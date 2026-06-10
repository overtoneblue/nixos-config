{ }
# { self, inputs, ... }:
# {
#   flake.nixosModules.niri =
#     { pkgs, lib, ... }:
#     {
#       programs.niri = {
#         enable = true;
#         package = self.packages.${pkgs.stdenv.hostPlatform.system}.myNiri;
#       };
#     };
#
#   perSystem =
#     {
#       pkgs,
#       lib,
#       self',
#       config,
#       ...
#     }:
#     {
#       packages.myNiri = inputs.wrapper-modules.wrappers.niri.wrap {
#         inherit pkgs;
#         settings =
#           let
#             noctaliaExe = (lib.getExe self'.packages.myNoctalia);
#           in
#           {
#             input = {
#               focus-follows-mouse = _: { };
#             };
#
#             spawn-at-startup = [ noctaliaExe ];
#
#             xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;
#
#             input.keyboard.xkb.layout = "us,ua";
#
#             layout.gaps = 5;
#
#             outputs = {
#               "DP-1" = {
#                 position = _: {
#                   props = {
#                     x = 0;
#                     y = 0;
#                   };
#                 };
#                 mode = "1920x1080@240.00";
#                 transform = "90";
#               };
#               "DP-2" = {
#                 position = _: {
#                   props = {
#                     x = 1080;
#                     y = 0;
#                   };
#                 };
#                 mode = "2560x1440@239.970";
#               };
#             };
#
#             workspaces =
#               let
#                 settings1 = {
#                   layout.gaps = 5;
#                   open-on-output = "DP-1";
#                 };
#                 settings2 = {
#                   layout.gaps = 5;
#                   open-on-output = "DP-2";
#                 };
#               in
#               {
#                 "w0" = settings2;
#                 "w1" = settings2;
#                 "w2" = settings1;
#                 "w3" = settings2;
#                 "w4" = settings2;
#                 "w5" = settings2;
#                 "w6" = settings2;
#                 "w7" = settings1;
#                 "w8" = settings1;
#                 "w9" = settings1;
#               };
#
#             binds = {
#               "Mod+Return".spawn-sh = lib.getExe pkgs.kitty;
#               "Mod+Q".close-window = _: { };
#               "Mod+Space".spawn-sh = "${lib.getExe self'.packages.myNoctalia} ipc call launcher toggle";
#               "Mod+G".maximize-column = _: { };
#               "Mod+F".fullscreen-window = _: { };
#               "Mod+Shift+Space".toggle-window-floating = _: { };
#               "Mod+C".center-column = _: { };
#
#               "Mod+B".move-workspace-to-monitor-next = _: { };
#
#               "Mod+H".focus-column-left = _: { };
#               "Mod+L".focus-column-right = _: { };
#               "Mod+K".focus-window-up = _: { };
#               "Mod+J".focus-window-down = _: { };
#
#               "Mod+Left".focus-column-left = _: { };
#               "Mod+Right".focus-column-right = _: { };
#               "Mod+Up".focus-window-up = _: { };
#               "Mod+Down".focus-window-down = _: { };
#
#               "Mod+Shift+H".move-column-left = _: { };
#               "Mod+Shift+L".move-column-right = _: { };
#               "Mod+Shift+K".move-window-up = _: { };
#               "Mod+Shift+J".move-window-down = _: { };
#
#               "Mod+1".focus-workspace = "w0";
#               "Mod+2".focus-workspace = "w1";
#               "Mod+3".focus-workspace = "w2";
#               "Mod+4".focus-workspace = "w3";
#               "Mod+5".focus-workspace = "w4";
#               "Mod+6".focus-workspace = "w5";
#               "Mod+7".focus-workspace = "w6";
#               "Mod+8".focus-workspace = "w7";
#               "Mod+9".focus-workspace = "w8";
#               "Mod+0".focus-workspace = "w9";
#               "Mod+Shift+1".move-column-to-workspace = "w0";
#               "Mod+Shift+2".move-column-to-workspace = "w1";
#               "Mod+Shift+3".move-column-to-workspace = "w2";
#               "Mod+Shift+4".move-column-to-workspace = "w3";
#               "Mod+Shift+5".move-column-to-workspace = "w4";
#               "Mod+Shift+6".move-column-to-workspace = "w5";
#               "Mod+Shift+7".move-column-to-workspace = "w6";
#               "Mod+Shift+8".move-column-to-workspace = "w7";
#               "Mod+Shift+9".move-column-to-workspace = "w8";
#               "Mod+Shift+0".move-column-to-workspace = "w9";
#             };
#           };
#       };
#     };
# }
