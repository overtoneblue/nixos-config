{ self, ... }:
# Containers rather than the native module: the data was migrated from
# Docker (LSIO nextcloud + postgres:15), so the same images run against it
# with no version migration or config rewrite.
#
# Both containers share the "cenunet" bridge so the restored config.php's
# dbhost = nextcloud-sql:5432 resolves by container name, and the DB port is
# never exposed to the host.
{
  flake.nixosModules.headNextcloud =
    { config, ... }:
    let
      containerNetwork = "cenunet";
    in
    {
      virtualisation.oci-containers = {
        backend = "docker";

        containers."nextcloud-sql" = {
          image = "postgres:15";
          autoStart = true;
          # No `user` override: the image's postgres uid (999) already owns
          # the migrated data.
          volumes = [ "/mnt/cache/appdata/postgres:/var/lib/postgresql/data" ];
          networks = [ containerNetwork ];
        };

        containers."nextcloud" = {
          image = "lscr.io/linuxserver/nextcloud:version-32.0.6";
          autoStart = true;
          # Matches the restored data ownership (99:100).
          environment = {
            PUID = "99";
            PGID = "100";
            UMASK = "022";
            NEXTCLOUD_TRUSTED_DOMAINS = "files.cenunix.dev";
          };
          # The container terminates TLS itself with a self-signed cert.
          ports = [ "4143:443" ];
          volumes = [
            "/mnt/cache/appdata/nextcloud:/config"
            "/mnt/cache/personal/nextcloud:/data"
          ];
          networks = [ containerNetwork ];
          dependsOn = [ "nextcloud-sql" ];
        };
      };

      # oci-containers' `networks` only attaches to a network; it never
      # creates one.
      systemd.services."docker-network-${containerNetwork}" = {
        description = "Ensure docker network ${containerNetwork} exists";
        wantedBy = [ "multi-user.target" ];
        before = [
          "docker-nextcloud.service"
          "docker-nextcloud-sql.service"
        ];
        path = [ config.virtualisation.docker.package ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          if ! docker network inspect ${containerNetwork} >/dev/null 2>&1; then
            docker network create ${containerNetwork}
          fi
        '';
      };

      systemd.services."docker-nextcloud-sql" = {
        requires = [ "docker-network-${containerNetwork}.service" ];
        after = [ "docker-network-${containerNetwork}.service" ];
      };
      systemd.services."docker-nextcloud" = {
        requires = [ "docker-network-${containerNetwork}.service" ];
        after = [ "docker-network-${containerNetwork}.service" ];
      };

      # Direct LAN access; public ingress is files.cenunix.dev in
      # nginx-proxy.nix.
      networking.firewall.allowedTCPPorts = [ 4143 ];
    };
}
