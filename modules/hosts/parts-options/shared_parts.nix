{ lib, flake-parts-lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkPerSystemOption;
in
{
  options.perSystem = mkPerSystemOption (
    { ... }:
    {
      options.myTheme.colors = mkOption {
        type = types.attrsOf types.str;
        default = import ./_theme.nix;
        description = "Shared palette for perSystem consumers.";
      };
    }
  );
}
