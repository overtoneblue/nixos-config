{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.nvf =
    { pkgs, lib, ... }:
{
  hm.imports = [
    inputs.nvf.homeManagerModules.default
    ./_keymaps.nix
    ./_lsp-format.nix
    ./_lualine.nix
    ./_misc.nix
    ./_utility.nix
  ];
  hm.programs.nvf = {
    enable = true;
    # most settings are documented in the appendix
    settings.vim = {
      viAlias = false;
      vimAlias = true;
      preventJunkFiles = true;
      enableLuaLoader = true;

      options = {
        shell = "zsh";
        guifont = "Inter Nerd Font:h14";
        termguicolors = true;
        undofile = true;
        smartindent = true;
        tabstop = 2;
        shiftwidth = 2;
        shiftround = true;
        expandtab = true;
        cursorline = true;
        # textwidth = 80;
        wrap = true;
        linebreak = true;
        relativenumber = true;
        number = true;
        viminfo = "";
        viminfofile = "NONE";
        clipboard = "unnamedplus";
        splitright = true;
        splitbelow = true;
        laststatus = 0;
        cmdheight = 1;
        winborder = "rounded";
      };
    };
  };
  };
}
