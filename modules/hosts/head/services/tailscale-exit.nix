{ self, ... }:
# head as a Tailscale exit node. Devices route all their internet traffic
# through head (e.g. on untrusted hotel Wi-Fi). The tailnet ACL decides who
# may use it: members -> autogroup:internet, which excludes the home LAN.
#
# tailscaled runs with --netfilter-mode=nodivert (modules/system/tailscale.nix),
# so it creates its ts-* chains but never hooks them into FORWARD/POSTROUTING.
# The two hooks an exit node needs are added explicitly below.
{
  flake.nixosModules.headTailscaleExit =
    { ... }:
    {
      services.tailscale = {
        useRoutingFeatures = "server";
        extraSetFlags = [ "--advertise-exit-node" ];
      };

      networking.firewall.extraCommands = ''
        # Forward tailnet clients' traffic out, and the replies back in.
        iptables -w -D FORWARD -i tailscale0 ! -o tailscale0 -j ACCEPT 2>/dev/null || true
        iptables -w -I FORWARD -i tailscale0 ! -o tailscale0 -j ACCEPT
        iptables -w -D FORWARD -o tailscale0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        iptables -w -I FORWARD -o tailscale0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        # Leave with head's address.
        iptables -w -t nat -D POSTROUTING -s 100.64.0.0/10 ! -o tailscale0 -j MASQUERADE 2>/dev/null || true
        iptables -w -t nat -A POSTROUTING -s 100.64.0.0/10 ! -o tailscale0 -j MASQUERADE
      '';
      networking.firewall.extraStopCommands = ''
        iptables -w -D FORWARD -i tailscale0 ! -o tailscale0 -j ACCEPT 2>/dev/null || true
        iptables -w -D FORWARD -o tailscale0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        iptables -w -t nat -D POSTROUTING -s 100.64.0.0/10 ! -o tailscale0 -j MASQUERADE 2>/dev/null || true
      '';
    };
}
