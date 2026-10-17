# Tailnet addresses and SSH public keys of the machines, read by the hosts that
# connect to or trust them. Public halves only: every private key is created on
# its own machine and never leaves it. A plain attrset rather than a module
# (import-tree skips `_` files); import it by path.
{
  head = {
    ip = "100.91.71.44"; # tailnet IPv4
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII8AKR3df4rGeqagxwBLLrfHmy9sYjJ+odSpVfEBOfU8";
  };

  callisto = {
    # Tailnet IPv4 + IPv6. Its keys work only from these addresses, so removing
    # callisto from the tailnet revokes them. If it is ever re-added it gets
    # new addresses: update them here.
    ips = [
      "100.97.38.94"
      "fd7a:115c:a1e0::622a:265f"
    ];
    # ~/.ssh/id_ed25519.pub, passphrase-protected: a normal shell as
    # overtoneblue on head (head/configuration.nix).
    admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFGyDfD7zd+w7Gd0WjgxHWXyyeqyz03XQSldcYdkYl8r callisto";
    # ~/.ssh/hermes_desktop_tunnel.pub, no passphrase (starts unattended): the
    # Hermes Desktop tunnel only (head/services/hermes-tunnel.nix).
    hermesTunnel = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEb+pgSKZtlc9wyk4NykO1BJCR8VzfVEGVPvyVF91jFg callisto-hermes-tunnel";
  };
}
