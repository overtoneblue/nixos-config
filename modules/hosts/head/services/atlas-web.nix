# atlas-web — the tailnet-facing Atlas instance for Caden's phone (:8646).
#
# Same binary as atlasd (:8644, loopback), plus -web serving the static
# bundle: the phone opens it in Safari and can Add to Home Screen (PWA:
# manifest, icons, standalone display). Same UI + same API as the desktop
# app — no relay, no separate login.
#
# Access model: bound to head's tailscale address only. tailscale0 is a
# trusted firewall interface, so tailnet devices (the phone) reach it and
# nothing on the LAN does — no public ingress, no extra auth layer while it
# stays tailnet-only. Upstreams are head's own services on loopback
# (hub :8643, api :8642), same as the desktop app.
{ inputs, ... }:
{
  flake.nixosModules.headAtlasWeb =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hermesState = "/mnt/cache/appdata/hermes-agent";
      atlas = inputs.atlas.packages.${pkgs.stdenv.hostPlatform.system};
      atlasd = lib.getExe' atlas.default "atlasd";
      webDir = atlas.atlas-web;
      tailnetAddr = "100.91.71.44"; # head's tailscale IPv4 (stable per tailnet)
    in
    {
      config = {
        systemd.services.atlas-web = {
          description = "Atlas web UI, phone surface (:8646, tailnet only)";
          wantedBy = [ "multi-user.target" ];
          after = [ "tailscaled.service" ];
          wants = [ "tailscaled.service" ];
          # The tailnet address only exists once tailscaled is up; retry
          # forever instead of tripping systemd's start limit.
          unitConfig.StartLimitIntervalSec = 0;

          serviceConfig = {
            User = "hermes";
            Group = "hermes";
            ExecStart = "${atlasd} -addr ${tailnetAddr} -port 8646 -web ${webDir}";
            Restart = "always";
            RestartSec = "5s";
            TimeoutStopSec = "10s";

            # Same sandbox as atlasd (see atlasd.nix): read-only filesystem
            # except the paste inbox (.hermes/cache). No PrivateTmp on
            # purpose — the /media allowlist includes /tmp.
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
