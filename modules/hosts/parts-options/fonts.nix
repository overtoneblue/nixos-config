{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      myTheme.fonts = {
        sizes = {
          applications = 12;
          desktop = 10;
          popups = 10;
          terminal = 12;
        };

        serif = {
          package = pkgs.inter-nerdfont;
          name = "Inter Nerd Font";
        };

        sansSerif = {
          package = pkgs.inter-nerdfont;
          name = "Inter Nerd Font";
        };

        monospace = {
          package = pkgs.maple-mono.NF;
          name = "Maple Mono NF";
        };

        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };
      };
    };
}
