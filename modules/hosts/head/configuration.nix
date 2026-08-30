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
      # Passwordless deployment wrapper. Root-owned (Nix store), fixed target,
      # and a deliberately tiny action surface: only switch, boot, or test.
      # Arbitrary user-supplied flags are rejected instead of being forwarded.
      headRebuild = pkgs.writeShellScriptBin "head-rebuild" ''
        set -eu

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

      # ── Desktop bridge ──────────────────────────────────────────────
      # `desktop <command...>` runs a command inside the node0 graphical
      # session via a dedicated SSH identity. It SSHes non-interactively to
      # overtoneblue@node0 and executes the command under `desktop-session`,
      # which imports the live Wayland/DBus/XDG/Hyprland session environment
      # (see modules/features/hermes).
      #
      # Identity is identity-aware via env vars, so the SAME wrapper serves
      # both callers without touching /home/overtoneblue permissions:
      #   - interactive overtoneblue TUI  -> defaults to the overtoneblue key
      #     + known_hosts (unchanged behavior)
      #   - hermes-agent.service          -> DESKTOP_SSH_KEY /
      #     DESKTOP_KNOWN_HOSTS are injected by the service unit (sops-rendered
      #     hermes-owned key + Nix-managed system known_hosts), keeping this
      #     wrapper and the interactive path identical.
      #
      # Each argument is shell-quoted with bash %q so the remote zsh
      # reconstructs the exact argv (no word-splitting / injection).
      # Host verification stays strict; the known_hosts file is supplied via
      # the env var (interactive: user file; service: /etc/ssh/ssh_known_hosts
      # populated declaratively by programs.ssh.knownHosts).
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
      # Expose the shared `desktop` command so both the interactive head
      # profile (environment.systemPackages below) and the Hermes gateway
      # (services/head/hermes.nix extraPackages) can reference the same
      # wrapper package.
      modules.system.desktopCommand = desktop;

      imports = [
        self.nixosModules.options
        ./_system.nix
        self.nixosModules.headHardware
        self.nixosModules.headStorage
        self.nixosModules.headSops
        self.nixosModules.headHermes
        self.nixosModules.headOpenCode
        self.nixosModules.headJellyfin
        self.nixosModules.headNextcloud
        self.nixosModules.headNginxProxy
        self.nixosModules.base
        self.nixosModules.network
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
        # Hermes dashboard — LAN access on port 9119 (requested 2026-08-25)
        firewall.allowedTCPPorts = [ 9119 ];
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

      # ── System-wide SSH known-hosts (host public keys are NOT secrets) ──
      # Node0's ED25519 host key, managed declaratively (writes
      # /etc/ssh/ssh_known_hosts, world-readable) so any local user or service
      # — including hermes-agent.service — can connect to node0 with strict
      # host verification. The `desktop` bridge uses this file when running
      # under the service (DESKTOP_KNOWN_HOSTS); the interactive TUI keeps its
      # user-scoped known_hosts.
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

      # ── Shared declarative admin group ────────────────────────────────
      # Both trusted admins (overtoneblue and hermes) share group `admin`
      # for the /srv/nixos-config worktree and loose sudo administration.
      users.groups.admin = { };

      # ── /srv/nixos-config group ownership + setgid inheritance ────────
      # The %admin group gets rwx, the directory carries the setgid bit so
      # new files/dirs inherit the admin group, and the world bit stays off
      # (nothing in the config repo becomes world-readable).
      system.activationScripts."nixos-config-admin-group" = lib.stringAfter [ "users" ] ''
        chgrp -R admin /srv/nixos-config 2>/dev/null || true
        find /srv/nixos-config -type d -exec chmod 2770 {} +
        find /srv/nixos-config -type f -exec chmod g+rw {} +
      '';

      # ── Passwordless sudo for autonomous administration ───────────────
      # Nolan (the gateway service user, hermes) is intentionally trusted
      # to administer this host autonomously. It already holds effective
      # root-equivalent authority (writable /srv/nixos-config + the deploy
      # path), so avoid brittle per-command/path sudoers matching and grant
      # broad passwordless sudo instead: `sudo <anything>` from the gateway
      # just works.
      security.sudo.extraRules = [
        {
          # Gateway service (Nolan): any command, any user, no password.
          users = [ "hermes" ];
          runAs = "ALL";
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
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

      # The service PATH is deliberately explicit; make the only authorized
      # deployment target resolvable as `head-rebuild` without adding the
      # whole system profile.
      systemd.services.hermes-agent.path = [ headRebuild ];

      # ── Nix-daemon privilege boundary ──────────────────────────────────
      # hermes (the gateway service user) may submit builds to the Nix
      # daemon for validation/debugging (`nh os build`), but must NOT be a
      # trusted user — trusted users are root-equivalent for Nix (arbitrary
      # substituters, settings, cross-user builds). hermes is therefore kept
      # OUT of wheel (so @wheel in nix-settings' trusted-users does not cover
      # it) and granted only allowed-users here. overtoneblue stays in wheel
      # and remains trusted; the single-command head-rebuild sudo grant is
      # per-user, independent of wheel.
      nix.settings.allowed-users = [ "hermes" ];

      virtualisation.docker.enable = true;

      # libgit2 (Nix's flake fetcher) refuses git repos not owned by euid /
      # SUDO_UID. `sudo head-rebuild` runs as root with SUDO_UID=hermes(994)
      # against this overtoneblue-owned repo, so root's flake fetch of
      # git+file:///srv/nixos-config needs a safe.directory allowlist for
      # exactly this path. System scope (not global `*`): the fetch runs with
      # HOME=/root (no root global gitconfig) and GIT_CONFIG_* env is ignored
      # because libgit2 is opened with use_env=false.
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
      ];

      system.stateVersion = "26.05";
    };
}
