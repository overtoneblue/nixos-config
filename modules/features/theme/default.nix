{
  self,
  inputs,
  moduleWithSystem,
  ...
}:

{
  flake.nixosModules.theme = moduleWithSystem (
    perSystem@{ config, ... }:
    { config, ... }:
    let
      colors = perSystem.config.myTheme.colors;
      fonts = perSystem.config.myTheme.fonts;
      inherit (config.modules.style) pointerCursor;
    in
    {
      imports = [
        inputs.stylix.nixosModules.stylix
      ];

      hm.stylix = {
        targets.nvf.enable = false;
        targets.firefox.enable = false;
        targets.librewolf.enable = false;
      };

      stylix = {
        enable = true;
        base16Scheme = colors;
        image = ./images/blue-sky.jpg;
        inherit fonts;

        cursor = {
          inherit (pointerCursor) package name size;
        };
      };
    }
  );
}
