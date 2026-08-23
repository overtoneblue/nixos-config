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
      xdg.portal = {
        enable = true;

        extraPortals = [
          pkgs.xdg-desktop-portal-wlr
        ];

        config.hyprland = {
          default = [
            "hyprland"
            "gtk"
          ];

          "org.freedesktop.impl.portal.Screenshot" = [
            "wlr"
          ];

          "org.freedesktop.impl.portal.ScreenCast" = [
            "hyprland"
          ];

          "org.freedesktop.impl.portal.InputCapture" = [
            "hyprland"
          ];

          "org.freedesktop.impl.portal.GlobalShortcuts" = [
            "hyprland"
          ];
        };
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
