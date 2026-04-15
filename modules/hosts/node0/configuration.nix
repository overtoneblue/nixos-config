{ self, inputs, ... }:
{

  flake.nixosModules.node0Configuration =
    { pkgs, lib, ... }:
    {
      # import any other modules from here
      imports = [
        self.nixosModules.node0Hardware
        self.nixosModules.base
        self.nixosModules.nix-settings
        self.nixosModules.network
        self.nixosModules.sound
        self.nixosModules.niri
        self.nixosModules.gaming
        inputs.home-manager.nixosModules.home-manager
        (lib.mkAliasOptionModule [ "hm" ] [ "home-manager" "users" "cenunix" ])
        # self.nixosModules.hyprland
      ];

      hm.home.username = "cenunix";
      hm.home.homeDirectory = "/home/cenunix";
      hm.home.stateVersion = "25.11";

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      boot = {
        kernelPackages = pkgs.linuxPackages;
        loader = {
          systemd-boot.enable = true;
          efi.canTouchEfiVariables = true;
        };
      };

      networking.hostName = "node0"; # Define your hostname.

      environment.systemPackages = with pkgs; [
        git
        thunar
        firefox
        zed
        helix
        neovim
        vscode
      ];
    };
}
