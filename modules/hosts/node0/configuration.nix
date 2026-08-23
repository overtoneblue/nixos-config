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
        self.nixosModules.tailscale
        self.nixosModules.sound
        inputs.home-manager.nixosModules.home-manager
        (lib.mkAliasOptionModule [ "hm" ] [ "home-manager" "users" config.modules.system.username ])
        self.nixosModules.theme
        self.nixosModules.dev
        self.nixosModules.desktop
        self.nixosModules.ai
        self.nixosModules.hermes
      ];

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      hm.home.stateVersion = "25.11";
      hm.home.packages = with pkgs; [
        wl-clipboard
        plexamp
        element-desktop
        thunderbird
        appimage-run
        plex-htpc
        calibre
        gthumb
        telegram-desktop
        imv
        mpv
        geeqie
        ueberzugpp
        nextcloud-client
        libnotify
        vscode
        jetbrains.idea
      ];
      hm.programs = {
        obsidian = {
          enable = true;
          vaults = {
            Janaru = {
              enable = true;
              target = "${config.modules.system.homeDirectory}/Personal/Janaru/";
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
          # gitCredentialHelper.enable = true;
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
        yazi = {
          enable = true;
          plugins = {
            mediainfo = pkgs.yaziPlugins.mediainfo;
            wl-clipboard = pkgs.yaziPlugins.wl-clipboard;
          };
          settings = {
            plugin = {
              prepend_preloaders = [
                {
                  mime = "image/*";
                  run = "mediainfo";
                }
                {
                  mime = "video/*";
                  run = "mediainfo";
                }
              ];

              prepend_previewers = [
                {
                  mime = "image/*";
                  run = "mediainfo";
                }
                {
                  mime = "video/*";
                  run = "mediainfo";
                }
              ];
            };
          };
          keymap = {
            mgr.prepend_keymap = [
              {
                on = [ "<C-y>" ];
                run = "plugin wl-clipboard";
                desc = "wl-clipboard";
              }
              {
                on = [ "H" ];
                run = "tab_switch -1 --relative";
                desc = "Previous tab";
              }
              {
                on = [ "L" ];
                run = "tab_switch 1 --relative";
                desc = "Next tab";
              }
            ];
          };
        };
      };

      boot = {
        kernelPackages = pkgs.linuxPackages_latest;
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
          user = "greeter";
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --cmd '${lib.getExe config.programs.uwsm.package} start -eD Hyprland:GNOME -- hyprland.desktop'";
        };
      };

      services.openssh = {
        enable = true;
        openFirewall = true;

        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      security.sudo.extraConfig = ''
        Defaults:${config.modules.system.username} timestamp_type=global, timestamp_timeout=120
      '';

      networking.hostName = "node0";

      time.hardwareClockInLocalTime = true;

      environment.systemPackages = with pkgs; [
        usbutils
      ];
    };
}
