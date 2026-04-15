{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.hyprland =
    { pkgs, lib, ... }:
    let
      noctaliaExe = (lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.myNoctalia);
    in
    {
      imports = [
        ./_binds.nix
        ./_settings.nix
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
