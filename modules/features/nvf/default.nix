{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.nvf =
    { pkgs, lib, ... }:
    {
      hm.home.packages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.myNvf
      ];
    };
  perSystem =
    { pkgs, config, ... }:
    let
      colors = config.myTheme.colors;
      customNeovim = inputs.nvf.lib.neovimConfiguration {
        inherit pkgs;
        modules = [
          ./_options.nix
          ./_keymaps.nix
          ./_lsp-format.nix
          ./_lualine.nix
          (import ./_misc.nix { inherit inputs pkgs colors; })
          ./_utility.nix
        ];
      };
    in
    {
      packages.myNvf = customNeovim.neovim;
      # options.vim = {
      #   viAlias = false;
      #   vimAlias = true;
      #   preventJunkFiles = true;
      #   enableLuaLoader = true;
      #
      #   options = {
      #     shell = "zsh";
      #     guifont = "Inter Nerd Font:h14";
      #     termguicolors = true;
      #     undofile = true;
      #     smartindent = true;
      #     tabstop = 2;
      #     shiftwidth = 2;
      #     shiftround = true;
      #     expandtab = true;
      #     cursorline = true;
      #     # textwidth = 80;
      #     wrap = true;
      #     linebreak = true;
      #     relativenumber = true;
      #     number = true;
      #     viminfo = "";
      #     viminfofile = "NONE";
      #     clipboard = "unnamedplus";
      #     splitright = true;
      #     splitbelow = true;
      #     laststatus = 0;
      #     cmdheight = 1;
      #     winborder = "rounded";
      #   };
      # };
      # };
    };
}
# {
#   hm.imports = [
#     inputs.nvf.homeManagerModules.default
#     ./_keymaps.nix
#     ./_lsp-format.nix
#     ./_lualine.nix
#     ./_misc.nix
#     ./_utility.nix
#   ];
#   hm.programs.nvf = {
#     enable = true;
#     # most settings are documented in the appendix
#     settings.vim = {
#       viAlias = false;
#       vimAlias = true;
#       preventJunkFiles = true;
#       enableLuaLoader = true;
#
#       options = {
#         shell = "zsh";
#         guifont = "Inter Nerd Font:h14";
#         termguicolors = true;
#         undofile = true;
#         smartindent = true;
#         tabstop = 2;
#         shiftwidth = 2;
#         shiftround = true;
#         expandtab = true;
#         cursorline = true;
#         # textwidth = 80;
#         wrap = true;
#         linebreak = true;
#         relativenumber = true;
#         number = true;
#         viminfo = "";
#         viminfofile = "NONE";
#         clipboard = "unnamedplus";
#         splitright = true;
#         splitbelow = true;
#         laststatus = 0;
#         cmdheight = 1;
#         winborder = "rounded";
#       };
#     };
#   };
#   };
# }
