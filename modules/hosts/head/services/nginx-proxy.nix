{ self, ... }:
# Public reverse proxy for *.cenunix.dev. Certs use Cloudflare DNS-01 so
# issuance doesn't depend on the router forwarding port 80. The token is a
# scoped Zone-DNS-Write token, not the global account key.
{
  flake.nixosModules.headNginxProxy =
    { config, ... }:
    {
      sops.secrets."cloudflare-api-token" = {
        sopsFile = "/srv/nixos-config/secrets/head-cf.yaml";
        owner = "acme";
        mode = "0400";
      };

      # lego wants a KEY=VALUE environmentFile.
      sops.templates."cloudflare-credentials" = {
        owner = "acme";
        group = "acme";
        mode = "0400";
        content = ''
          CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder."cloudflare-api-token"}
        '';
      };

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
        certs."matrix.cenunix.dev" = {
          domain = "matrix.cenunix.dev";
        };
        certs."cenunix.dev" = {
          domain = "cenunix.dev";
        };
      };

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
            # The upstream cert is self-signed, hence proxy_ssl_verify off.
            proxyPass = "https://127.0.0.1:4143";
            extraConfig = ''
              proxy_ssl_verify off;
              client_max_body_size 0;
              add_header Strict-Transport-Security "max-age=15552000" always;
            '';
          };
        };

        # Client and federation traffic both terminate here.
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

        # The apex only serves Matrix federation delegation.
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

      networking.firewall.allowedTCPPorts = [ 80 443 ];
    };
}
