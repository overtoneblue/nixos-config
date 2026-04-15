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
        self.nixosModules.niri
      ];

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
        firefox
        zed
        helix
        neovim
        vscode
      ];
    };
}
