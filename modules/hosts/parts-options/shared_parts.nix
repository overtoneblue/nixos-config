{
  lib,
  config,
  flake-parts-lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;

  # The theme is declared once at the flake-parts top level, so it is reachable
  # from every kind of module: flake-parts modules read `config.theme`, NixOS /
  # home-manager modules defined in this flake capture it by closure (see
  # `topTheme` in features/theme/default.nix), and perSystem keeps `myTheme`
  # as a derived view with font packages resolved against that system's pkgs.
  topTheme = config.theme;

  fontType = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      package = mkOption {
        type = types.functionTo types.package;
        description = "Selects the font package from a pkgs set.";
      };
    };
  };
in
{
  options.theme = {
    colors = mkOption {
      type = types.attrsOf types.str;
      default = import ./_theme.nix;
      description = "Base16 palette shared by every host, wrapper and package.";
    };

    fonts = {
      sizes = mkOption {
        type = types.submodule {
          options = {
            applications = mkOption { type = types.int; };
            desktop = mkOption { type = types.int; };
            popups = mkOption { type = types.int; };
            terminal = mkOption { type = types.int; };
          };
        };
      };
      serif = mkOption { type = fontType; };
      sansSerif = mkOption { type = fontType; };
      monospace = mkOption { type = fontType; };
      emoji = mkOption { type = fontType; };
    };

    # Resolves font packages against a pkgs set: the shape Stylix's `fonts`
    # option expects.
    fontsFor = mkOption {
      type = types.functionTo types.attrs;
      readOnly = true;
      default =
        pkgs:
        let
          resolve = font: {
            inherit (font) name;
            package = font.package pkgs;
          };
        in
        {
          inherit (topTheme.fonts) sizes;
          serif = resolve topTheme.fonts.serif;
          sansSerif = resolve topTheme.fonts.sansSerif;
          monospace = resolve topTheme.fonts.monospace;
          emoji = resolve topTheme.fonts.emoji;
        };
    };
  };

  options.perSystem = mkPerSystemOption (
    { pkgs, ... }:
    {
      options.myTheme = mkOption {
        type = types.attrs;
        readOnly = true;
        default = {
          inherit (topTheme) colors;
          fonts = topTheme.fontsFor pkgs;
        };
        description = "Per-system view of `theme` (font packages resolved).";
      };
    }
  );
}
