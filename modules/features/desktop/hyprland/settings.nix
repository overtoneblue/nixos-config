{
  inputs,
  self,
  outputs,
  lib,
  config,
  pkgs,
  osConfig,
  ...
}:
{
  flake.nixosModules.hyprland =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (config) modules;
      inherit (modules) device;

      # Used below to embed the existing legacy device monitor/workspace
      # string lists as safe Lua values.
      toLua = lib.generators.toLua { };
    in
    {
      hm.home.packages = [ ];

      hm.wayland.windowManager.hyprland = {
        configType = "lua";

        settings = {
          # Home Manager renders this as:
          #   local mod = "SUPER"
          mod = {
            _var = "SUPER";
          };

          window_rule = [
            {
              name = "hermes-scratchpad";

              match = {
                class = "^HERMES$";
              };

              workspace = "special:scratchpad";
              no_initial_focus = false;
            }
            {
              name = "hermes-browser";

              match = {
                class = "^hermes-browser$";
              };

              workspace = "special:hermes-browser silent";
              no_initial_focus = true;
            }
          ];

          # Ordinary Hyprland variables now belong in hl.config({ ... }).
          config = {
            input = {
              follow_mouse = 1;
              sensitivity = 0;
            };

            cursor = {
              # Current Hyprland type is int:
              # 0 = hardware cursors when possible
              # 1 = disable hardware cursors
              # 2 = auto (disable when tearing)
              no_hardware_cursors = 1;
            };

            general = {
              gaps_in = 4;
              gaps_out = 4;
              border_size = 1;
              allow_tearing = true;
              resize_on_border = true;
              layout = "master";
            };

            decoration = {
              shadow = {
                enabled = true;
                range = 20;
                render_power = 3;
              };

              rounding = 8;
            };

            animations = {
              enabled = true;
            };

            quirks = {
              prefer_hdr = 0;
            };

            misc = {
              animate_manual_resizes = true;
              disable_hyprland_logo = true;
              disable_splash_rendering = true;
              mouse_move_enables_dpms = true;
              key_press_enables_dpms = true;
              vrr = 1;
            };
          };

          # Hyprland 0.55+ curves are first-class hl.curve(...) calls.
          curve = [
            {
              _args = [
                "pace"
                {
                  type = "bezier";
                  points = [
                    [
                      0.46
                      1.0
                    ]
                    [
                      0.29
                      0.99
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "overshot"
                {
                  type = "bezier";
                  points = [
                    [
                      0.13
                      0.99
                    ]
                    [
                      0.29
                      1.1
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "md3_decel"
                {
                  type = "bezier";
                  points = [
                    [
                      0.05
                      0.7
                    ]
                    [
                      0.1
                      1.0
                    ]
                  ];
                }
              ];
            }
            {
              _args = [
                "custom"
                {
                  type = "bezier";
                  points = [
                    [
                      0.5
                      0.5
                    ]
                    [
                      0.4
                      0.3
                    ]
                  ];
                }
              ];
            }
          ];

          # Old "animation = ..." strings become hl.animation({ ... }).
          animation = [
            {
              leaf = "windowsIn";
              enabled = true;
              speed = 1;
              bezier = "custom";
              style = "slide";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 1;
              bezier = "custom";
              style = "slide";
            }
            {
              leaf = "windowsMove";
              enabled = true;
              speed = 1;
              bezier = "custom";
              style = "slide";
            }
            {
              leaf = "fade";
              enabled = true;
              speed = 1;
              bezier = "custom";
            }
            {
              leaf = "workspaces";
              enabled = true;
              speed = 1.5;
              bezier = "custom";
            }
            {
              leaf = "specialWorkspace";
              enabled = true;
              speed = 1;
              bezier = "custom";
              style = "slide";
            }
          ];
        };

        # Transitional migration shim.
        #
        # Your modules.device.monitors and modules.device.workspaces are
        # currently legacy Hyprlang strings. Home Manager's extraConfig is
        # appended literally, so the old "monitor=..." / "workspace=..."
        # text is invalid inside hyprland.lua.
        #
        # This embeds those existing Nix lists as Lua tables and translates
        # the common legacy syntax into native hl.monitor(...) and
        # hl.workspace_rule(...) calls. You can later replace the shim by
        # making device.monitors/workspaces structured Nix attrsets.
        extraConfig = ''
          local function trim(value)
            return (value:gsub("^%s+", ""):gsub("%s+$", ""))
          end

          local function split_csv(value)
            local parts = {}
            local start = 1

            while true do
              local comma = value:find(",", start, true)

              if comma == nil then
                table.insert(parts, trim(value:sub(start)))
                break
              end

              table.insert(parts, trim(value:sub(start, comma - 1)))
              start = comma + 1
            end

            return parts
          end

          local function parse_scalar(value)
            value = trim(value)

            if value == "true" then
              return true
            elseif value == "false" then
              return false
            end

            local number = tonumber(value)
            if number ~= nil then
              return number
            end

            return value
          end

          -- Legacy monitor strings:
          --   "DP-1,2560x1440@165,0x0,1"
          --   "DP-2,disable"
          local legacy_monitors = ${toLua device.monitors}

          for _, raw in ipairs(legacy_monitors) do
            local parts = split_csv(raw)

            if #parts == 2 and parts[2] == "disable" then
              hl.monitor({
                output = parts[1],
                disabled = true,
              })
            elseif #parts >= 4 then
              local monitor = {
                output = parts[1],
                mode = parts[2],
                position = parts[3],
                scale = parse_scalar(parts[4]),
              }

              -- Common monitor-v1 extra arguments are key,value pairs after
              -- output/mode/position/scale. Current Lua monitor fields use
              -- the same names for common options such as transform, mirror,
              -- bitdepth, cm, vrr, etc.
              local index = 5

              while index <= #parts do
                local key = parts[index]
                local value = parts[index + 1]

                if value == nil then
                  error("Unsupported legacy monitor rule: " .. raw)
                end

                monitor[key] = parse_scalar(value)
                index = index + 2
              end

              hl.monitor(monitor)
            else
              error("Unsupported legacy monitor rule: " .. raw)
            end
          end

          -- Legacy workspace fields that changed spelling in the Lua API.
          local workspace_key_map = {
            gapsin = "gaps_in",
            gapsout = "gaps_out",
            bordersize = "border_size",
            ["on-created-empty"] = "on_created_empty",
            defaultName = "default_name",
            defaultname = "default_name",
          }

          -- Legacy booleans described what to ENABLE. Lua workspace-rule
          -- fields describe what to DISABLE, hence the inversion.
          local workspace_inverted_bool_map = {
            border = "no_border",
            shadow = "no_shadow",
            rounding = "no_rounding",
          }

          local legacy_workspaces = ${toLua device.workspaces}

          for _, raw in ipairs(legacy_workspaces) do
            -- Accept either the raw RHS ("1, monitor:DP-1") or a complete
            -- old line ("workspace = 1, monitor:DP-1").
            local spec = trim(raw):gsub("^workspace%s*=%s*", "")
            local parts = split_csv(spec)

            if #parts < 1 or parts[1] == "" then
              error("Unsupported legacy workspace rule: " .. raw)
            end

            local rule = {
              workspace = parts[1],
            }

            for index = 2, #parts do
              local key, value = parts[index]:match("^([^:]+)%s*:%s*(.*)$")

              if key == nil then
                error("Unsupported legacy workspace rule token: " .. parts[index])
              end

              key = trim(key)
              value = parse_scalar(value)

              local inverted_key = workspace_inverted_bool_map[key]

              if inverted_key ~= nil then
                if type(value) ~= "boolean" then
                  error("Expected boolean for legacy workspace rule: " .. parts[index])
                end

                rule[inverted_key] = not value
              else
                rule[workspace_key_map[key] or key] = value
              end
            end

            hl.workspace_rule(rule)
          end
        '';
      };
    };
}
