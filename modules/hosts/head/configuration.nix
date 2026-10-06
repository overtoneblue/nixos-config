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
      # via `desktop-session` (see features/hermes). Arguments are
      # %q-quoted so the remote shell rebuilds the exact argv. The
      # hermes-agent unit overrides DESKTOP_SSH_KEY / DESKTOP_KNOWN_HOSTS.
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
        self.nixosModules.headHermes
        self.nixosModules.headOpenCode
        self.nixosModules.headPi
        self.nixosModules.headDebbieTask
        self.nixosModules.headJellyfin
        self.nixosModules.headNextcloud
        self.nixosModules.headNginxProxy
        self.nixosModules.headMatrix
        self.nixosModules.headAtlasHub
        self.nixosModules.headAtlasd
        self.nixosModules.headAtlasWeb
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

      # hermes already has root-equivalent reach (writable /srv/nixos-config
      # plus the deploy path), so it gets unrestricted passwordless sudo
      # rather than brittle per-command rules.
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

      # libgit2 (Nix's flake fetcher) refuses repos not owned by euid /
      # SUDO_UID, and `sudo head-rebuild` fetches this repo as root. Allowlist
      # only this path, at system scope: root has no global gitconfig and
      # libgit2 ignores GIT_CONFIG_* env.
      environment.etc."gitconfig".text = ''
        [safe]
          directory = /srv/nixos-config
          directory = /srv/atlas
      '';

      # ── Flake-input auth (atlas) ───────────────────────────────────────
      # github:overtoneblue/atlas is public since 2026-09-28, so this
      # include is a no-op safety net kept for one reason: re-privatizing
      # the repo then works without a rebuild. A revoked or expired token
      # does not break public fetches (verified). The token is
      # sops-encrypted (secrets/head.yaml -> atlas-read-token) and rendered
      # by sops-nix to /run/secrets/rendered/nix-access-tokens (see
      # services/sops.nix). Missing/unreadable include targets are silently
      # skipped by nix, so activation/boot ordering is safe.
      nix.extraOptions = ''
        !include /run/secrets/rendered/nix-access-tokens
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
        self.packages.${pkgs.stdenv.hostPlatform.system}.atlas
        pkgs.claude-code
      ];

      # The tailnet's global resolver is the pihole; with accept-dns, head
      # sends every lookup there and loses all name resolution whenever the
      # pihole is down.
      services.tailscale.extraSetFlags = [ "--accept-dns=false" ];

      system.stateVersion = "26.05";
    };
}
