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

      # ── Passwordless single-command deployment (mirror of head) ────────
      # `sudo node-rebuild` rebuilds/switches the node0 flake. Wrapper is
      # argumentless; the sudoers rule below pins the `''` empty-arg form so
      # the grant can never be widened by appending arguments.
      nodeRebuild = pkgs.writeShellScriptBin "node-rebuild" ''
        # Transient/non-login contexts do not inherit a usable PATH: `nix`
        # becomes unresolvable and nh aborts (same flaw fixed on head's
        # head-rebuild 2026-08-31). Self-anchor to the system profile.
        export PATH=/run/current-system/sw/bin:$PATH

        exec ${lib.getExe config.programs.nh.package} os switch \
          ${config.modules.system.flakePath}#node0 \
          --elevation-strategy none \
          --bypass-root-check \
          --show-activation-logs
      '';
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
        # `ssh head` from node0 maps to the account that exists on head. node0
        # and head now share the same primary account `overtoneblue`
        # (modules.system.username, formerly `cenunix` before the node0 account
        # migration), and head already authorizes the `hermes_audio_tunnel` key
        # for that account. Without this alias, `ssh head` tries the local
        # username and fails with "Permission denied (publickey)".
        ssh = {
          enable = true;
          matchBlocks = {
            head = {
              hostname = "10.1.1.24";
              user = "overtoneblue";
              identityFile = "~/.ssh/hermes_audio_tunnel";
              identitiesOnly = true;
            };
          };
        };
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
      };

      # ── Account migration: cenunix → overtoneblue ───────────────────
      # The primary account on node0 moves from `cenunix` to the shared
      # `overtoneblue` (modules.system.username). Pin UID 1000 explicitly so
      # filesystem ownership is preserved exactly across the rename (the old
      # cenunix account is 1000; an auto-assigned id could drift to 1001).
      # homeDirectory resolves from the shared default
      # (/home/${username} = /home/overtoneblue).
      users.users.${config.modules.system.username}.uid = 1000;

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

      # ── Passwordless deployment grant (mirrors head) ──────────────────
      # Only the primary user may switch this host, and only via the exact
      # argumentless `node-rebuild` wrapper. The `''` pin mirrors head: any
      # `node-rebuild <arg>` invocation is rejected by sudo itself.
      security.sudo.extraRules = [
        {
          users = [ config.modules.system.username ];
          runAs = "root";
          commands = [
            {
              command = "${nodeRebuild}/bin/node-rebuild ''";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      networking.hostName = "node0";

      time.hardwareClockInLocalTime = true;

      environment.systemPackages = with pkgs; [
        usbutils
        nodeRebuild
      ];
    };
}
