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
      inherit (modules.programs) default;

      computerUseLinux = pkgs.rustPlatform.buildRustPackage {
        pname = "computer-use-linux";
        version = "0.4.9";

        src = inputs.computer-use-linux;

        # Monitor/output targeting for the screenshot tool, applied on top of
        # upstream. If upstream changes so this no longer applies, the build
        # fails loudly rather than silently losing monitor targeting.
        patches = [
          ../../../patches/computer-use-linux-monitor-target.patch
        ];

        cargoLock = {
          lockFile = "${inputs.computer-use-linux}/Cargo.lock";
        };

        doCheck = false;
      };

      desktopSession = pkgs.writeShellApplication {
        name = "desktop-session";

        runtimeInputs = [
          pkgs.coreutils
          pkgs.systemd
        ];

        text = ''
          set -euo pipefail

          # Import graphical-session variables maintained by UWSM/systemd.
          while IFS= read -r line; do
            case "$line" in
              XDG_RUNTIME_DIR=*)
                XDG_RUNTIME_DIR="''${line#*=}"
                export XDG_RUNTIME_DIR
                ;;
              WAYLAND_DISPLAY=*)
                WAYLAND_DISPLAY="''${line#*=}"
                export WAYLAND_DISPLAY
                ;;
              DISPLAY=*)
                DISPLAY="''${line#*=}"
                export DISPLAY
                ;;
              HYPRLAND_INSTANCE_SIGNATURE=*)
                HYPRLAND_INSTANCE_SIGNATURE="''${line#*=}"
                export HYPRLAND_INSTANCE_SIGNATURE
                ;;
              DBUS_SESSION_BUS_ADDRESS=*)
                DBUS_SESSION_BUS_ADDRESS="''${line#*=}"
                export DBUS_SESSION_BUS_ADDRESS
                ;;
              XDG_CURRENT_DESKTOP=*)
                XDG_CURRENT_DESKTOP="''${line#*=}"
                export XDG_CURRENT_DESKTOP
                ;;
              XDG_SESSION_DESKTOP=*)
                XDG_SESSION_DESKTOP="''${line#*=}"
                export XDG_SESSION_DESKTOP
                ;;
              XDG_SESSION_TYPE=*)
                XDG_SESSION_TYPE="''${line#*=}"
                export XDG_SESSION_TYPE
                ;;
            esac
          done < <(systemctl --user show-environment)

          # Sensible fallbacks for the standard per-user runtime paths.
          if [[ -z "''${XDG_RUNTIME_DIR:-}" ]]; then
            XDG_RUNTIME_DIR="/run/user/$(id -u)"
            export XDG_RUNTIME_DIR
          fi

          if [[ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]] &&
             [[ -S "$XDG_RUNTIME_DIR/bus" ]]; then
            DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
            export DBUS_SESSION_BUS_ADDRESS
          fi

          if [[ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
            echo "desktop-session: no active Hyprland session found" >&2
            exit 1
          fi

          exec "$@"
        '';
      };
      hermesChat = pkgs.writeShellApplication {
        name = "hermes-chat";

        runtimeInputs = [
          pkgs.openssh
          pkgs.coreutils
        ];

        text = ''
          set -euo pipefail

          STATE_DIR="''${XDG_RUNTIME_DIR:?}/hermes"
          PANE_FILE="$STATE_DIR/wezterm-pane"
          SOCKET_FILE="$STATE_DIR/wezterm-socket"

          mkdir -p "$STATE_DIR"

          if [[ -z "''${WEZTERM_PANE:-}" || -z "''${WEZTERM_UNIX_SOCKET:-}" ]]; then
            echo "hermes-chat must be launched from WezTerm" >&2
            exit 1
          fi

          PANE="$WEZTERM_PANE"
          SOCKET="$WEZTERM_UNIX_SOCKET"

          ${default.terminal} cli set-tab-title --pane-id "$PANE" HERMES

          printf '%s\n' "$PANE" > "$PANE_FILE"
          printf '%s\n' "$SOCKET" > "$SOCKET_FILE"

          cleanup() {
            if [[ -f "$PANE_FILE" ]] &&
               [[ "$(cat "$PANE_FILE" 2>/dev/null)" == "$PANE" ]]; then
              rm -f "$PANE_FILE" "$SOCKET_FILE"
            fi
          }

          trap cleanup EXIT

          ssh -t tower \
            'docker exec -u hermes -it Hermes-Agent /opt/hermes/.venv/bin/hermes chat'
        '';
      };

      hermesVoice = pkgs.writeShellApplication {
        name = "hermes-voice";

        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
        ];

        text = ''
          set -euo pipefail

          STATE_DIR="''${XDG_RUNTIME_DIR:?}/hermes"
          PANE_FILE="$STATE_DIR/wezterm-pane"
          SOCKET_FILE="$STATE_DIR/wezterm-socket"

          mkdir -p "$STATE_DIR"

          load_target() {
            [[ -r "$PANE_FILE" ]] || return 1
            [[ -r "$SOCKET_FILE" ]] || return 1

            PANE="$(cat "$PANE_FILE")"
            SOCKET="$(cat "$SOCKET_FILE")"

            [[ -n "$PANE" && -n "$SOCKET" ]]
          }

          target_alive() {
            load_target || return 1

            WEZTERM_UNIX_SOCKET="$SOCKET" \
              ${default.terminal} cli get-text \
                --pane-id "$PANE" \
                >/dev/null 2>&1
          }

          #
          # If Hermes isn't already alive, summon it.
          #
          if ! target_alive; then
            rm -f "$PANE_FILE" "$SOCKET_FILE"

            ${default.terminal} start \
              --always-new-process \
              --class HERMES \
              -- \
              ${lib.getExe hermesChat} \
              >/dev/null 2>&1 &
          fi
        '';
      };
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
        telegram-desktop
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
        hermesChat
        hermesVoice
        desktopSession
        computerUseLinux
        libnotify
        chromium
      ];
      hm.systemd.user.services.hermes-browser-tunnel = {
        Unit = {
          Description = "Hermes reverse SSH browser CDP tunnel";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          ExecStart = ''
            ${lib.getExe pkgs.openssh} \
              -N \
              -T \
              -i /home/cenunix/.ssh/hermes_audio_tunnel \
              -o BatchMode=yes \
              -o IdentitiesOnly=yes \
              -o ExitOnForwardFailure=yes \
              -o ServerAliveInterval=30 \
              -o ServerAliveCountMax=3 \
              -R 172.18.0.1:9222:127.0.0.1:9222 \
              root@10.1.1.24
          '';

          Restart = "always";
          RestartSec = 5;
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      };
      hm.systemd.user.services.hermes-chromium = {
        Unit = {
          Description = "Dedicated Chromium browser for Hermes";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = ''
            ${lib.getExe pkgs.chromium} \
              --remote-debugging-address=127.0.0.1 \
              --remote-debugging-port=9222 \
              --user-data-dir=/home/cenunix/.local/share/hermes-chromium \
              --class=hermes-browser \
              --no-first-run \
              --no-default-browser-check
          '';

          Restart = "always";
          RestartSec = 3;
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
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

      hm.programs.ssh = {
        enable = true;

        matchBlocks = {
          tower = {
            hostname = "10.1.1.24";
            user = "root";
            identityFile = "~/.ssh/hermes_audio_tunnel";
            identitiesOnly = true;
          };
        };
      };

      hm.systemd.user.services.hermes-audio-tunnel = {
        Unit = {
          Description = "Hermes reverse SSH audio tunnel";
          After = [
            "pipewire-pulse.service"
          ];
          Wants = [
            "pipewire-pulse.service"
          ];
        };

        Service = {
          ExecStart = ''
            ${lib.getExe pkgs.openssh} \
              -N \
              -T \
              -i /home/cenunix/.ssh/hermes_audio_tunnel \
              -o BatchMode=yes \
              -o IdentitiesOnly=yes \
              -o ExitOnForwardFailure=yes \
              -o ServerAliveInterval=30 \
              -o ServerAliveCountMax=3 \
              -R 172.18.0.1:4713:127.0.0.1:4713 \
              root@10.1.1.24
          '';

          Restart = "always";
          RestartSec = 5;
        };

        Install = {
          WantedBy = [ "default.target" ];
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

      users.users.cenunix.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBttEvb3mNaTHjsc0lCB7oiGqXOZnncFYh4NKOzzWpmc hermes-desktop-control"
      ];
      services.hermes-agent = {
        enable = false;
        addToSystemPackages = true;
        extraDependencyGroups = [
          "messaging"
          "voice"
          "edge-tts"
        ];
        extraPackages = with pkgs; [
          ffmpeg
          kittenTTS
        ];
        environmentFiles = [
          "/var/lib/hermes/env"
        ];
        settings = {
          agent = {
            reasoning_effort = "high";
          };
          model = {
            provider = "deepseek";
            default = "deepseek-v4-flash";
          };
          display = {
            streaming = true;
            show_cost = true;
            show_reasoning = false;
          };
          memory.write_approval = true;
          skills.write_approval = true;
          stt = {
            provider = "local";
            local.model = "base";
          };
          tts = {
            provider = "kittentts";

            kittentts = {
              model = "KittenML/kitten-tts-nano-0.8-int8";
              voice = "Jasper";
              speed = 1.0;
              clean_text = true;
            };
          };
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
      programs.ydotool.enable = true;

      environment.systemPackages = with pkgs; [
        busybox
        pulseaudio
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
