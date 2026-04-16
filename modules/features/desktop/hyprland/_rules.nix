{ lib, ... }:
let
  inherit (lib) mkIf;
in
{
  hm.wayland.windowManager.hyprland.settings = {

    windowrule = [
      # window rules go here
      # See https://wiki.hyprland.org/Configuring/Window-Rules/
      "match:class ^(Civ6)$, fullscreen on"
      "match:class ^(Civ6)$, monitor 1"

    ];
  };
}
