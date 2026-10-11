{ self, inputs, ... }:
{
  flake.nixosModules.gaming =
    { pkgs, lib, config, ... }:
    lib.mkIf config.modules.programs.desktopApps.enable {
      environment.systemPackages = with pkgs; [
        gamescope
      ];
      programs.steam = {
        enable = true;
        protontricks.enable = true;
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };
    };
}
