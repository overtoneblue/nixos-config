{ config, pkgs, ... }:
{
  config = {
    modules = {
      device = {
        type = "desktop";
        cpu = "amd";
        gpu = "nvidia";
        monitors = [
          "DP-2,2560x1440@239.97,1080x0,1"
          "DP-1,1920x1080@240,0x0,1,transform,1"
          "HDMI-A-1,3840x2160@60,auto,2"
        ];
        workspaces = [
          "workspace = 1, monitor:DP-2"
          "workspace = 2, monitor:DP-2"
          "workspace = 3, monitor:DP-2"
          "workspace = 4, monitor:DP-2"
          "workspace = 5, monitor:DP-2"
          "workspace = 6, monitor:DP-2"
          "workspace = 7, monitor:DP-1"
          "workspace = 8, monitor:DP-1"
          "workspace = 9, monitor:DP-1"
          "workspace = 10, monitor:HDMI-A-1"
        ];
        hasBluetooth = true;
        hasSound = true;
      };
    };
  };
}
