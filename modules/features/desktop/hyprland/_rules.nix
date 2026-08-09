{ ... }:
{
  hm.wayland.windowManager.hyprland.settings = {
    window_rule = [
      {
        match = {
          class = "^(Civ6)$";
        };

        fullscreen = true;
        monitor = "1";
      }
    ];
  };
}
