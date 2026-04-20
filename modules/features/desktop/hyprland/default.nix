{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.hyprland =
    { pkgs, lib, ... }:

    {
      imports = [
        inputs.hyprland.nixosModules.default
        ./_rules.nix
      ];

      programs.hyprland = {
        enable = true;
        withUWSM = true;
      };

      hm = {
        imports = [
          inputs.hyprland.homeManagerModules.default
        ];
        wayland.windowManager.hyprland = {
          enable = true;
          package = null;
          portalPackage = null;

          systemd = {
            enable = false;
          };
        };
      };
    };
}
