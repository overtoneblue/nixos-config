{ self, ... }:
{
  flake.nixosModules.headConfiguration =
    {
      self,
      pkgs,
      config,
      lib,
      ...
    }:
    let
      # Passwordless deploy wrapper with a fixed target and a tiny surface:
      # only switch, boot or test. User-supplied flags are never forwarded.
      headRebuild = pkgs.writeShellScriptBin "head-rebuild" ''
        set -eu

        # Transient units (systemd-run) and other non-login contexts do NOT
        # inherit a usable PATH: `nix` becomes unresolvable and nh aborts with
        # "No output from nix --version" (seen live 2026-08-31, twice).
        # Self-anchor to the stable system profile instead of trusting callers.
        export PATH=/run/current-system/sw/bin:$PATH

        case "$#" in
          0)
            mode=switch
            ;;
          1)
            case "$1" in
              switch|boot|test)
                mode="$1"
                ;;
              *)
                echo "usage: head-rebuild [switch|boot|test]" >&2
                exit 64
                ;;
            esac
            ;;
          *)
            echo "usage: head-rebuild [switch|boot|test]" >&2
            exit 64
            ;;
        esac

        exec ${lib.getExe config.programs.nh.package} os "$mode" \
          /srv/nixos-config#head \
          --elevation-strategy none \
          --bypass-root-check \
          --show-activation-logs
      '';

      # `desktop <command...>` runs a command in node0's graphical session
      # via `desktop-session` (see features/desktop/automation.nix).
      # Arguments are %q-quoted so the remote shell rebuilds the exact argv.
      # Services can override DESKTOP_SSH_KEY / DESKTOP_KNOWN_HOSTS.
      desktop = pkgs.writeShellApplication {
        name = "desktop";
        runtimeInputs = [ pkgs.openssh ];
        text = ''
          set -euo pipefail

          if [[ $# -eq 0 ]]; then
            echo "usage: desktop <command...>" >&2
            exit 2
          fi

          : "''${DESKTOP_SSH_KEY:=/home/overtoneblue/hermes-recovery/hermes-ssh/desktop_ed25519}"
          : "''${DESKTOP_KNOWN_HOSTS:=/home/overtoneblue/.ssh/known_hosts}"

          remote=()
          arg=
          for arg in "$@"; do
            remote+=("$(printf '%q' "$arg")")
          done

          exec ${lib.getExe pkgs.openssh} \
            -i "$DESKTOP_SSH_KEY" \
            -o BatchMode=yes \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=yes \
            -o UserKnownHostsFile="$DESKTOP_KNOWN_HOSTS" \
            -o ConnectTimeout=15 \
            overtoneblue@node0 \
            desktop-session "''${remote[*]}"
        '';
      };
    in
    {
      modules.system.desktopCommand = desktop;

      imports = [
        self.nixosModules.options
        ./_system.nix
        self.nixosModules.headHardware
        self.nixosModules.headStorage
        self.nixosModules.headSops
        self.nixosModules.headOpenCode
        self.nixosModules.headPi
        self.nixosModules.headJellyfin
        self.nixosModules.headNextcloud
        self.nixosModules.headNginxProxy
        self.nixosModules.headMatrix
        self.nixosModules.headWavegen
        self.nixosModules.headWavegenWeb
        self.nixosModules.base
        self.nixosModules.network
        self.nixosModules.tailscale
        self.nixosModules.nix-settings
        self.nixosModules.dev
      ];

      boot.loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };

      networking = {
        hostName = "head";
        firewall.allowPing = true;
      };

      services.logind.settings.Login = {
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
        HandleSuspendKey = "ignore";
        HandleHibernateKey = "ignore";
      };

      systemd.sleep.settings.Sleep = {
        AllowSuspend = "no";
        AllowHibernation = "no";
        AllowHybridSleep = "no";
        AllowSuspendThenHibernate = "no";
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

      # System-wide, so services (e.g. via DESKTOP_KNOWN_HOSTS) can reach
      # node0 with strict host key checking.
      programs.ssh.knownHosts.node0 = {
        hostNames = [ "node0" "10.1.1.174" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIyoNmOgQES9ANxbKTjb9p6zTc4+sRC325cFwd426dnU";
      };

      users.users.${config.modules.system.username} = {
        extraGroups = [ "admin" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJr8vXNPsadegcZ64bobPFk42Cnokwrn08tLE9Jab6ik hermes-audio-tunnel"
        ];
      };

      security.sudo.wheelNeedsPassword = true;

      # Owns /srv/nixos-config.
      users.groups.admin = { };

      # setgid dirs so new files inherit the admin group; no world access.
      system.activationScripts."nixos-config-admin-group" = lib.stringAfter [ "users" ] ''
        chgrp -R admin /srv/nixos-config 2>/dev/null || true
        find /srv/nixos-config -type d -exec chmod 2770 {} +
        find /srv/nixos-config -type f -exec chmod g+rw {} +
      '';

      security.sudo.extraRules = [
        {
          # Use the stable system-profile path: sudo matches the invoked
          # symlink path, not the immutable /nix/store target it resolves to.
          # In sudoers, an argument string of "" means exactly no arguments.
          users = [ "overtoneblue" ];
          runAs = "root";
          commands = [
            {
              command = "/run/current-system/sw/bin/head-rebuild \"\"";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/head-rebuild switch";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/head-rebuild boot";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/head-rebuild test";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      virtualisation.docker.enable = true;

      # libgit2 (Nix's flake fetcher) refuses repos not owned by euid /
      # SUDO_UID, and `sudo head-rebuild` fetches this repo as root. Allowlist
      # only this path, at system scope: root has no global gitconfig and
      # libgit2 ignores GIT_CONFIG_* env.
      environment.etc."gitconfig".text = ''
        [safe]
          directory = /srv/nixos-config
      '';

      environment.systemPackages = with pkgs; [
        headRebuild
        config.modules.system.desktopCommand
        tmux
        wget
        curl
        smartmontools
        xfsprogs
        mergerfs
        intel-gpu-tools
        self.packages.${pkgs.stdenv.hostPlatform.system}.head-dash
        pkgs.claude-code
      ];

      # The tailnet's global resolver is the pihole; with accept-dns, head
      # sends every lookup there and loses all name resolution whenever the
      # pihole is down.
      services.tailscale.extraSetFlags = [ "--accept-dns=false" ];

      system.stateVersion = "26.05";
    };
}
