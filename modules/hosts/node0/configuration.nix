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
        inputs.home-manager.nixosModules.home-manager
        (lib.mkAliasOptionModule [ "hm" ] [ "home-manager" "users" "cenunix" ])
        self.nixosModules.theme
        self.nixosModules.dev
        self.nixosModules.desktop
        inputs.hermes-agent.nixosModules.default
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
        thunderbird
        whois
        appimage-run
        plex-htpc
        calibre
        gthumb
        #new
        imv
        mediainfo
        mpv
        geeqie
        imagemagick
        exiftool
        fd
        ueberzugpp
        nextcloud-client
        pandoc
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
      services.hermes-agent = {
        enable = true;
        addToSystemPackages = true;
        settings = {
          display = {
            streaming = true;
            show_cost = true;
          };
          memory.write_approval = true;
          skills.write_approval = true;
        };
      };
      services.gnome.gnome-keyring.enable = true;
      services.gvfs.enable = true;
      services.tumbler.enable = true;
      services.udisks2.enable = true;
      security.pam.services.greetd.enableGnomeKeyring = true;
      security.polkit.enable = true;
      security.sudo.extraConfig = ''
        Defaults:cenunix timestamp_type=global, timestamp_timeout=120
      '';
      programs.seahorse.enable = true;

      #Hermes-agent
      services.gnome.at-spi2-core.enable = true;
      services.envfs.enable = true;
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc
          zlib
          glib
          dbus
          libGL
          libxkbcommon
          fontconfig
          freetype

          xorg.libX11
          xorg.libXext
          xorg.libXrender
          xorg.libXrandr
          xorg.libXi
          xorg.libXtst
          xorg.libXfixes
          xorg.libXcursor
          xorg.libXinerama
          xorg.libxcb
        ];
      };

      # services.displayManager.sessionPackages = [
      #   (pkgs.writeTextFile {
      #     name = "hyprland-uwsm-gnome-session";
      #     destination = "/share/wayland-sessions/hyprland-uwsm-gnome.desktop";
      #     text = ''
      #       [Desktop Entry]
      #       Name=Hyprland (UWSM, GNOME desktop names)
      #       Comment=Hyprland compositor managed by UWSM
      #       Exec=${lib.getExe config.programs.uwsm.package} start -eD Hyprland:GNOME -- hyprland.desktop
      #       TryExec=${lib.getExe config.programs.uwsm.package}
      #       Type=Application
      #       DesktopNames=Hyprland;GNOME
      #       Keywords=tiling;wayland;compositor;
      #     '';
      #     derivationArgs = {
      #       passthru.providedSessions = [ "hyprland-uwsm-gnome" ];
      #     };
      #   })
      # ];
      virtualisation.oci-containers.backend = "podman";
      virtualisation.oci-containers.containers.comfyui = {
        image = "ghcr.io/utensils/comfyui-nix:latest-cuda";
        autoStart = false;

        ports = [
          "127.0.0.1:8188:8188"
        ];

        volumes = [
          "/home/cenunix/ai/comfyui-nix-data:/data"
        ];

        environment = {
          USER = "comfyui";
          LOGNAME = "comfyui";
          HOME = "/data/user";
          TORCHINDUCTOR_CACHE_DIR = "/data/user/.cache/torchinductor";
        };

        extraOptions = [
          "--device=nvidia.com/gpu=all"
        ];

        cmd = [
          "--listen"
          "0.0.0.0"
          "--enable-manager"
          "--lowvram"
        ];
      };
      virtualisation.podman = {
        enable = true;

        # Gives you a `docker` compatibility CLI if something expects Docker.
        dockerCompat = true;

        # Useful for DNS/networking in containers.
        defaultNetwork.settings.dns_enabled = true;
      };
      # virtualisation.docker = {
      #   enable = true;
      #   rootless = {
      #     enable = true;
      #     setSocketVariable = true;
      #     # Optionally customize rootless Docker daemon settings
      #     daemon.settings = {
      #       dns = [
      #         "1.1.1.1"
      #         "8.8.8.8"
      #       ];
      #       registry-mirrors = [ "https://mirror.gcr.io" ];
      #     };
      #   };
      # };
      hardware.nvidia-container-toolkit.enable = true;
      networking.hostName = "node0"; # Define your hostname.
      programs.thunar = {
        enable = true;
        plugins = with pkgs; [
          thunar-archive-plugin
        ];
      };
      environment.systemPackages = with pkgs; [
        busybox
        xarchiver
        zip
        unzip
        vscode
        jetbrains.idea
        podman
        podman-compose
        usbutils
        docker-compose
      ];
    };
}
