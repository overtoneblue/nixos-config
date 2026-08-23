{ inputs, ... }:
{
  flake.nixosModules.headHermes =
    { config, lib, pkgs, ... }:
    let
      stateDir = "/mnt/cache/appdata/hermes-agent";
      username = config.modules.system.username;
    in
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      # ── Trusted admins / shared state access ─────────────────────────
      # overtoneblue gets the hermes group so plain `hermes` commands share
      # the recovered state (2770 hermes:hermes) without sudo -u hermes.
      # hermes (the interactive account, not the service sandbox) is a full
      # administrator: wheel + the shared admin group for /srv/nixos-config.
      users.users.${username}.extraGroups = [ "hermes" ];
      users.users.hermes.extraGroups = [
        "wheel"
        "admin"
      ];

      # Resolve plain `hermes` to the recovered state explicitly for every
      # interactive overtoneblue session (addToSystemPackages already exports
      # this system-wide; kept here as the authoritative declaration).
      environment.variables.HERMES_HOME = "${stateDir}/.hermes";

      services.hermes-agent = {
        enable = true;
        inherit stateDir;
        workingDirectory = "${stateDir}/.hermes/workspace";
        addToSystemPackages = true;

        environmentFiles = [
          "${stateDir}/secrets.env"
        ];

        environment = {
          API_SERVER_ENABLED = "false";
          API_SERVER_HOST = "127.0.0.1";
          HERMES_DASHBOARD = "true";
          HERMES_DASHBOARD_HOST = "127.0.0.1";
          HERMES_DASHBOARD_TUI = "1";
          HERMES_DISABLE_LAZY_INSTALLS = "1";
        };

        extraArgs = [
          "run"
          "--replace"
        ];

        settings = {
          mcp_servers.computer-use-linux.enabled = false;
          terminal.backend = "local";
        };

        # OpenCode client wrapper — the gateway (User=hermes) must be able to
        # invoke it against the persistent backend (it holds the NOPASSWD
        # head-rebuild grant, so it is also the deploy identity). Sourced env
        # file is group-readable via opencode.nix tmpfiles.
        extraPackages = [ config.services.opencode-client.package ];
      };

      # ── Media read-only guardrail (service sandbox only) ─────────────
      # ProtectSystem=strict already leaves /mnt/disk* and /mnt/user
      # read-only (the only read-write paths are stateDir/workingDirectory);
      # these ReadOnlyPaths make the guardrail explicit and binding.
      systemd.services.hermes-agent = {
        requires = [ "mnt-cache.mount" ];
        after = [ "mnt-cache.mount" ];

        serviceConfig.ReadOnlyPaths = [
          "/mnt/disk1"
          "/mnt/disk2"
          "/mnt/disk3"
          "/mnt/user"
        ];
      };

      # ── Shared Hermes credential store permissions ────────────────────
      # The gateway (User=hermes, UMask=0007) and overtoneblue share one
      # credential store. The agent opens auth.lock with "a+", so both the
      # store and its cross-process lock must be group-writable. We keep the
      # .hermes tree setgid/group-writable and install default ACLs so files
      # created by either party — regardless of the creator's umask — stay
      # usable by the other. Nothing becomes world-readable/writable.
      systemd.tmpfiles.rules = [
        "f ${stateDir}/.hermes/auth.json 0660 hermes hermes - -"
        "f ${stateDir}/.hermes/auth.lock 0660 hermes hermes - -"
      ];

      system.activationScripts."hermes-shared-state" = lib.stringAfter [
        "hermes-agent-setup"
      ] ''
        # Reassert setgid + group-write AND group-execute on every shared dir
        # (post-migration, recovered dirs may still be owner-only or missing
        # group-x — without it subdirs like skills/ are not traversable).
        # NB: `g+rws` produces `rwS` (no execute); must be `g+rwxs`.
        find ${stateDir}/.hermes -type d -exec chmod g+rwxs {} +

        # Default ACLs: whichever user/umask creates a file in the shared
        # tree, the hermes group gets rwx-equivalent access and the world
        # gets nothing.
        find ${stateDir}/.hermes -type d \
          -exec ${pkgs.acl}/bin/setfacl -d -m u:hermes:rwx -m g:hermes:rwx -m o::--- {} +

        # Credential store + cross-process lock: group rw (both users must
        # be able to read AND update), never owner-only, never 0640.
        touch ${stateDir}/.hermes/auth.lock
        chown hermes:hermes \
          ${stateDir}/.hermes/auth.json \
          ${stateDir}/.hermes/auth.lock 2>/dev/null || true
        chmod 0660 \
          ${stateDir}/.hermes/auth.json \
          ${stateDir}/.hermes/auth.lock 2>/dev/null || true
      '';
    };
}
