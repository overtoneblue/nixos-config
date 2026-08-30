{ self, ... }:
# Nextcloud restore on head as OCI containers, matching the recovered Unraid
# templates (my-nextcloud.xml + my-nextcloud-sql.xml).
#
# Containers (not native NixOS services) are the deliberate choice here, for
# the same reason documented in jellyfin.nix: the migrated data is
# Docker-native (LSIO nextcloud webroot + official postgres:15 cluster at
# fixed versions), so running the exact same images against the restored
# volumes restores 1:1 with zero version migration or config rewrite.
#
# Layout matches the templates exactly:
#   - /config  -> /mnt/cache/appdata/nextcloud       (restored appdata)
#   - /data    -> /mnt/cache/personal/nextcloud      (restored user files)
#   - PGDATA   -> /mnt/cache/appdata/postgres        (restored PG15 cluster)
#
# Both containers share a user-defined docker bridge ("cenunet") so the
# restored config.php keeps working untouched: dbhost = nextcloud-sql:5432
# resolves by container name, and the DB port is never exposed to the host.
# WebUI stays on the original 4143 -> 443 mapping; head's LAN IP (10.1.1.24)
# is already present in the restored trusted_domains, so direct LAN access
# works with no config.php edits.
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
          # Temporarily deactivated (2026-08-29) — services on hold, config kept.
          autoStart = false;
          # Restored PG15 cluster. No `user` override: the official image
          # already runs as its own postgres user (uid 999), which is exactly
          # the owner of the migrated data — no chown needed on the host.
          volumes = [ "/mnt/cache/appdata/postgres:/var/lib/postgresql/data" ];
          networks = [ containerNetwork ];
        };

        containers."nextcloud" = {
          image = "lscr.io/linuxserver/nextcloud:version-32.0.6";
          # Temporarily deactivated (2026-08-29) — services on hold, config kept.
          autoStart = false;
          # LSIO images honor PUID/PGID via s6 (init still runs as root so
          # fix-perms works); matches the restored data ownership 99:100.
          environment = {
            PUID = "99";
            PGID = "100";
            UMASK = "022";
            NEXTCLOUD_TRUSTED_DOMAINS = "files.cenunix.dev";
          };
          # WebUI, original port (container's own TLS, self-signed from
          # restored /config/keys).
          ports = [ "4143:443" ];
          volumes = [
            "/mnt/cache/appdata/nextcloud:/config"
            "/mnt/cache/personal/nextcloud:/data"
          ];
          networks = [ containerNetwork ];
          dependsOn = [ "nextcloud-sql" ];
        };
      };

      # ── Declarative docker bridge network ────────────────────────────
      # oci-containers' `networks` option only ATTACHES (docker run
      # --network=...); it does not create the network. Ensure cenunet
      # exists before either container starts; idempotent, so it also
      # self-heals on a fresh docker daemon.
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

      # Containers must wait for the network to exist.
      systemd.services."docker-nextcloud-sql" = {
        requires = [ "docker-network-${containerNetwork}.service" ];
        after = [ "docker-network-${containerNetwork}.service" ];
      };
      systemd.services."docker-nextcloud" = {
        requires = [ "docker-network-${containerNetwork}.service" ];
        after = [ "docker-network-${containerNetwork}.service" ];
      };

      # ── LAN exposure ─────────────────────────────────────────────────
      # Direct LAN WebUI on the original port (self-signed TLS, same as the
      # old 10.1.1.24:4143 access path). No public/Cloudflare-facing nginx
      # vhost or LE cert: this instance stays inside the house.
      networking.firewall.allowedTCPPorts = [ 4143 ];
    };
}
