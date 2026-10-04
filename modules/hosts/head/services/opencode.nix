{ ... }:
{
  flake.nixosModules.headOpenCode =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      user = config.modules.system.username;
      repository = "/srv/nixos-config";
      stateDir = "/mnt/cache/appdata/opencode";
      homeDir = "${stateDir}/home";
      configDir = "${stateDir}/config";
      dataDir = "${stateDir}/data";
      runtimeStateDir = "${stateDir}/state";
      cacheDir = "${stateDir}/cache";
      # Rendered by sops (see services/sops.nix).
      environmentFile = config.sops.templates."opencode-env".path;

      # Loads the server password, then runs the real CLI. Without `set -a`
      # the sourced vars aren't exported and the client gets 401s.
      opencodeClient = pkgs.writeShellScriptBin "opencode-client" ''
        set -a
        if [ -r "${environmentFile}" ]; then
          . "${environmentFile}"
        fi
        set +a
        exec "${pkgs.opencode}/bin/opencode" "$@"
      '';
    in
    {
      options.services.opencode-client.package = lib.mkOption {
        type = lib.types.package;
        default = opencodeClient;
        description = "OpenCode client wrapper package (sources the sops-rendered opencode-env template).";
      };

      config = {
        # The repo's opencode.jsonc is overwritten on every switch; the repo
        # is the source of truth.
        system.activationScripts."opencode-config" = lib.stringAfter [ "users" ] ''
          mkdir -p ${configDir}/opencode
          install -o ${user} -g users -m 0640 \
            ${../../../../opencode.jsonc} \
            ${configDir}/opencode/opencode.jsonc
        '';

        systemd.tmpfiles.rules = [
          "d ${repository} 2770 ${user} admin - -"
          "z ${stateDir} 0750 ${user} users - -"
          "z ${homeDir} 0700 ${user} users - -"
          "z ${configDir} 0700 ${user} users - -"
          "z ${dataDir} 0700 ${user} users - -"
          "z ${runtimeStateDir} 0700 ${user} users - -"
          "z ${cacheDir} 0700 ${user} users - -"
        ];

        environment.systemPackages = [ config.services.opencode-client.package ];

        systemd.services.opencode = {
          description = "OpenCode persistent backend";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          requires = [ "mnt-cache.mount" ];
          after = [
            "mnt-cache.mount"
            "network-online.target"
          ];

          path = with pkgs; [
            bashInteractive
            coreutils
            fd
            git
            jq
            nix
            openssh
            ripgrep
          ];

          environment = {
            HOME = homeDir;
            XDG_CONFIG_HOME = configDir;
            XDG_DATA_HOME = dataDir;
            XDG_STATE_HOME = runtimeStateDir;
            XDG_CACHE_HOME = cacheDir;
          };

          unitConfig = {
            ConditionPathExists = environmentFile;
            RequiresMountsFor = [
              repository
              stateDir
            ];
          };

          serviceConfig = {
            User = user;
            Group = "users";
            WorkingDirectory = repository;
            EnvironmentFile = environmentFile;
            ExecStart = "${pkgs.opencode}/bin/opencode serve --hostname 127.0.0.1 --port 4096";
            Restart = "always";
            RestartSec = "5s";
            TimeoutStopSec = "30s";
            # Keeps files it writes in the setgid repo group-writable for admin.
            UMask = "0007";

            CapabilityBoundingSet = "";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            ReadWritePaths = [
              repository
              stateDir
            ];
            InaccessiblePaths = [
              # Leftover Hermes state (credentials) until it is archived.
              "-/mnt/cache/appdata/hermes-agent"
              "-/mnt/user"
              "-/mnt/disk1"
              "-/mnt/disk2"
              "-/mnt/disk3"
              "-/run/docker.sock"
              "-/var/run/docker.sock"
              "-/run/wrappers/bin/sudo"
            ];
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
          };
        };
      };
    };
}
