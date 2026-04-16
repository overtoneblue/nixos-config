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
    };
}
