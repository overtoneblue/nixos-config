{
  self,
  inputs,
  moduleWithSystem,
  ...
}:

{
  flake.nixosModules.theme = moduleWithSystem (
    perSystem@{ config, ... }:
    { pkgs, config, ... }:
    let
      colors = perSystem.config.myTheme.colors;
      inherit (config.modules.style) pointerCursor;
    in
    {
      imports = [
        inputs.stylix.nixosModules.stylix
      ];
      hm.stylix = {
        targets.nvf.enable = false;
        targets.firefox.enable = false;
        targets.librewolf.enable = false;
      };
      stylix = {
        enable = true;
        base16Scheme = colors;
        image = ./images/blue-sky.jpg;
        fonts = {
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
        cursor = {
          inherit (pointerCursor) package name size;
        };
      };
    }
  );
}
