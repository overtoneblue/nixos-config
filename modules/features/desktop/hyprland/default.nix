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

          # Hyprland 0.55+ uses Lua as the primary configuration language.
          configType = "lua";

          # UWSM owns the graphical systemd session.
          systemd.enable = false;
        };
      };
    };
}
