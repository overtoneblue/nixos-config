{ self, inputs, ... }:
{
  flake.nixosModules.myNeovim =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        self.packages.${pkgs.stdenv.hostPlatform.system}.myNeovim
      ];
    };
  perSystem =
    { pkgs, ... }:
    {
      packages.myNeovim = inputs.wrapper-modules.wrappers.neovim.wrap {
        inherit pkgs;

        # optional, useful if you may have multiple wrapped nvim packages later
        binName = "my-neovim";
        settings.dont_link = true;

        # simple first pass: just use a normal config directory
        settings.config_directory = ./config;

        # helpful CLI tools/LSPs available to the wrapped nvim
        extraPackages = with pkgs; [
          ripgrep
          fd
          stylua
          lua-language-server
        ];

        # a few startup plugins
        specs.general = with pkgs.vimPlugins; [
          plenary-nvim
          telescope-nvim
          nvim-treesitter
          lualine-nvim
          which-key-nvim
        ];

        # one example configured spec
        specs.colors = {
          data = pkgs.vimPlugins.mini-base16;
          before = [ "INIT_MAIN" ];
          info = {
            base00 = "#0b0e14";
            base01 = "#11141b";
            base02 = "#181b22";
            base03 = "#21242c";
            base04 = "#2d3039";
            base05 = "#c7d0dd";
            base06 = "#e2e6ee";
            base07 = "#ffffff";
            base08 = "#b7c2d9";
            base09 = "#c0cae2";
            base0A = "#d0d9ee";
            base0B = "#adc6ff";
            base0C = "#9bb3e7";
            base0D = "#7a8fb8";
            base0E = "#a4b3d4";
            base0F = "#8b94a5";
          };
          config = /* lua */ ''
            local info = ...
            require("mini.base16").setup({
              palette = info,
            })
          '';
        };
      };
    };
}
