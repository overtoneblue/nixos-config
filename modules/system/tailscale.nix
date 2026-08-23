{
  ...
}:
{
  flake.nixosModules.tailscale =
    { ... }:
    {
      services.tailscale = {
        enable = true;
        extraSetFlags = [ "--netfilter-mode=nodivert" ];
        openFirewall = false;
      };

      networking.firewall = {
        checkReversePath = false;
        trustedInterfaces = [
          "tailscale0"
        ];
      };
    };
}
