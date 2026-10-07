{ ... }:
{
  # User-facing packages that no feature module owns. Hosts opt in per group:
  #   modules.packages.groups = [ "media" "comms" ];
  # Installed via users.users.<name>.packages (no home-manager needed), so
  # head can take a group without pulling in home-manager. Packages a feature
  # module already installs stay in that module.
  flake.nixosModules.userPackages =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.modules.packages;

      groups = with pkgs; {
        media = [
          mpv
          imv
          gthumb
          geeqie
          plexamp
          plex-htpc
          jellyfin-desktop
          calibre
        ];

        comms = [
          telegram-desktop
          element-desktop
          thunderbird
        ];

        apps = [
          vscode
          # jetbrains.idea
          nextcloud-client
        ];

        desktop = [
          wl-clipboard
          libnotify
          pavucontrol
          ueberzugpp
          appimage-run
        ];

        gaming = [
          rimsort
        ];

        system = [
          usbutils
        ];
      };

      # Static so the option type never has to touch pkgs.
      groupNames = [
        "media"
        "comms"
        "apps"
        "desktop"
        "gaming"
        "system"
      ];
    in
    {
      options.modules.packages.groups = lib.mkOption {
        type = lib.types.listOf (lib.types.enum groupNames);
        default = [ ];
        description = "Package groups installed for the primary user on this host.";
      };

      config = {
        users.users.${config.modules.system.username}.packages = lib.concatMap (
          g: groups.${g}
        ) cfg.groups;

        # rimsort pulls in steamworkspy, which ships no dist-info, so
        # pythonMetadataCheckHook fails on it; disable that check for that
        # leaf only. Also rebind python314Packages or rimsort (which uses it
        # directly) still gets the un-overridden steamworkspy.
        nixpkgs.overlays = lib.mkIf (lib.elem "gaming" cfg.groups) [
          (final: prev: {
            python3 = prev.python3.override {
              packageOverrides = pf: pp: {
                steamworkspy = pp.steamworkspy.overridePythonAttrs (_: {
                  dontCheckPythonMetadata = true;
                });
              };
            };
            python314Packages = final.python3.pkgs;
          })
        ];
      };
    };
}
