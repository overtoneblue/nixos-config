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
                    applications = mkOption {
                      type = types.int;
                      default = 12;
                    };

                    desktop = mkOption {
                      type = types.int;
                      default = 10;
                    };

                    popups = mkOption {
                      type = types.int;
                      default = 10;
                    };

                    terminal = mkOption {
                      type = types.int;
                      default = 12;
                    };
                  };
                };
                default = { };
                description = "Shared font sizes.";
              };

              serif = mkOption {
                type = types.submodule {
                  options = {
                    package = mkOption {
                      type = types.package;
                    };

                    name = mkOption {
                      type = types.str;
                    };
                  };
                };
                default = { };
              };

              sansSerif = mkOption {
                type = types.submodule {
                  options = {
                    package = mkOption {
                      type = types.package;
                    };

                    name = mkOption {
                      type = types.str;
                    };
                  };
                };
                default = { };
              };

              monospace = mkOption {
                type = types.submodule {
                  options = {
                    package = mkOption {
                      type = types.package;
                    };

                    name = mkOption {
                      type = types.str;
                    };
                  };
                };
                default = { };
              };

              emoji = mkOption {
                type = types.submodule {
                  options = {
                    package = mkOption {
                      type = types.package;
                    };

                    name = mkOption {
                      type = types.str;
                    };
                  };
                };
                default = { };
              };
            };
          };

          default = {
            sizes = {
              applications = 12;
              desktop = 10;
              popups = 10;
              terminal = 12;
            };

            serif = {
              package = null;
              name = "Inter Nerd Font";
            };

            sansSerif = {
              package = null;
              name = "Inter Nerd Font";
            };

            monospace = {
              package = null;
              name = "Maple Mono NF";
            };

            emoji = {
              package = null;
              name = "Noto Color Emoji";
            };
          };

          description = "Shared font configuration for Stylix and perSystem consumers.";
        };
      };
    }
  );
}
