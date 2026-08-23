{ ... }:
{
  flake.nixosModules.headOpenCode =
    {
      config,
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
    in
    {
      systemd.tmpfiles.rules = [
        "d ${repository} 0750 ${user} users - -"
        "d ${stateDir} 0700 ${user} users - -"
        "d ${homeDir} 0700 ${user} users - -"
        "d ${configDir} 0700 ${user} users - -"
        "d ${dataDir} 0700 ${user} users - -"
        "d ${runtimeStateDir} 0700 ${user} users - -"
        "d ${cacheDir} 0700 ${user} users - -"
      ];

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
}
