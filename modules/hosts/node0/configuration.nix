{ self, inputs, ... }:
{

  flake.nixosModules.node0Configuration =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      imports = [
        self.nixosModules.options
        ./_system.nix
        self.nixosModules.node0Hardware
        self.nixosModules.base
        self.nixosModules.nix-settings
        self.nixosModules.network
        self.nixosModules.sound
        # self.nixosModules.niri
        self.nixosModules.gaming
        inputs.home-manager.nixosModules.home-manager
        (lib.mkAliasOptionModule [ "hm" ] [ "home-manager" "users" "cenunix" ])
        self.nixosModules.theme
        self.nixosModules.hyprland
        self.nixosModules.dev
        self.nixosModules.firefox
        self.nixosModules.signal
      ];

      hm.home.username = "cenunix";
      hm.home.homeDirectory = "/home/cenunix";
      hm.home.stateVersion = "25.11";
      hm.home.packages = with pkgs; [
        wl-clipboard
        gist # manage github gists
        act # local github actions
        zsh-forgit # zsh plugin to load forgit via `git forgit`
        gitflow
        ripgrep # recursively searches directories for a regex pattern
        plexamp
      ];
      hm.programs = {

        bash = {
          enable = true;
          initExtra = "SHELL=${pkgs.bash}";
        };

        # a command-line tool for github
        gh = {
          enable = true;
          gitCredentialHelper.enable = true;
          extensions = with pkgs; [
            gh-dash # dashboard with pull requests and issues
            gh-eco # explore the ecosystem
            gh-cal # contributions calender terminal viewer
          ];
          settings = {
            version = 1;
            git_protocol = "ssh";
            prompt = "enabled";
          };
        };

      };
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
      services.gnome.gnome-keyring.enable = true;
      programs.seahorse.enable = true;
      networking.hostName = "node0"; # Define your hostname.
      environment.systemPackages = with pkgs; [
        thunar
        vscode
      ];
    };
}
