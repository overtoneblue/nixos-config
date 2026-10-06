{ self, inputs, ... }:
{
  flake.nixosModules.base =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      ifTheyExist = groups: builtins.filter (group: builtins.hasAttr group config.users.groups) groups;
      inherit (config.modules.system) username homeDirectory extraGroups;
    in

    {
      users.users.${username} = {
        isNormalUser = true;

        home = homeDirectory;

        extraGroups = [
          "wheel"
          "video"
        ]
        ++ extraGroups
        ++ ifTheyExist [
          "networkmanager"
          "docker"
          "libvirtd"
          "kvm"
          "qemu-libvirtd"
          "wireshark"
          "hermes"
          "ydotool"
        ];
      };

      time = {
        timeZone = "America/Los_Angeles";
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
    };
}
