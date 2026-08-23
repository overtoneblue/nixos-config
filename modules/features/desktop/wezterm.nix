{ self, inputs, ... }:
{
  flake.nixosModules.wezterm =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        self.packages.${pkgs.system}.myWezterm
      ];
    };
  perSystem =
    {
      pkgs,
      self',
      config,
      ...
    }:
    let
      colors = config.myTheme.colors;
      fonts = config.myTheme.fonts;
    in
    {
      packages.myWezterm = inputs.wrapper-modules.wrappers.wezterm.wrap {
        inherit pkgs;

        "wezterm.lua".content = ''
          local wezterm = require 'wezterm'
          local mux = wezterm.mux
          local config = wezterm.config_builder()
          local act = wezterm.action

          config.default_prog = { "${self'.packages.myZsh}/bin/zsh", "-l" }

          config.max_fps = 240
          config.animation_fps = 240
          config.use_fancy_tab_bar = false
          config.front_end = "OpenGL"
          config.enable_wayland = true

          config.color_schemes = {
            stylix = {
              ansi = {
                "${colors.base00}",
                "${colors.base08}",
                "${colors.base0B}",
                "${colors.base0A}",
                "${colors.base0D}",
                "${colors.base0E}",
                "${colors.base0C}",
                "${colors.base05}",
              },
              brights = {
                "${colors.base03}",
                "${colors.base08}",
                "${colors.base0B}",
                "${colors.base0A}",
                "${colors.base0D}",
                "${colors.base0E}",
                "${colors.base0C}",
                "${colors.base07}",
              },
              background = "${colors.base00}",
              foreground = "${colors.base05}",
              cursor_bg = "${colors.base05}",
              cursor_fg = "${colors.base00}",
              compose_cursor = "${colors.base06}",
              scrollbar_thumb = "${colors.base01}",
              selection_bg = "${colors.base05}",
              selection_fg = "${colors.base00}",
              split = "${colors.base03}",
              visual_bell = "${colors.base09}",
              tab_bar = {
                background = "${colors.base01}",
                inactive_tab_edge = "${colors.base01}",
                active_tab = {
                  bg_color = "${colors.base00}",
                  fg_color = "${colors.base05}",
                },
                inactive_tab = {
                  bg_color = "${colors.base03}",
                  fg_color = "${colors.base05}",
                },
                inactive_tab_hover = {
                  bg_color = "${colors.base05}",
                  fg_color = "${colors.base00}",
                },
                new_tab = {
                  bg_color = "${colors.base03}",
                  fg_color = "${colors.base05}",
                },
                new_tab_hover = {
                  bg_color = "${colors.base05}",
                  fg_color = "${colors.base00}",
                },
              },
            },
          }

          config.color_scheme = "stylix"

          config.window_frame = {
            active_titlebar_bg = "${colors.base03}",
            active_titlebar_fg = "${colors.base05}",
            active_titlebar_border_bottom = "${colors.base03}",
            border_left_color = "${colors.base01}",
            border_right_color = "${colors.base01}",
            border_bottom_color = "${colors.base01}",
            border_top_color = "${colors.base01}",
            button_bg = "${colors.base01}",
            button_fg = "${colors.base05}",
            button_hover_bg = "${colors.base05}",
            button_hover_fg = "${colors.base03}",
            inactive_titlebar_bg = "${colors.base01}",
            inactive_titlebar_fg = "${colors.base05}",
            inactive_titlebar_border_bottom = "${colors.base03}",
          }

          config.command_palette_bg_color = "${colors.base01}"
          config.command_palette_fg_color = "${colors.base05}"

          -- Optional: match your general font setup
          config.font = wezterm.font_with_fallback({
            "${fonts.monospace.name}",
            "${fonts.emoji.name}",
          })
          config.font_size = ${toString fonts.sizes.terminal}
          config.command_palette_font_size = ${toString fonts.sizes.popups}

          -- Optional opacity
          -- config.window_background_opacity = 1.0

          config.keys = {
            {
              key = 'i',
              mods = 'CTRL',
              action = act.EmitEvent 'workflow-startup',
            },
            {
              key = 'i',
              mods = 'CTRL|SHIFT',
              action = act.SwitchToWorkspace {
                name = 'workflow',
              },
            },
            {
              key = 'u',
              mods = 'CTRL|SHIFT',
              action = act.SwitchToWorkspace {
                name = 'default',
              },
            },
          }

          wezterm.on('workflow-startup', function(cmd)
            local args = {}
            if cmd then
              args = cmd.args
            end

            local journal_dir = '/home/overtoneblue/Personal/Janaru'
            local config_dir = '/home/overtoneblue/NixLand'
            local default_dir = '/home/overtoneblue'

            local default_tab, default_pane, window = mux.spawn_window {
              workspace = 'workflow',
              cwd = default_dir,
              args = args,
            }

            local config_tab, config_pane = window:spawn_tab {
              cwd = config_dir,
            }

            local journal_tab, journal_pane = window:spawn_tab {
              cwd = journal_dir,
            }

            local music_tab, music_pane = window:spawn_tab {
              cwd = default_dir,
            }

            journal_tab:set_title 'Journal'
            config_tab:set_title 'NixLand'
            music_tab:set_title 'Music'

            config_pane:send_text 'nvim .\n'
            journal_pane:send_text 'nvim .\n'
            music_pane:send_text 'spotify_player \n'
            default_tab:activate()

            mux.set_active_workspace 'workflow'
          end)

          return config
        '';
      };
    };
}
