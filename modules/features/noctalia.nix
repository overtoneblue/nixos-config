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
        runtimeLibraries = with pkgs; [
          wlsunset
          cliphis
        ];
        colors = {
          mError = "#fb4934";
          mHover = "#83a598";
          mOnError = "#282828";
          mOnHover = "#282828";
          mOnPrimary = "#282828";
          mOnSecondary = "#282828";
          mOnSurface = "#fbf1c7";
          mOnSurfaceVariant = "#ebdbb2";
          mOnTertiary = "#282828";
          mOutline = "#57514e";
          mPrimary = colors.base00;
          mSecondary = colors.base01;
          mShadow = "#282828";
          mSurface = "#282828";
          mSurfaceVariant = "#3c3836";
          mTertiary = "#83a598";
        };
        settings = { };
        # settings = (builtins.fromJSON (builtins.readFile ./noctalia.json)).settings;
      };
    };
}
