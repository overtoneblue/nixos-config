{ self, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.myNeovim = inputs.wrapper-modules.wrappers.neovim.wrap {
        inherit pkgs;
        specs.general = with pkgs.vimPlugins; [
          # plugins which are loaded at startup ...
        ];
        specs.lazy = {
          lazy = true;
          data = with pkgs.vimPlugins; [
            # plugins which are not loaded until you vim.cmd.packadd them ...
          ];
        };
        info = {
          values = "for lua";
          which = "will be placed in the generated info plugin for access";
        };
        extraPackages = with pkgs; [
          # lsps, formatters, etc...
        ];
        settings.config_directory = ./config; # or lib.generators.mkLuaInline "vim.fn.stdpath('config')";
      };
    };
}
