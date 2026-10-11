{ self, ... }:
# VPN gateway (AirVPN over WireGuard). Containers that must only ever reach
# the internet through the tunnel join this container's network namespace
# (`--network=container:gluetun`) instead of getting an interface of their
# own. gluetun's firewall drops everything that isn't the tunnel, so if the
# tunnel or this container goes down they have no route out at all.
#
# Attaching a container (qbittorrent.nix is the reference):
#   - extraOptions = [ "--network=container:gluetun" ]; dependsOn = [ "gluetun" ];
#   - bindsTo/partOf/wantedBy docker-gluetun.service, so it follows gluetun's
#     restarts (a namespace it joined dies with the old gluetun container);
#   - publish its ports HERE, not on the attached container.
{
  flake.nixosModules.headGluetun =
    { config, ... }:
    let
      ph = config.sops.placeholder;
    in
    {
      # The AirVPN WireGuard device qBittorrent used on Unraid (its built-in
      # wg0), which the forwarded port belongs to.
      sops.secrets = {
        "airvpn-wg-private-key".restartUnits = [ "docker-gluetun.service" ];
        "airvpn-wg-preshared-key".restartUnits = [ "docker-gluetun.service" ];
        "airvpn-wg-addresses".restartUnits = [ "docker-gluetun.service" ];
      };
      sops.templates."gluetun-env" = {
        owner = "root";
        mode = "0400";
        content = ''
          WIREGUARD_PRIVATE_KEY=${ph."airvpn-wg-private-key"}
          WIREGUARD_PRESHARED_KEY=${ph."airvpn-wg-preshared-key"}
          WIREGUARD_ADDRESSES=${ph."airvpn-wg-addresses"}
        '';
      };

      # Kernel WireGuard; without it gluetun falls back to userspace
      # wireguard-go over /dev/net/tun.
      boot.kernelModules = [ "wireguard" ];

      virtualisation.oci-containers = {
        backend = "docker";
        containers.gluetun = {
          image = "qmcgaw/gluetun:v3.41";
          autoStart = true;
          capabilities.NET_ADMIN = true;
          devices = [ "/dev/net/tun:/dev/net/tun" ];
          environment = {
            TZ = "America/Los_Angeles";
            VPN_SERVICE_PROVIDER = "airvpn";
            VPN_TYPE = "wireguard";
            SERVER_COUNTRIES = "United States";
            # AirVPN forwarded port = qBittorrent's listen port; lets peers
            # connect in through the tunnel.
            FIREWALL_VPN_INPUT_PORTS = "53405";
          };
          environmentFiles = [ config.sops.templates."gluetun-env".path ];
          # Ports of the attached containers. Docker-published ports bypass
          # nixos-fw; they stay LAN-only because the router forwards nothing
          # here and the tailnet ACL only allows tag:head:8443. Not bound to
          # 10.1.1.24: the address comes from DHCP, and a failed bind would
          # keep gluetun (and everything behind it) down.
          ports = [
            "8080:8080" # qBittorrent WebUI
          ];
        };
      };
    };
}
