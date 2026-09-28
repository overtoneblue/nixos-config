{ inputs, ... }:
{
  flake.nixosModules.headAtlasHub =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hermesState = "/mnt/cache/appdata/hermes-agent/.hermes";
    in
    {
      config = {
        systemd.services.atlas-hub = {
          description = "Atlas hub daemon (:8643, workstream tree, read-only derivations)";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];

          environment = {
            HERMES_HOME = hermesState;
          };

          serviceConfig = {
            User = "hermes";
            Group = "hermes";
            ExecStart =
              "${lib.getExe pkgs.python3} ${inputs.atlas}/hub/atlas-hub.py";
            Restart = "on-failure";
            RestartSec = "10s";
            TimeoutStopSec = "10s";

            # Read-only access to hermes state (./env for tokens, state.db for
            # session data, profiles/ for sub-profile registries). No write
            # paths, no media access.
            UMask = "0077";

            # Sandboxing — minimal surface for a read-only Python HTTP server.
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
            ReadOnlyPaths = [
              hermesState
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