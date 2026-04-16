{ self, inputs, ... }:
{
  perSystem =
    { pkgs, self', ... }:
    {
      packages.myWezterm = inputs.wrapper-modules.wrappers.wezterm.wrap {
        inherit pkgs;

        wezterm.lua.content = ''
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

            local journal_dir = '/home/cenunix/Personal/Janaru'
            local config_dir = '/home/cenunix/NixLand'
            local default_dir = '/home/cenunix'

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
