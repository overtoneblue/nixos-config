{ self, ... }:
# SSH account that only carries the Hermes Desktop backend tunnel from client
# machines (modules/features/hermes/desktop-client.nix) over the tailnet.
# A client can forward to head's loopback hermes-serve (127.0.0.1:9119) and do
# nothing else: no shell or commands, no other forwards, no reverse, socket,
# agent or X11 forwarding, no TTY. Each key is also pinned to its machine's
# tailnet addresses, and the tailnet ACL must allow that machine to
# tag:head:22.
#
# This tunnel is the real lock on the backend: hermes-serve hands its session
# token to any client that can reach 127.0.0.1:9119.
{
  flake.nixosModules.headHermesTunnel =
    { lib, pkgs, ... }:
    let
      falseBin = "${pkgs.coreutils}/bin/false";

      # name = { ips = "<tailnet IPv4>,<tailnet IPv6>"; key = "<its .pub line>"; };
      # The key is created on the client itself (see desktop-client.nix).
      clients = { };

      tunnelOnly =
        ips: ''restrict,port-forwarding,permitopen="127.0.0.1:9119",command="${falseBin}",from="${ips}"'';
    in
    {
      users.users.hermes-tunnel = {
        isSystemUser = true;
        group = "hermes-tunnel";
        openssh.authorizedKeys.keys = lib.mapAttrsToList (_: c: "${tunnelOnly c.ips} ${c.key}") clients;
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
