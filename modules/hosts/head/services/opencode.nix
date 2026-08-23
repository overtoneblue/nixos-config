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
      environmentFile = "${stateDir}/server.env";

      # Client wrapper command — sources the runtime-only server.env (sets
      # OPENCODE_SERVER_PASSWORD etc.) then execs the real OpenCode CLI.
      # Usable from the interactive user AND the hermes gateway.
      # `set -a` ensures the sourced vars are exported to the child CLI
      # process (sourcing without it leaves them shell-only => client 401s).
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
        description = "OpenCode client wrapper package (sources server.env).";
      };

      config = {
        # Runtime-only credential for OpenCode *clients* (CLI against the
        # persistent backend). The server reads the same file via systemd
        # EnvironmentFile; the wrapper sources it for client invocations.
        # Group `hermes` (the gateway service user) is granted read-only access
        # so both the interactive user and the hermes gateway can use the CLI
        # without ever typing the password. Never world-readable; never in Git.
        systemd.tmpfiles.rules = [
          "d ${repository} 2770 ${user} admin - -"
          "z ${stateDir} 0750 ${user} hermes - -"
          "z ${environmentFile} 0640 ${user} hermes - -"
          "z ${homeDir} 0700 ${user} hermes - -"
          "z ${configDir} 0700 ${user} hermes - -"
          "z ${dataDir} 0700 ${user} hermes - -"
          "z ${runtimeStateDir} 0700 ${user} hermes - -"
          "z ${cacheDir} 0700 ${user} hermes - -"
        ];

        # Expose the wrapper to other modules: interactive systemPackages
        # (overtoneblue TUI) and hermes-agent extraPackages (gateway PATH).
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
            UMask = "0077";

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
              "/mnt/cache/appdata/hermes-agent"
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
