{
  lib,
  flake-parts-lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;
in
{
  options.perSystem = mkPerSystemOption (
    { ... }:
    {
      options.myTheme = {
        colors = mkOption {
          type = types.attrsOf types.str;
          default = import ./_theme.nix;
          description = "Shared palette for perSystem consumers.";
        };

        fonts = mkOption {
          type = types.submodule {
            options = {
              sizes = mkOption {
                type = types.submodule {
                  options = {
                    applications = mkOption { type = types.int; };
                    desktop = mkOption { type = types.int; };
                    popups = mkOption { type = types.int; };
                    terminal = mkOption { type = types.int; };
                  };
                };
                description = "Shared font sizes.";
              };

              serif = mkOption {
                type = types.submodule {
                  options = {
                    package = mkOption { type = types.package; };
                    name = mkOption { type = types.str; };
                  };
                };
              };

              sansSerif = mkOption {
                type = types.submodule {
                  options = {
                    package = mkOption { type = types.package; };
                    name = mkOption { type = types.str; };
                  };
                };
              };

              monospace = mkOption {
                type = types.submodule {
                  options = {
                    package = mkOption { type = types.package; };
                    name = mkOption { type = types.str; };
                  };
                };
              };

              emoji = mkOption {
                type = types.submodule {
                  options = {
                    package = mkOption { type = types.package; };
                    name = mkOption { type = types.str; };
                  };
                };
              };
            };
          };
          description = "Shared font configuration for Stylix and perSystem consumers.";
        };
      };
    }
  );
}
