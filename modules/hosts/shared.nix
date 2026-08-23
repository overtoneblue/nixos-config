{ self, inputs, ... }:
{
  flake.nixosModules.base =
    {
      inputs,
      pkgs,
      lib,
      config,
      ...
    }:
    let
      ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
    in

    {

      users.users = {
        cenunix = {

          initialPassword = "changeme";
          isNormalUser = true;

          extraGroups = [
            "wheel"
            "networkManager"
            "video"
          ]
          ++ ifTheyExist [
            "docker"
            "libvirtd"
            "kvm"
            "qemu-libvirtd"
            "wireshark"
            "hermes"
            "ydotool"
          ];
        };
      };

      time = {
        timeZone = "America/Los_Angeles";
        hardwareClockInLocalTime = true;
      };

      i18n.defaultLocale = "en_US.UTF-8";

      i18n.extraLocaleSettings = {
        LC_ADDRESS = "en_US.UTF-8";
        LC_IDENTIFICATION = "en_US.UTF-8";
        LC_MEASUREMENT = "en_US.UTF-8";
        LC_MONETARY = "en_US.UTF-8";
        LC_NAME = "en_US.UTF-8";
        LC_NUMERIC = "en_US.UTF-8";
        LC_PAPER = "en_US.UTF-8";
        LC_TELEPHONE = "en_US.UTF-8";
        LC_TIME = "en_US.UTF-8";
      };

      # services = {
      #   printing.enable = true;
      # };

      security.rtkit.enable = true;

    };
}
