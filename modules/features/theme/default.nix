{
  inputs,
  config,
  ...
}:
let
  # Flake-level theme, captured before the NixOS module below shadows
  # `config` with its own.
  topTheme = config.theme;
in
{
  flake.nixosModules.theme =
    { config, pkgs, ... }:
    let
      inherit (config.modules.style) pointerCursor;
    in
    {
      imports = [
        inputs.stylix.nixosModules.stylix
      ];

      hm.stylix = {
        # polarity = "dark"; # Required for obsidian i guess
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
        base16Scheme = topTheme.colors;
        image = ./images/Greek.png;
        fonts = topTheme.fontsFor pkgs;

        cursor = {
          inherit (pointerCursor) package name size;
        };
      };
    };
}
