{ self, ... }:
# qBittorrent, restored from the Unraid binhex-qbittorrentvpn appdata. Same
# image, so the appdata layout and torrent resume data carry over untouched,
# but its built-in VPN is off: it runs inside gluetun's network namespace
# (gluetun.nix), with no interface of its own and no route out except the
# AirVPN tunnel. It is also bound to tun0 in its own settings
# (Session\Interface) as a second layer.
{
  flake.nixosModules.headQbittorrent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      docker = "${config.virtualisation.docker.package}/bin/docker";
      # The gluetun unit is "active" as soon as `docker run` starts, before the
      # container (and the namespace this one joins) exists. Wait until the
      # tunnel is up (healthy). On timeout the start fails and Restart= retries.
      waitForGluetun = pkgs.writeShellScript "wait-for-gluetun" ''
        fmt='{{.State.Running}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
        for _ in {1..180}; do
          case "$(${docker} inspect -f "$fmt" gluetun 2>/dev/null)" in
            true/healthy | true/none) exit 0 ;;
          esac
          sleep 1
        done
        echo "gluetun not up and healthy after 180s" >&2
        exit 1
      '';
    in
    {
      virtualisation.oci-containers.containers.qbittorrent = {
        image = "binhex/arch-qbittorrentvpn:5.2.4-1-02";
        autoStart = true;
        dependsOn = [ "gluetun" ];
        # WebUI port 8080 is published on the gluetun container.
        extraOptions = [ "--network=container:gluetun" ];
        environment = {
          VPN_ENABLED = "no";
          # binhex's start script rewrites Session\Interface(Name) to this on
          # every start; unset (as it is with the VPN off) it blanks the
          # binding. tun0 = gluetun's tunnel.
          VPN_DEVICE_TYPE = "tun0";
          WEBUI_PORT = "8080";
          # gluetun's resolver (DNS over TLS through the tunnel).
          NAME_SERVERS = "127.0.0.1";
          # Same as on Unraid; the restored data is owned 99:100.
          PUID = "99";
          PGID = "100";
          UMASK = "000";
        };
        volumes = [
          "/mnt/cache/appdata/binhex-qbittorrentvpn:/config"
          # Read-only: seed-only (no new torrents) and the pool is full, so a
          # torrent that tries to (re)download errors out instead of writing.
          # Torrents saved under /music and /games (Unraid cache paths not
          # restored on head) are stopped in their resume data.
          "/mnt/user/media/qbit/downloads:/downloads:ro"
        ];
      };

      # Follow gluetun: stop when it stops, restart when it restarts, and get
      # pulled back in whenever gluetun starts (including its auto-restart
      # after a failure). Not upheldBy: Upholds= restarts this unit the
      # moment a switch stops it, from the old unit file, so config changes
      # never land.
      systemd.services.docker-qbittorrent = {
        bindsTo = [ "docker-gluetun.service" ];
        partOf = [ "docker-gluetun.service" ];
        wantedBy = [ "docker-gluetun.service" ];
        serviceConfig.ExecStartPre = lib.mkAfter [ "${waitForGluetun}" ];
      };
    };
}
