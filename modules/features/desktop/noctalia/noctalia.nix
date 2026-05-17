{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.noctalia =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      inherit (config) modules;
      inherit (modules) device style;

      colors = config.lib.stylix.colors.withHashtag;
      preferredNoctaliaColors = {
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

        terminal = {
          foreground = colors.base05;
          background = colors.base00;

          selectionFg = colors.base00;
          selectionBg = colors.base05;

          cursorText = colors.base00;
          cursor = colors.base05;

          normal = {
            black = colors.base00;
            red = colors.base08;
            green = colors.base0B;
            yellow = colors.base0A;
            blue = colors.base0D;
            magenta = colors.base0E;
            cyan = colors.base0C;
            white = colors.base05;
          };

          bright = {
            black = colors.base03;
            red = colors.base08;
            green = colors.base0B;
            yellow = colors.base0A;
            blue = colors.base0D;
            magenta = colors.base0E;
            cyan = colors.base0C;
            white = colors.base07;
          };
        };
      };

      stylixPalette = {
        dark = preferredNoctaliaColors;

        # Intentionally mirrors dark mode so your exact preferred mapping
        # remains consistent even if Noctalia expects both keys.
        light = preferredNoctaliaColors;
      };
      # noctaliaPkg = inputs.wrapper-modules.wrappers.noctalia-shell.wrap {
      #   inherit pkgs;
      #
      #   colors = {
      #     mError = colors.base08;
      #     mHover = colors.base0C;
      #     mOnError = colors.base00;
      #     mOnHover = colors.base00;
      #     mOnPrimary = colors.base00;
      #     mOnSecondary = colors.base00;
      #     mOnSurface = colors.base05;
      #     mOnSurfaceVariant = colors.base06;
      #     mOnTertiary = colors.base00;
      #     mOutline = colors.base04;
      #     mPrimary = colors.base0B;
      #     mSecondary = colors.base0D;
      #     mShadow = colors.base00;
      #     mSurface = colors.base00;
      #     mSurfaceVariant = colors.base02;
      #     mTertiary = colors.base0C;
      #   };
      #   # To update these settings heres the command from root of the flake/config:
      #   # nix run nixpkgs#noctalia-shell ipc call state all > ./modules/features/desktop/noctalia/noctalia.json
      #   settings = (builtins.fromJSON (builtins.readFile ./noctalia.json)).settings;
      # };
    in
    {
      hm = {
        imports = [
          inputs.noctalia.homeModules.default
        ];
        programs.noctalia = {
          enable = true;
          systemd.enable = true;
          settings = {
            bar = {
              default = {
                margin_ends = 0;
              };
            };
          };
          customPalettes = {
            stylix = stylixPalette;
          };
        };
      };
    };
}
