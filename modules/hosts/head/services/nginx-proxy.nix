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
          # lego's propagation check otherwise asks resolv.conf's first server,
          # the router (10.1.1.1), which caches the challenge record's NXDOMAIN
          # for up to the zone's 30 min negative TTL and fails the 2 min wait.
          dnsResolver = "1.1.1.1:53";
          # nginx reads the cert files from /var/lib/acme/<cert>
          group = "nginx";
        };
        certs."jelly.cenunix.dev" = {
          domain = "jelly.cenunix.dev";
        };
        certs."play.cenunix.dev" = {
          domain = "play.cenunix.dev";
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
        # Catch-all for requests that match no vhost (bare IP, stale or
        # unknown hostnames): refuse the TLS handshake instead of presenting
        # some other site's cert, and close plain-HTTP connections.
        virtualHosts."_" = {
          default = true;
          rejectSSL = true;
          locations."/".return = "444";
        };

        # Nextcloud is tailnet-only (nextcloud.nix); no public vhost.

        # Plex (plex.nix). Clients learn this URL from customConnections
        # (https://play.cenunix.dev:443) in Preferences.xml via plex.tv.
        virtualHosts."play.cenunix.dev" = {
          forceSSL = true;
          useACMEHost = "play.cenunix.dev";
          locations."/" = {
            proxyPass = "http://127.0.0.1:32400";
            proxyWebsockets = true;
            extraConfig = ''
              client_max_body_size 100M;
              proxy_buffering off;
              proxy_request_buffering off;
              # Notification streams and websockets sit idle for long stretches.
              proxy_read_timeout 1h;
              proxy_send_timeout 1h;
            '';
          };
        };

        # Matrix is private (matrix.nix: loopback + tailnet only); no
        # matrix.cenunix.dev or apex delegation vhost.
      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];
    };
}
