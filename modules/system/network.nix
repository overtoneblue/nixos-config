{
  ...
}:
{
  flake.nixosModules.network =
    { lib, ... }:
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
          trustedInterfaces = [
            "virbr0"
          ];
          allowedTCPPorts = [

          ];
          allowedUDPPorts = [

          ];
          allowPing = lib.mkDefault false;
          logReversePathDrops = true;
        };
      };
    };
}
