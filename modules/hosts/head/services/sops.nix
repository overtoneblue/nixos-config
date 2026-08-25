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
      # Substitution tokens rendered by sops-install-secrets at activation.
      # Each maps to a value decrypted from secrets/head.yaml; never inline a
      # literal secret here — only these placeholder references.
      ph = config.sops.placeholder;
    in
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
      ];

      # Decryption identity: the head SSH host key, converted to an age
      # identity via ssh-to-age at activation. The matching age recipient is
      # already declared in .sops.yaml (age13cyh... head machine key).
      #
      # secrets/head.yaml is gitignored (it stays out of the nix store and is
      # read live from /srv/nixos-config at activation), so defaultSopsFile uses
      # the absolute path and validateSopsFiles is false: sops-nix otherwise
      # requires sops files to be store paths and would hash the file at eval
      # time. Restart-on-change still works — sops-install-secrets compares
      # decrypted values across generations at activation, not at build time.
      sops = {
        defaultSopsFile = "/srv/nixos-config/secrets/head.yaml";
        validateSopsFiles = false;
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

        # All top-level keys of secrets/head.yaml. Raw secret files are
        # only read by sops-install-secrets (root) to render the templates
        # below, so the sops default owner=root mode=0400 is correct for every
        # entry; the consumer-readable permissions live on the templates, not
        # the raw secrets. restartUnits are attached per-secret so a changed
        # value restarts exactly the services that consume it (via the template
        # it feeds) — never an unrelated unit.
        secrets = {
          # ── consumed by the opencode-env template ──
          "opencode-server-password" = {
            restartUnits = [ "opencode.service" ];
          };
          "makora-api-key" = {
            restartUnits = [ "opencode.service" ];
          };
          # Shared by both templates (DEEPSEEK_API_KEY appears in opencode-env
          # and hermes-env), so a change must restart both consumers.
          "deepseek-api-key" = {
            restartUnits = [
              "opencode.service"
              "hermes-agent.service"
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
          "hf-token" = {
            restartUnits = [ "hermes-agent.service" ];
          };
          "hermes-auxiliary-vision-api-key" = {
            restartUnits = [ "hermes-agent.service" ];
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
        };

        templates = {
          # Rendered .env consumed by services.hermes-agent.environmentFiles.
          # The upstream hermes-agent activation script (hermes-agent-setup,
          # ordered after setupSecrets) merges this file into
          # /mnt/cache/appdata/hermes-agent/.hermes/.env (hermes:hermes 0640)
          # and hermes reads that .env at startup — so the service never reads
          # this template directly. Owner/group stay inside the hermes boundary
          # regardless; mode 0440 keeps it hermes-readable without world access.
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
              HF_TOKEN=${ph."hf-token"}
              HERMES_AUXILIARY_VISION_API_KEY=${ph."hermes-auxiliary-vision-api-key"}
            '';
          };

          # Rendered .env consumed by the opencode systemd service
          # (EnvironmentFile) AND sourced by the opencode-client wrapper, which
          # both overtoneblue (interactive) and hermes (gateway) exec. This
          # preserves the prior hand-maintained server.env boundary exactly:
          # owner overtoneblue, group hermes, mode 0640 — overtoneblue owns it,
          # the hermes group reads it, nobody else.
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
        };
      };

      # Operator tooling so admins can encrypt/edit sops files on-head.
      environment.systemPackages = [
        pkgs.sops
        pkgs.age
        pkgs.ssh-to-age
      ];
    };
}
