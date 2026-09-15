{ self, ... }:
# wavegen: standalone Matrix bot for WaveSpeedAI image editing.
# Zero-LLM, no Hermes integration, no public exposure.
# See packages/wavegen/wavegen.py.
{
  flake.nixosModules.headWavegen =
    { config, lib, pkgs, ... }:
    let
      ph = config.sops.placeholder;
    in
    {
      imports = [ ];

      # ── sops secrets ──────────────────────────────────────────────────
      # WAVESPEED_API_KEY  from secrets/head.yaml (defaultSopsFile)
      # WAVEGEN_MATRIX_TOKEN from secrets/head-matrix-bots.yaml
      sops.secrets = {
        "wavespeed-api-key" = {
          restartUnits = [ "wavegen.service" ];
        };
        "matrix-wavegen-access-token" = {
          sopsFile = "/srv/nixos-config/secrets/head-matrix-bots.yaml";
          restartUnits = [ "wavegen.service" ];
        };
      };

      sops.templates."wavegen-env" = {
        owner = "wavegen";
        group = "wavegen";
        mode = "0440";
        content = ''
          WAVEGEN_WAVESPEED_API_KEY=${ph."wavespeed-api-key"}
          WAVEGEN_MATRIX_TOKEN=${ph."matrix-wavegen-access-token"}
        '';
      };

      # ── System user ───────────────────────────────────────────────────
      users.users.wavegen = {
        isSystemUser = true;
        group = "wavegen";
        home = "/var/lib/wavegen";
        createHome = true;
      };
      users.groups.wavegen = {};

      # ── Service ───────────────────────────────────────────────────────
      systemd.services.wavegen = {
        description = "wavegen — Matrix bot for WaveSpeedAI image editing";
        after = [ "network-online.target" "matrix-synapse.service" ];
        wants = [ "network-online.target" "matrix-synapse.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          ExecStart = "${lib.getExe self.packages.${pkgs.system}.wavegen}";
          User = "wavegen";
          Group = "wavegen";
          WorkingDirectory = "/var/lib/wavegen";
          Restart = "on-failure";
          RestartSec = "5";

          # ── sops-rendered env ──
          EnvironmentFile = config.sops.templates."wavegen-env".path;

          # Declarative non-secret env
          Environment = [
            "WAVEGEN_HOMESERVER=http://127.0.0.1:8008"
            "WAVEGEN_MATRIX_USER=@wavegen:cenunix.dev"
            "WAVEGEN_ALLOWED_SENDER=@caden:cenunix.dev"
            "WAVEGEN_API_BASE=https://api.wavespeed.ai/api/v3"
            "WAVEGEN_MODEL=bytedance/seedream-v5.0-pro/edit"
            "WAVEGEN_STATE_DIR=/var/lib/wavegen"
            "WAVEGEN_POLL_TIMEOUT=300"
            "WAVEGEN_QUEUE_CAP=5"
            "WAVEGEN_PENDING_TTL=600"
            "WAVEGEN_FLUSH_GRACE=6"
          ];

          # ── Hardening ──
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = "/var/lib/wavegen";
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

  # ── wavegen-web: web UI for WaveSpeedAI image editing ─────────────
  # Starlette + uvicorn, queue with 2-parallel workers, history, retry,
  # single-password auth.  Tailnet-only on port 8443 (no firewall).
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
            "WAVEGEN_WEB_CONCURRENCY=2"
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