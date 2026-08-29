{ self, ... }:
# Public reverse proxy for head services behind the cenunix.dev domain,
# restoring what Nginx Proxy Manager provided on the old Tower — implemented
# natively with NixOS nginx + Let's Encrypt via Cloudflare DNS-01.
#
# TLS strategy: DNS-01 on the Cloudflare zone (works regardless of router
# port-80 forwarding, matches the old cert's issuance method). The Cloudflare
# credential is a scoped Zone-DNS-Write API token (NOT the global account
# key), stashed in secrets/head-cf.yaml encrypted to head's own age identity
# plus the operator recipient. Head's SSH host key decrypts it at activation.
{
  flake.nixosModules.headNginxProxy =
    { config, ... }:
    {
      # ── Cloudflare DNS-01 credential (sops) ──────────────────────
      sops.secrets."cloudflare-api-token" = {
        sopsFile = "/srv/nixos-config/secrets/head-cf.yaml";
        owner = "acme";
        mode = "0400";
      };

      # acme's lego service consumes `environmentFile` (KEY=VALUE format),
      # so render the token as an EnvironmentFile via a sops template.
      sops.templates."cloudflare-credentials" = {
        owner = "acme";
        group = "acme";
        mode = "0400";
        content = ''
          CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder."cloudflare-api-token"}
        '';
      };

      # ── Let's Encrypt, DNS-01 via Cloudflare ─────────────────────
      security.acme = {
        acceptTerms = true;
        defaults = {
          email = "caden.hargrave@gmail.com";
          dnsProvider = "cloudflare";
          environmentFile = config.sops.templates."cloudflare-credentials".path;
          # nginx reads the cert files from /var/lib/acme/<cert>
          group = "nginx";
        };
        certs."jelly.cenunix.dev" = {
          domain = "jelly.cenunix.dev";
        };
      };

      # ── nginx reverse proxy ──────────────────────────────────────
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        virtualHosts."jelly.cenunix.dev" = {
          forceSSL = true;
          useACMEHost = "jelly.cenunix.dev";
          locations."/" = {
            proxyPass = "http://127.0.0.1:8096";
            proxyWebsockets = true;
            extraConfig = ''
              client_max_body_size 500M;
              proxy_buffering off;
              proxy_request_buffering off;
            '';
          };
        };
      };

      # Expose the public web ports (nginx serves 80/443).
      networking.firewall.allowedTCPPorts = [ 80 443 ];
    };
}
