{ self, inputs, ... }:
{
  flake.nixosModules.hermes =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (lib) mkIf getExe;
      inherit (config) modules;
      inherit (modules.programs) default;

      username = config.modules.system.username;
      homeDirectory = config.modules.system.homeDirectory;

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
        inputs.hermes-agent.nixosModules.default
      ];

      hm.home.packages = with pkgs; [
        hermesChat
        hermesVoice
        desktopSession
        computerUseLinux
        chromium
        # Hermes Desktop (Electron) app — CLIENT ONLY on node0. The
        # gateway/agent runtime stays on head; the app must be connected to
        # head's gateway via remote mode (dashboard URL or SSH remote mode).
        # Never use the app's local backend here: it would spawn a second
        # agent runtime on node0.
        inputs.hermes-agent.packages.${pkgs.system}.desktop
        # Native Wayland computer-use: expose the Hermes CLI (computer_use /
        # cua-driver) inside the graphical session. The upstream hermes-agent
        # module only installs the CLI when `services.hermes-agent.enable` is
        # true; on node0 we keep the gateway service off and instead put the
        # CLI in the user profile so `hermes computer-use doctor` and the CUA
        # backend run with the session's Wayland/DBus env.
        config.services.hermes-agent.package
      ];

      # Native Wayland computer-use backend: cua-driver 0.19.2 is installed
      # by its own installer under ~/.cua-driver (not in nixpkgs); wire it
      # declaratively by pointing HERMES_CUA_DRIVER_CMD at the cached current
      # release and enabling the native Wayland backend. CUA_DRIVER_RS_ENABLE_WAYLAND
      # makes the driver use wlroots screencopy + foreign-toplevel instead of
      # the X11-only fallback.
      hm.home.sessionVariables = {
        HERMES_CUA_DRIVER_CMD = "${homeDirectory}/.cua-driver/packages/current/cua-driver";
        CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
      };

      # Ease the driver onto PATH too (its user-local bin link is stale after
      # the cenunix->overtoneblue migration); sessionVariables above are the
      # authoritative resolution, this is belt-and-suspenders.
      hm.home.sessionPath = [ "${homeDirectory}/.local/bin" ];

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
              -i ${homeDirectory}/.ssh/hermes_audio_tunnel \
              -o BatchMode=yes \
              -o IdentitiesOnly=yes \
              -o ExitOnForwardFailure=yes \
              -o ServerAliveInterval=30 \
              -o ServerAliveCountMax=3 \
              -R 172.18.0.1:9222:127.0.0.1:9222 \
              overtoneblue@10.1.1.24
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
              --user-data-dir=${homeDirectory}/.local/share/hermes-chromium \
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
              -i ${homeDirectory}/.ssh/hermes_audio_tunnel \
              -o BatchMode=yes \
              -o IdentitiesOnly=yes \
              -o ExitOnForwardFailure=yes \
              -o ServerAliveInterval=30 \
              -o ServerAliveCountMax=3 \
              -R 172.18.0.1:4713:127.0.0.1:4713 \
              overtoneblue@10.1.1.24
          '';

          Restart = "always";
          RestartSec = 5;
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      users.users.${username}.openssh.authorizedKeys.keys = [
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

      programs.ydotool.enable = true;
    };
}
