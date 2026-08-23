{
  ...
}:
{
  flake.nixosModules.sound =
    { pkgs, ... }:
    {

      hardware.bluetooth = {
        enable = true;
        package = pkgs.bluez-experimental;
        # hsphfpd.enable = true;
        powerOnBoot = true;
        disabledPlugins = [ "sap" ];
        settings = {
          General = {
            JustWorksRepairing = "always";
            Experimental = true;
            MultiProfile = "multiple";
          };
        };
      };

      environment.systemPackages = with pkgs; [
        bluez-tools
        alsa-utils
      ];

      services = {
        # blueman.enable = true;
        pulseaudio.enable = false;
        pipewire = {
          enable = true;
          alsa = {
            enable = true;
            support32Bit = true;
          };
          wireplumber.enable = true;
          wireplumber.extraConfig = {
            "11-bluetooth-policy" = {
              "override.wireplumber.settings" = {
                "bluetooth.autoswitch-to-headset-profile" = false;
              };
            };
            "10-bluez" = {
              "override.monitor.bluez.properties" = {
                "bluez5.enable-msbc" = false;
                "bluez5.enable-sbc-xq" = true;
                "bluez5.hfphsp-backend" = "none";
                "bluez5.codecs" = [
                  "aac"
                  "sbc_xq"
                  "sbc"
                ];
                "bluez5.roles" = [
                  "a2dp_sink"
                  "a2dp_source"
                ];
              };
            };
          };
          pulse.enable = true;
          jack.enable = true;
          extraConfig.pipewire-pulse."10-remote-pulse" = {
            "pulse.properties" = {
              "server.address" = [
                "unix:native"
                "tcp:127.0.0.1:4713"
              ];
            };
          };
        };
      };
    };
}
