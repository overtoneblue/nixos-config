{ self, ... }:
# Container rather than the native module, to stay compatible with the old
# Unraid deployment.
{
  flake.nixosModules.headJellyfin =
    { ... }:
    {
      virtualisation.oci-containers = {
        backend = "docker";
        containers.jellyfin = {
          image = "jellyfin/jellyfin:unstable";
          autoStart = true;
          # The official image ignores PUID/PGID and runs as root otherwise.
          user = "1000:100";
          ports = [
            "8096:8096" # WebUI
            "8920:8920" # optional https
            "7359:7359/udp" # client discovery
            "1900:1900/udp" # DLNA/service discovery
          ];
          environment = {
            JELLYFIN_PublishedServerUrl = "192.168.0.5";
            # Inert for the official image.
            PUID = "99";
            PGID = "100";
            UMASK = "022";
          };
          volumes = [
            "/mnt/cache/appdata/jellyfin:/config"
            "/mnt/cache/appdata/jellyfin-cache:/cache"
            "/mnt/user/media/qbit/downloads/content/Movies:/data/movies:ro"
            "/mnt/user/media/qbit/downloads/content/TV Shows:/data/tvshows:ro"
          ];
          # Hardware transcoding.
          devices = [
            "/dev/dri:/dev/dri"
          ];
        };
      };
    };
}
