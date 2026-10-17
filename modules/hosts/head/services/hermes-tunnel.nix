{ self, ... }:
# SSH account that only carries the Hermes Desktop backend tunnel from client
# machines (modules/features/hermes/desktop-client.nix) over the tailnet.
# A client can forward to head's loopback hermes-serve (127.0.0.1:9119) and do
# nothing else: no shell or commands, no other forwards, no reverse, socket,
# agent or X11 forwarding, no TTY. Keys come from `hermesTunnel` in
# modules/hosts/_machines.nix, each pinned to its machine's tailnet addresses;
# the tailnet ACL must also allow that machine to tag:head:22.
#
# This tunnel is the real lock on the backend: hermes-serve hands its session
# token to any client that can reach 127.0.0.1:9119.
{
  flake.nixosModules.headHermesTunnel =
    { lib, pkgs, ... }:
    let
      falseBin = "${pkgs.coreutils}/bin/false";

      # Machines with a tunnel key; each key is created on its own machine
      # (see desktop-client.nix).
      clients = lib.filterAttrs (_: m: m.hermesTunnel or null != null) (import ../../_machines.nix);

      tunnelOnly =
        ips:
        ''restrict,port-forwarding,permitopen="127.0.0.1:9119",command="${falseBin}",from="${lib.concatStringsSep "," ips}"'';
    in
    {
      users.users.hermes-tunnel = {
        isSystemUser = true;
        group = "hermes-tunnel";
        openssh.authorizedKeys.keys = lib.mapAttrsToList (
          _: m: "${tunnelOnly m.ips} ${m.hermesTunnel}"
        ) clients;
      };
      users.groups.hermes-tunnel = { };

      # The same limits for the whole account, so they hold for any key added
      # here even without the options above. `Match all` closes the block, so
      # Match-allowed lines appended after it apply to everyone again (a
      # global-only keyword there fails the build-time sshd check instead).
      services.openssh.extraConfig = lib.mkAfter ''
        Match User hermes-tunnel
          AllowTcpForwarding local
          PermitOpen 127.0.0.1:9119
          PermitListen none
          AllowStreamLocalForwarding no
          AllowAgentForwarding no
          X11Forwarding no
          PermitTTY no
          ForceCommand ${falseBin}
        Match all
      '';
    };
}
