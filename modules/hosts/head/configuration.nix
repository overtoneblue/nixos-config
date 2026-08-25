{ self, ... }:
{
  flake.nixosModules.headConfiguration =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      # Passwordless single-command deployment wrapper. Root-owned (nix
      # store), fixed action, and user-supplied arguments are never
      # forwarded — sole action below.
      headRebuild = pkgs.writeShellScriptBin "head-rebuild" ''
        exec ${lib.getExe config.programs.nh.package} os switch \
          /srv/nixos-config#head \
          --elevation-strategy none \
          --bypass-root-check \
          --show-activation-logs
      '';

      # ── Desktop bridge ──────────────────────────────────────────────
      # `desktop <command...>` runs a command inside the node0 graphical
      # session via the dedicated desktop SSH identity. It SSHes
      # non-interactively to overtoneblue@node0 and executes the command
      # under `desktop-session`, which imports the live Wayland/DBus/
      # XDG/Hyprland session environment (see modules/features/hermes).
      #
      # Each argument is shell-quoted with bash %q so the remote zsh
      # reconstructs the exact argv (no word-splitting / injection).
      # Known_hosts entry is pinned to the overtoneblue user's file,
      # which holds the node0 ED25519 host key, so host verification
      # stays strict.
      desktop = pkgs.writeShellApplication {
        name = "desktop";
        runtimeInputs = [ pkgs.openssh ];
        text = ''
          set -euo pipefail

          if [[ $# -eq 0 ]]; then
            echo "usage: desktop <command...>" >&2
            exit 2
          fi

          remote=()
          arg=
          for arg in "$@"; do
            remote+=("$(printf '%q' "$arg")")
          done

          exec ${lib.getExe pkgs.openssh} \
            -i /home/overtoneblue/hermes-recovery/hermes-ssh/desktop_ed25519 \
            -o BatchMode=yes \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=yes \
            -o UserKnownHostsFile=/home/overtoneblue/.ssh/known_hosts \
            -o ConnectTimeout=15 \
            overtoneblue@node0 \
            desktop-session "''${remote[*]}"
        '';
      };
    in
    {
      imports = [
        self.nixosModules.options
        ./_system.nix
        self.nixosModules.headHardware
        self.nixosModules.headStorage
        self.nixosModules.headSops
        self.nixosModules.headHermes
        self.nixosModules.headOpenCode
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

      # ── Passwordless single-command deployment ────────────────────────
      # `sudo head-rebuild` rebuilds/switches the head flake.

      # Exactly this wrapper, NOPASSWD, as root only. No NOPASSWD: ALL.
      # The `""` restricts arguments further: sudo rejects any `head-rebuild
      # <arg>` invocation even before the wrapper ignores the arg.
      # Both trusted admins — overtoneblue (interactive TUI / NOLAN) and
      # hermes (gateway service user) — share this single-command grant.
      security.sudo.extraRules = [
        {
          users = [ "overtoneblue" "hermes" ];
          runAs = "root";
          commands = [
            {
              command = "${headRebuild}/bin/head-rebuild ''";
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

      environment.systemPackages = with pkgs; [
        headRebuild
        desktop
        tmux
        wget
        curl
        smartmontools
        xfsprogs
        mergerfs
      ];

      system.stateVersion = "26.05";
    };
}
