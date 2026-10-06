{ inputs, ... }:
{
  flake.nixosModules.headSops =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Placeholders filled in at activation. Never inline a literal secret.
      ph = config.sops.placeholder;
    in
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
      ];

      # Decrypts with the host SSH key (the head age recipient in .sops.yaml).
      #
      # secrets/head.yaml is read live from the checkout at activation instead
      # of being copied into the store, so validateSopsFiles must be false
      # (sops-nix otherwise requires a store path). Restart-on-change still
      # works: sops-install-secrets compares decrypted values at activation.
      sops = {
        defaultSopsFile = "/srv/nixos-config/secrets/head.yaml";
        validateSopsFiles = false;
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

        # Raw secrets stay root-only; consumers read the templates below.
        # restartUnits must list every service whose template uses the key.
        secrets = {
          # Discord webhook for #build-logs; read by head-rebuild-run as root.
          # Nothing caches it, so no restartUnits.
          "build-logs-webhook" = { };
          "opencode-server-password" = {
            restartUnits = [ "opencode.service" ];
          };
          "makora-api-key" = {
            restartUnits = [
              "opencode.service"
              "pi.service"
            ];
          };
          # Shared by the opencode-env, pi-env and hermes-env templates, so a
          # change must restart every consumer.
          "deepseek-api-key" = {
            restartUnits = [
              "opencode.service"
              "hermes-agent.service"
              "pi.service"
            ];
          };

          # ── consumed by the hermes-env template ──
          "hermes-makora-api-key" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "google-api-key" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "hermes-dashboard-username" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "hermes-dashboard-password" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "hermes-dashboard-secret" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "telegram-bot-token" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "discord-bot-token" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "matrix-nolan-access-token" = {
            sopsFile = "/srv/nixos-config/secrets/head-matrix-bots.yaml";
            restartUnits = [ "hermes-agent.service" ];
          };
          "hf-token" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "hermes-auxiliary-vision-api-key" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "friendli-api-key" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "openrouter-api-key" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "hermes-databricks-api-key" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "orcarouter-api-key" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          # API server bearer key for the atlas TUI (loopback :8642).
          "hermes-api-server-key" = {
            restartUnits = [ "hermes-agent.service" ];
          };

          # ── Hermes Desktop backend session token ──
          # Fixed session token for `hermes serve` (HERMES_DASHBOARD_SESSION_TOKEN)
          # so the desktop app can authenticate to the head backend across
          # restarts (serve generates an ephemeral random one otherwise, and the
          # headless serve has no web UI to hand it out). Rendered into the
          # hermes-env template → ~/.hermes/.env, which every hermes process
          # (gateway, serve, TUI) loads at startup; restart both consumers.
          "hermes-serve-session-token" = {
            restartUnits = [
              "hermes-agent.service"
              "hermes-serve.service"
            ];
          };

          # ── hermes→node0 desktop SSH identity ──
          # Reuses the already-authorized desktop_ed25519 key so no node0
          # authorized-keys change is needed. Rendered as a private FILE secret
          # (not an env/template value) at /run/secrets/hermes-desktop-key,
          # 0400 hermes:hermes, injected by name into the desktop bridge via
          # DESKTOP_SSH_KEY on the hermes-agent unit. Host verification uses
          # the declarative system known_hosts (programs.ssh.knownHosts), not
          # a secret — see modules/hosts/head/configuration.nix.
          "hermes-desktop-key" = {
            owner = "hermes";
            group = "hermes";
            mode = "0400";
            restartUnits = [ "hermes-agent.service" ];
          };

          # ── nix flake-input auth (github:overtoneblue/atlas) ──
          # Read-only GitHub PAT consumed by the nix-access-tokens template.
          # The atlas repo is public since 2026-09-28, so this is currently
          # a no-op safety net for a possible re-privatization; every nix
          # CLI reads the rendered snippet per invocation, so rotating or
          # revoking the value requires no unit restarts.
          "atlas-read-token" = {
            restartUnits = [ ];
          };
        };

        templates = {
          # Not read by the service directly: hermes-agent's activation script
          # merges it into /mnt/cache/appdata/hermes-agent/.hermes/.env, which
          # hermes loads.
          "hermes-env" = {
            owner = "hermes";
            group = "hermes";
            mode = "0440";
            content = ''
              DEEPSEEK_API_KEY=${ph."deepseek-api-key"}
              HERMES_CUSTOM_INFERENCE_MAKORA_COM_API_KEY=${ph."hermes-makora-api-key"}
              GOOGLE_API_KEY=${ph."google-api-key"}
              HERMES_DASHBOARD_BASIC_AUTH_USERNAME=${ph."hermes-dashboard-username"}
              HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=${ph."hermes-dashboard-password"}
              HERMES_DASHBOARD_BASIC_AUTH_SECRET=${ph."hermes-dashboard-secret"}
              TELEGRAM_BOT_TOKEN=${ph."telegram-bot-token"}
              DISCORD_BOT_TOKEN=${ph."discord-bot-token"}
              MATRIX_ACCESS_TOKEN=${ph."matrix-nolan-access-token"}
              HF_TOKEN=${ph."hf-token"}
              HERMES_AUXILIARY_VISION_API_KEY=${ph."hermes-auxiliary-vision-api-key"}
              FRIENDLI_API_KEY=${ph."friendli-api-key"}
              OPENROUTER_API_KEY=${ph."openrouter-api-key"}
              ORCAROUTER_API_KEY=${ph."orcarouter-api-key"}
              HERMES_DATABRICKS_API_KEY=${ph."hermes-databricks-api-key"}
              HERMES_DASHBOARD_SESSION_TOKEN=${ph."hermes-serve-session-token"}
              API_SERVER_ENABLED=true
              API_SERVER_KEY=${ph."hermes-api-server-key"}
            '';
          };

          # Also sourced by the opencode-client wrapper (run by overtoneblue
          # and by the hermes gateway, hence group hermes).
          "opencode-env" = {
            owner = "overtoneblue";
            group = "hermes";
            mode = "0640";
            content = ''
              OPENCODE_SERVER_PASSWORD=${ph."opencode-server-password"}
              MAKORA_API_KEY=${ph."makora-api-key"}
              DEEPSEEK_API_KEY=${ph."deepseek-api-key"}
            '';
          };

          "pi-env" = {
            owner = "overtoneblue";
            group = "hermes";
            mode = "0640";
            content = ''
              MAKORA_API_KEY=${ph."makora-api-key"}
              DEEPSEEK_API_KEY=${ph."deepseek-api-key"}
            '';
          };

          # nix.conf snippet with the repo access token, read via `!include`
          # (see configuration.nix) by every nix CLI on head: root for
          # system fetches, hermes for `nh os build` gates. Currently a
          # no-op (atlas is public); kept for re-privatization. Rendered
          # root:hermes 0640 — other users' nix runs silently skip it (nix
          # tolerates unreadable include targets).
          "nix-access-tokens" = {
            owner = "root";
            group = "hermes";
            mode = "0640";
            content = ''
              access-tokens = github.com=${ph."atlas-read-token"}
            '';
          };
        };
      };

      environment.systemPackages = [
        pkgs.sops
        pkgs.age
        pkgs.ssh-to-age
      ];
    };
}
