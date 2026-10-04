{ inputs, ... }:
{
  # node0 end of head's `desktop` bridge, plus computer-use tooling and the
  # accessibility/input plumbing it relies on.
  flake.nixosModules.desktop-automation =
    {
      pkgs,
      config,
      ...
    }:
    let
      username = config.modules.system.username;
      homeDirectory = config.modules.system.homeDirectory;

      computerUseLinux = pkgs.rustPlatform.buildRustPackage {
        pname = "computer-use-linux";
        version = "0.4.9";

        src = inputs.computer-use-linux;

        # Adds monitor targeting to the screenshot tool.
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
    in
    {
      hm.home.packages = with pkgs; [
        desktopSession
        computerUseLinux
        chromium
      ];

      # cua-driver isn't in nixpkgs; its own installer puts it under
      # ~/.cua-driver. This makes it use wlroots screencopy instead of the
      # X11-only fallback.
      hm.home.sessionVariables = {
        CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
      };

      hm.home.sessionPath = [ "${homeDirectory}/.local/bin" ];

      # Key behind head's `desktop` bridge (head -> node0 graphical session).
      users.users.${username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBttEvb3mNaTHjsc0lCB7oiGqXOZnncFYh4NKOzzWpmc hermes-desktop-control"
      ];

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
