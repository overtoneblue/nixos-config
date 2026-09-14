{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  osConfig,
  ...
}:
{
  config.vim = {
    statusline.lualine = {
      enable = true;
      theme = "base16";
      componentSeparator = {
        right = "";
        left = "";
      };
      sectionSeparator = {
        right = "";
        left = "";
      };
      setupOpts = {
        icons_enabled = true;
        disabled_filetypes = {
          statusline = [ ];
          winbar = [ ];
        };
        ignore_focus = [ ];
        always_divide_middle = true;
        globalstatus = false;
        refresh = {
          statusline = 1000;
          tabline = 1000;
          winbar = 1000;
        };

        # Active sections: we use the built-in "mode" component (which will use our custom mapping)
        sections.lualine_a = map lib.generators.mkLuaInline [
        "{
            (function()
             local mode_map = {
               ['n']   = '',
               ['no']  = '',
               ['nov'] = '',
               ['noV'] = '',
               ['no�'] = '',
               ['niI'] = '',
               ['niR'] = '',
               ['niV'] = '',
               ['nt']  = '',
               ['v']   = '',
               ['vs']  = '',
               ['V']   = '',
               ['Vs']  = '',
               ['�']   = '',
               ['�s']  = '',
               ['s']   = '',
               ['S']   = '',
               ['�']   = '',
               ['i']   = '',
               ['ic']  = '',
               ['ix']  = '',
               ['R']   = '',
               ['Rc']  = '',
               ['Rx']  = '',
               ['Rv']  = '',
               ['Rvc'] = '',
               ['Rvx'] = '',
               ['c']   = '',
               ['cv']  = '',
               ['ce']  = '',
               ['r']   = '',
               ['rm']  = '',
               ['r?']  = '',
               ['!']   = '',
               ['t']   = '',
             }
             return function()
               return mode_map[vim.api.nvim_get_mode().mode] or '__'
             end
          end)(),
          separator = { left = '' },
          right_padding = 2
        }"
      ];
        sections.lualine_b = map lib.generators.mkLuaInline [
        ''
          {
            "branch",
            icon = ' •',
            separator = { right = ''},
          }
        ''
      ];
        sections.lualine_c = map lib.generators.mkLuaInline [
        ''
          {
            "filename",
            icon = '',
          }
        ''
      ];
        sections.lualine_x = [ ];
        sections.lualine_y = [ ];
        sections.lualine_z = [ ];

        # Inactive sections
        inactive_sections.lualine_a = [ ];
        inactive_sections.lualine_b = [ ];
        inactive_sections.lualine_c = map lib.generators.mkLuaInline [ "'filename'" ];
        inactive_sections.lualine_x = map lib.generators.mkLuaInline [ "'location'" ];
        inactive_sections.lualine_y = [ ];
        inactive_sections.lualine_z = [ ];
      };
    };

  };
}
