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
          "opencode-server-password" = {
            restartUnits = [ "opencode.service" ];
          };
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
          # Also sourced by the opencode-client wrapper.
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

      environment.systemPackages = [
        pkgs.sops
        pkgs.age
        pkgs.ssh-to-age
      ];
    };
}
