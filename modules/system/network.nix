{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.network =
    { pkgs, lib, ... }:
    {
      networking = {
        networkmanager = {
          enable = true;
        };
        nameservers = [
          "1.1.1.1"
          "1.0.0.1"
        ];
        firewall = {
          enable = true;
          checkReversePath = false;
          trustedInterfaces = [
            "virbr0"
            "tailscale0"
          ];
          allowedTCPPorts = [

          ];
          allowedUDPPorts = [

          ];
          allowPing = false;
          logReversePathDrops = true;
        };
      };
      services.tailscale = {
        enable = true;
        extraSetFlags = [ "--netfilter-mode=nodivert" ];
        openFirewall = false;
      };
    };
}
