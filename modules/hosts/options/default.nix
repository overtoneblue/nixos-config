{ self, inputs, ... }:
{
  flake.nixosModules.options =
    { lib, ... }:
    let
      inherit (lib) mkOption mkEnableOption types;
    in
    {
      imports = [ ./_hardware.nix ];
    };
}
