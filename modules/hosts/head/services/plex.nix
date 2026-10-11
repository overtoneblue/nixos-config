{ self, ... }:
# Plex, restored from the Unraid binhex-plexpass appdata (same image family,
# pinned to the version that last ran there, so the library DB needs no
# migration). Library paths are the ones the DB already has:
#   /downloads/content/{Movies,TV Shows}  same tree Jellyfin reads
#   /mymusic                              Unraid's /mnt/user/music/organized
# Media mounts are read-only. Music is served straight from the Unraid backup
# copy (/mnt/user has no room for it); read-only keeps the backup pristine.
# The Remux library's source (/mnt/user/music/remux) wasn't migrated, so it
# shows as unavailable.
#
# Public at https://play.cenunix.dev (nginx-proxy.nix). Preferences.xml has
# customConnections = http://10.1.1.24:32400, https://play.cenunix.dev:443
# (plus the dead NPM-era proxy.cenunix.dev) and
# LanNetworksBandwidth = 10.1.1.0/24 so LAN clients connect and count as local;
# proxied clients arrive from the docker bridge and count as remote.
{
  flake.nixosModules.headPlex =
    { ... }:
    {
      virtualisation.oci-containers = {
        backend = "docker";
        containers.plex = {
          image = "binhex/arch-plexpass:1.43.0.10346-1-01";
          autoStart = true;
          environment = {
            TZ = "America/Los_Angeles";
            # Same as on Unraid; the restored appdata is owned 99:100.
            PUID = "99";
            PGID = "100";
            UMASK = "000";
            TRANS_DIR = "/config/transcode";
          };
          # Docker-published ports bypass nixos-fw. The router still forwards
          # WAN 32400 here (Unraid-era rule; head kept Unraid's 10.1.1.24), so
          # this is Plex Remote Access via plex.tv: reachable from the internet,
          # plex.tv-authenticated. Remove the router rule or turn off Remote
          # Access in Plex to make it LAN-only.
          ports = [ "32400:32400" ];
          volumes = [
            "/mnt/cache/appdata/binhex-plexpass:/config"
            "/mnt/user/media/qbit/downloads:/downloads:ro"
            "/mnt/cache/fullbackup/cache/music/organized:/mymusic:ro"
          ];
          # Hardware transcoding (Preferences pins the iGPU at 0000:00:02.0).
          devices = [ "/dev/dri:/dev/dri" ];
          # Docker's default 10s stop timeout can kill Plex mid DB write.
          extraOptions = [ "--stop-timeout=60" ];
        };
      };
    };
}
