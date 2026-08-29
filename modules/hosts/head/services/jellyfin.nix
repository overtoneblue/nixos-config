{ self, ... }:
# Jellyfin as an OCI container on head, restored to match the recovered
# Unraid template (bbergle-jellyfin). Native Jellyfin service is avoided on
# purpose to stay compatible with the old container deployment.
#
# Old appdata (/mnt/user/appdata/bbergle-jellyfin) was NOT migrated to head —
# only the recovered template + media survived. Config therefore starts fresh
# here on head's appdata volume; media is mounted read-only.
{
  flake.nixosModules.headJellyfin =
    { ... }:
    {
      virtualisation.oci-containers = {
        backend = "docker";
        containers.jellyfin = {
          image = "jellyfin/jellyfin:unstable"; # same image tag as the old Unraid template
          autoStart = true;
          # Run non-root as the restored-appdata owner (uid:gid 1000:100).
          # The official image runs as root by default; PUID/PGID envs are
          # inert, so this is the effective ownership control.
          user = "1000:100";
          ports = [
            "8096:8096" # WebUI
            "8920:8920" # optional https
            "7359:7359/udp" # client discovery
            "1900:1900/udp" # DLNA/service discovery
          ];
          environment = {
            # autodiscovery IP from the recovered template
            JELLYFIN_PublishedServerUrl = "192.168.0.5";
            # Unraid uid/gid compat (inert for the official image, kept for template fidelity)
            PUID = "99";
            PGID = "100";
            UMASK = "022";
          };
          volumes = [
            "/mnt/cache/appdata/jellyfin:/config"
            "/mnt/cache/appdata/jellyfin-cache:/cache"
            # media read-only; container paths match the restored library layout
            "/mnt/user/media/qbit/downloads/content/Movies:/data/movies:ro"
            "/mnt/user/media/qbit/downloads/content/TV Shows:/data/tvshows:ro"
          ];
          # hardware transcode, same device passthrough as the old setup
          devices = [
            "/dev/dri:/dev/dri"
          ];
        };
      };
    };
}
