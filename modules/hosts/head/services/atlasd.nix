# atlasd — head-side daemon for the Atlas client (:8644, loopback only).
#
# Remote shells (node0's Atlas app) relay /media and /api/attach requests to
# this instance through the atlas ssh tunnel (node0:8645 → head:8644): the
# files the agent references live here, so this is the origin that serves
# them. It also gives head a local Atlas daemon (browser access) with zero
# configuration — same binary, local-only mode (no ATLAS_UPSTREAM).
#
# Access model (see cmd/atlasd/relay.go): absolute paths only, symlink-
# resolved, restricted to /tmp + the hermes user's ~/.hermes, image
# extensions only. Pastes land in .hermes/cache/atlas-inbox.
{ inputs, ... }:
{
  flake.nixosModules.headAtlasd =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hermesState = "/mnt/cache/appdata/hermes-agent";
      atlasd = lib.getExe' inputs.atlas.packages.${pkgs.stdenv.hostPlatform.system}.default "atlasd";
    in
    {
      config = {
        systemd.services.atlasd = {
          description = "Atlas daemon (:8644, media/attach relay for remote shells)";
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            User = "hermes";
            Group = "hermes";
            ExecStart = "${atlasd} -addr 127.0.0.1 -port 8644";
            Restart = "on-failure";
            RestartSec = "5s";
            TimeoutStopSec = "10s";

            # Sandboxing — read-only filesystem except the paste inbox
            # (.hermes/cache holds agent scratch + atlas-inbox). No
            # PrivateTmp on purpose: the /media allowlist includes /tmp so
            # agent-saved screenshots there stay renderable in the app.
            CapabilityBoundingSet = "";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            ReadWritePaths = [
              "${hermesState}/.hermes/cache"
            ];
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
          };
        };
      };
    };
}
