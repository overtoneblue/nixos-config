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
        certs."files.cenunix.dev" = {
          domain = "files.cenunix.dev";
        };
        # Matrix homeserver + apex federation delegation (added 2026-09-11;
        # the apex serves only /.well-known/matrix/server).
        certs."matrix.cenunix.dev" = {
          domain = "matrix.cenunix.dev";
        };
        certs."cenunix.dev" = {
          domain = "cenunix.dev";
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
        virtualHosts."files.cenunix.dev" = {
          forceSSL = true;
          useACMEHost = "files.cenunix.dev";
          locations."/" = {
            # Upstream = LSIO container's own TLS on the 4143->443 mapping
            # (restored self-signed cert) — proxy_ssl_verify off is deliberate.
            proxyPass = "https://127.0.0.1:4143";
            extraConfig = ''
              proxy_ssl_verify off;
              client_max_body_size 0;
              add_header Strict-Transport-Security "max-age=15552000" always;
            '';
          };
        };

        # Matrix homeserver ingress (added 2026-09-11): synapse listens on
        # 127.0.0.1:8008; client + federation traffic terminate here.
        virtualHosts."matrix.cenunix.dev" = {
          forceSSL = true;
          useACMEHost = "matrix.cenunix.dev";
          locations."~ ^(/_matrix|/_synapse/client)" = {
            proxyPass = "http://127.0.0.1:8008";
            proxyWebsockets = true;
            extraConfig = ''
              client_max_body_size 100M;
            '';
          };
          locations."/" = {
            proxyPass = "http://127.0.0.1:8008";
            proxyWebsockets = true;
            extraConfig = ''
              client_max_body_size 100M;
            '';
          };
        };

        # Apex (cenunix.dev): ONLY federation delegation is served; all other
        # paths return 404.
        virtualHosts."cenunix.dev" = {
          forceSSL = true;
          useACMEHost = "cenunix.dev";
          locations."/.well-known/matrix/server" = {
            extraConfig = ''
              default_type application/json;
              add_header Access-Control-Allow-Origin "*";
              return 200 '{"m.server": "matrix.cenunix.dev:443"}';
            '';
          };
          locations."/" = {
            extraConfig = ''
              return 404;
            '';
          };
        };
      };

      # Expose the public web ports (nginx serves 80/443).
      networking.firewall.allowedTCPPorts = [ 80 443 ];
    };
}
