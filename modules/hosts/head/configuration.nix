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
        exec ${config.system.build.nixos-rebuild}/bin/nixos-rebuild \
          switch --flake /srv/nixos-config#head
      '';
    in
    {
      imports = [
        self.nixosModules.options
        ./_system.nix
        self.nixosModules.headHardware
        self.nixosModules.headStorage
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
      security.sudo.extraRules = [
        {
          users = [ "hermes" ];
          runAs = "root";
          commands = [
            {
              command = "${headRebuild}/bin/head-rebuild ''";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      virtualisation.docker.enable = true;

      environment.systemPackages = with pkgs; [
        headRebuild
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
