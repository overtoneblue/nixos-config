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

        # Secrets consumed by the templates below (secrets/head.yaml may hold
        # further, currently unused keys). Raw secret files are only read by
        # sops-install-secrets (root) to render the templates, so the sops
        # default owner=root mode=0400 is correct for every entry; the
        # consumer-readable permissions live on the templates, not the raw
        # secrets. restartUnits are attached per-secret so a changed value
        # restarts exactly the services that consume it (via the template it
        # feeds) — never an unrelated unit.
        secrets = {
          # ── consumed by the opencode-env template ──
          "opencode-server-password" = {
            restartUnits = [ "opencode.service" ];
          };
          # Shared by the opencode-env and pi-env templates, so a change must
          # restart every consumer.
          "makora-api-key" = {
            restartUnits = [
              "opencode.service"
              "pi.service"
            ];
          };
          "deepseek-api-key" = {
            restartUnits = [
              "opencode.service"
              "pi.service"
            ];
          };
        };

        templates = {
          # Rendered .env consumed by the opencode systemd service
          # (EnvironmentFile) AND sourced by the opencode-client wrapper.
          # Owner-only: overtoneblue reads it, nobody else.
          "opencode-env" = {
            owner = "overtoneblue";
            group = "users";
            mode = "0400";
            content = ''
              OPENCODE_SERVER_PASSWORD=${ph."opencode-server-password"}
              MAKORA_API_KEY=${ph."makora-api-key"}
              DEEPSEEK_API_KEY=${ph."deepseek-api-key"}
            '';
          };

          # Rendered .env consumed by the pi systemd service
          # (services/pi.nix: EnvironmentFile). Same boundary as opencode-env.
          "pi-env" = {
            owner = "overtoneblue";
            group = "users";
            mode = "0400";
            content = ''
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
