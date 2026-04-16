{
  self,
  inputs,
  ...
}:

{
  perSystem =
    {
      pkgs,
      config,
      ...
    }:
    let
      colors = config.myTheme.colors;
    in
    {
      packages.myNoctalia = inputs.wrapper-modules.wrappers.noctalia-shell.wrap {
        inherit pkgs;

        colors = {
          mError = colors.base08;
          mHover = colors.base0C;
          mOnError = colors.base00;
          mOnHover = colors.base00;
          mOnPrimary = colors.base00;
          mOnSecondary = colors.base00;
          mOnSurface = colors.base05;
          mOnSurfaceVariant = colors.base06;
          mOnTertiary = colors.base00;
          mOutline = colors.base04;
          mPrimary = colors.base0B;
          mSecondary = colors.base0D;
          mShadow = colors.base00;
          mSurface = colors.base00;
          mSurfaceVariant = colors.base02;
          mTertiary = colors.base0C;
        };
        # To update these settings heres the command from root of the flake/config:
        # nix run nixpkgs#noctalia-shell ipc call state all > ./modules/features/noctalia/noctalia.json
        settings = (builtins.fromJSON (builtins.readFile ./noctalia.json)).settings;
      };
    };
}
