{ self, ... }:
# wavegen-web: web UI for WaveSpeedAI image editing (packages/wavegen-web).
# The old Matrix bot (headWavegen) was removed 2026-10-14.
{
  # Port 8443 isn't opened in the firewall, so it is only reachable over the
  # tailnet.
  flake.nixosModules.headWavegenWeb =
    { config, lib, pkgs, ... }:
    let
      ph = config.sops.placeholder;
    in
    {
      imports = [ ];

      sops.secrets = {
        "wavespeed-api-key" = {
          restartUnits = [ "wavegen-web.service" ];
        };
        "wavegen-web-password" = {
          restartUnits = [ "wavegen-web.service" ];
        };
      };

      sops.templates."wavegen-web-env" = {
        owner = "wavegen-web";
        group = "wavegen-web";
        mode = "0440";
        content = ''
          WAVEGEN_WEB_WAVESPEED_API_KEY=${ph."wavespeed-api-key"}
          WAVEGEN_WEB_PASSWORD=${ph."wavegen-web-password"}
        '';
      };

      users.users.wavegen-web = {
        isSystemUser = true;
        group = "wavegen-web";
        home = "/var/lib/wavegen-web";
        createHome = true;
      };
      users.groups.wavegen-web = {};

      systemd.services.wavegen-web = {
        description = "wavegen-web — Web UI for WaveSpeedAI image editing";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          ExecStart = "${lib.getExe self.packages.${pkgs.system}.wavegen-web}";
          User = "wavegen-web";
          Group = "wavegen-web";
          WorkingDirectory = "/var/lib/wavegen-web";
          Restart = "on-failure";
          RestartSec = "5";

          EnvironmentFile = config.sops.templates."wavegen-web-env".path;

          Environment = [
            "WAVEGEN_WEB_CONCURRENCY=4"
            "WAVEGEN_WEB_PORT=8443"
            "WAVEGEN_WEB_STATE=/var/lib/wavegen-web"
            "WAVEGEN_WEB_POLL_TIMEOUT=300"
          ];

          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = "/var/lib/wavegen-web";
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          CapabilityBoundingSet = [ "" ];
          RestrictSUIDSGID = true;
        };
      };
    };
}