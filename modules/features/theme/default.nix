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
        polarity = "dark"; # Required for obsidian i guess
        targets = {
          gtksourceview.enable = false;
          nixos-icons.enable = false;
          nvf.enable = false;
          firefox.enable = false;
          librewolf.enable = false;
          obsidian.vaultNames = [ "Janaru" ];
        };
      };

      stylix = {
        targets = {
          gtksourceview.enable = false;
          nixos-icons.enable = false;
        };
        enable = true;
        base16Scheme = colors;
        image = ./images/Greek.png;
        inherit fonts;

        cursor = {
          inherit (pointerCursor) package name size;
        };
      };
    }
  );
}
