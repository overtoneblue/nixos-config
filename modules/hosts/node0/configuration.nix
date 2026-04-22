{ self, inputs, ... }:
{

  flake.nixosModules.node0Configuration =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (lib) mkIf;
      inherit (config) modules;
      inherit (modules) device;
    in
    {
      imports = [
        self.nixosModules.options
        ./_system.nix
        self.nixosModules.node0Hardware
        self.nixosModules.base
        self.nixosModules.nix-settings
        self.nixosModules.network
        self.nixosModules.sound
        self.nixosModules.gaming
        inputs.home-manager.nixosModules.home-manager
        (lib.mkAliasOptionModule [ "hm" ] [ "home-manager" "users" "cenunix" ])
        self.nixosModules.theme
        self.nixosModules.dev
        self.nixosModules.desktop
      ];

      nixpkgs.config.allowUnfree = true;
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
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
        element-desktop
      ];

      hm.programs = {
        obsidian = {
          enable = true;
          vaults = {
            Janaru = {
              enable = true;
              target = "/home/cenunix/Personal/Janaru/";
            };
          };
        };
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
            git_protocol = "https";
            prompt = "enabled";
          };
        };

      };

      boot = {
        kernelPackages = pkgs.linuxPackages;
        loader = {
          systemd-boot.enable = true;
          efi.canTouchEfiVariables = true;
        };
      };

      environment.etc."greetd/sway-regreet.conf".text =
        let
          monitorConfig = builtins.concatStringsSep "\n" (
            builtins.map (monitor: "monitor=${monitor}") device.monitors
          );
        in

        ''
          # Main monitor
          output DP-2 mode 2560x1440@239.97Hz position 0 0 scale 1

          # Vertical side monitor
          output DP-1 disable

          # If you want the side monitor OFF for the greeter instead, use:
          # output HDMI-A-1 disable

          exec "${pkgs.regreet}/bin/regreet; ${pkgs.sway}/bin/swaymsg exit"

          # Keep the greeter minimal
          seat seat0 xcursor_theme Bibata-Modern-Ice 24
          default_border none
          default_floating_border none
          hide_edge_borders smart        '';

      services.greetd = {
        enable = true;
        settings.default_session = {
          command = "${pkgs.dbus}/bin/dbus-run-session ${pkgs.sway}/bin/sway --unsupported-gpu --config /etc/greetd/sway-regreet.conf";
          user = "greeter";
        };
      };
      programs.regreet = {
        enable = true;
        settings = {
          GTK = {
            application_prefer_dark_theme = lib.mkForce true;
          };
        };
      };
      services.gnome.gnome-keyring.enable = true;
      security.pam.services.greetd.enableGnomeKeyring = true;
      security.polkit.enable = true;
      programs.seahorse.enable = true;

      services.displayManager.sessionPackages = [
        (pkgs.writeTextFile {
          name = "hyprland-uwsm-gnome-session";
          destination = "/share/wayland-sessions/hyprland-uwsm-gnome.desktop";
          text = ''
            [Desktop Entry]
            Name=Hyprland (UWSM, GNOME desktop names)
            Comment=Hyprland compositor managed by UWSM
            Exec=${lib.getExe config.programs.uwsm.package} start -eD Hyprland:GNOME -- hyprland.desktop
            TryExec=${lib.getExe config.programs.uwsm.package}
            Type=Application
            DesktopNames=Hyprland;GNOME
            Keywords=tiling;wayland;compositor;
          '';
          derivationArgs = {
            passthru.providedSessions = [ "hyprland-uwsm-gnome" ];
          };
        })
      ];

      networking.hostName = "node0"; # Define your hostname.
      environment.systemPackages = with pkgs; [
        thunar
        vscode
      ];
    };
}
