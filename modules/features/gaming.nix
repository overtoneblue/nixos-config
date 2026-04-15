{ self, inputs, ... }:
{
  flake.nixosModules.gaming =
    { pkgs, ... }:
    {
      programs.steam = {
        enable = true;
        protontricks.enable = true;
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };
    };
}
