{
  ...
}:
{
  flake.nixosModules.desktop-services =
    { pkgs, ... }:
    {
      services.gnome.gnome-keyring.enable = true;
      services.gvfs.enable = true;
      services.tumbler.enable = true;
      services.udisks2.enable = true;
      security.pam.services.greetd.enableGnomeKeyring = true;
      security.polkit.enable = true;
      programs.seahorse.enable = true;

      programs.thunar = {
        enable = true;
        plugins = with pkgs; [
          thunar-archive-plugin
        ];
      };

      environment.systemPackages = with pkgs; [
        busybox
        pulseaudio
        xarchiver
        zip
        unzip
      ];
    };
}
