{ self, inputs, ... }:
{
  flake.nixosModules.niri =
    { pkgs, lib, ... }:
    {
      programs.niri = {
        enable = true;
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.myNiri;
      };
    };

  perSystem =
    {
      pkgs,
      lib,
      self',
      config,
      ...
    }:
    {
      packages.myNiri = inputs.wrapper-modules.wrappers.niri.wrap {
        inherit pkgs;
        settings =
          let
            noctaliaExe = (lib.getExe self'.packages.myNoctalia);
          in
          {
            input = {
              focus-follows-mouse = null;
            };

            spawn-at-startup = [ noctaliaExe ];

            xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;

            input.keyboard.xkb.layout = "us,ua";

            layout.gaps = 5;

            outputs = {
              "DP-1" = {
                position = _: {
                  props = {
                    x = 0;
                    y = 0;
                  };
                };
                mode = "1920x1080@240.00";
                transform = "90";
              };
              "DP-2" = {
                position = _: {
                  props = {
                    x = 1080;
                    y = 0;
                  };
                };
                mode = "2560x1440@239.970";
              };
            };

            binds = {
              "Mod+Return".spawn-sh = lib.getExe pkgs.kitty;
              "Mod+Q".close-window = null;
              "Mod+Space".spawn-sh = "${lib.getExe self'.packages.myNoctalia} ipc call launcher toggle";
              "Mod+G".maximize-column = null;
              "Mod+F".fullscreen-window = null;
              "Mod+Shift+Space".toggle-window-floating = null;
              "Mod+C".center-column = null;
              # "Mod+d".spawn-sh = self.mkWhichKeyExe config.pkgs [
              #   {
              #     key = "b";
              #     desc = "Bluetooth";
              #     cmd = "${noctaliaExe} ipc call bluetooth togglePanel";
              #   }
              #   {
              #     key = "w";
              #     desc = "Wifi";
              #     cmd = "${noctaliaExe} ipc call wifi togglePanel";
              #   }
              #   {
              #     key = "f";
              #     desc = "Firefox";
              #     cmd = "firefox";
              #   }
              #   {
              #     key = "t";
              #     desc = "Telegram";
              #     cmd = "Telegram";
              #   }
              #   {
              #     key = "d";
              #     desc = "Discord";
              #     cmd = "vesktop";
              #   }
              #   {
              #     key = "m";
              #     desc = "Youtube Music";
              #     cmd = "pear-desktop";
              #   }
              #   {
              #     key = "s";
              #     desc = "Pavucontrol";
              #     cmd = "${lib.getExe pkgs.pavucontrol}";
              #   }
              # ];
              "Mod+H".focus-column-left = null;
              "Mod+L".focus-column-right = null;
              "Mod+K".focus-window-up = null;
              "Mod+J".focus-window-down = null;

              "Mod+Left".focus-column-left = null;
              "Mod+Right".focus-column-right = null;
              "Mod+Up".focus-window-up = null;
              "Mod+Down".focus-window-down = null;

              "Mod+Shift+H".move-column-left = null;
              "Mod+Shift+L".move-column-right = null;
              "Mod+Shift+K".move-window-up = null;
              "Mod+Shift+J".move-window-down = null;

              "Mod+1".focus-workspace = "w0";
              "Mod+2".focus-workspace = "w1";
              "Mod+3".focus-workspace = "w2";
              "Mod+4".focus-workspace = "w3";
              "Mod+5".focus-workspace = "w4";
              "Mod+6".focus-workspace = "w5";
              "Mod+7".focus-workspace = "w6";
              "Mod+8".focus-workspace = "w7";
              "Mod+9".focus-workspace = "w8";
              "Mod+0".focus-workspace = "w9";
              "Mod+Shift+1".move-column-to-workspace = "w0";
              "Mod+Shift+2".move-column-to-workspace = "w1";
              "Mod+Shift+3".move-column-to-workspace = "w2";
              "Mod+Shift+4".move-column-to-workspace = "w3";
              "Mod+Shift+5".move-column-to-workspace = "w4";
              "Mod+Shift+6".move-column-to-workspace = "w5";
              "Mod+Shift+7".move-column-to-workspace = "w6";
              "Mod+Shift+8".move-column-to-workspace = "w7";
              "Mod+Shift+9".move-column-to-workspace = "w8";
              "Mod+Shift+0".move-column-to-workspace = "w9";
            };
          };
      };
    };
}
