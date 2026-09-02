{ inputs, ... }:
{
  flake.nixosModules.headHermes =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      stateDir = "/mnt/cache/appdata/hermes-agent";
      username = config.modules.system.username;
    in
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

      # Hermes's agent-browser backend (local spawning and CDP attach) invokes
      # upstream dynamically-linked binaries. NixOS's default stub loader
      # rejects them before Hermes can use its accessibility-tree browser API.
      # This mirrors the known-good node0 runtime set without adding a display
      # manager, browser service, or network listener to head.
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

          libx11
          libxext
          libxrender
          libxrandr
          libxi
          libxtst
          libxfixes
          libxcursor
          libxinerama
          libxcb
        ];
      };

      # ── Trusted admins / shared state access ─────────────────────────
      # overtoneblue gets the hermes group so plain `hermes` commands share
      # the recovered state (2770 hermes:hermes) without sudo -u hermes.
      # hermes keeps the shared admin group (rwx on /srv/nixos-config) and
      # the single-command head-rebuild sudo grant, but is NOT in wheel: that
      # keeps it out of @wheel in nix.settings.trusted-users, so it can build
      # (allowed-users, see configuration.nix) without root-equivalent Nix
      # trust. Generic sudo remains unauthorized; NoNewPrivileges is disabled
      # below only so the exact NOPASSWD head-rebuild rule can function.
      users.users.${username}.extraGroups = [ "hermes" ];
      users.users.hermes.extraGroups = [
        "admin"
        "systemd-journal"
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

        # Secrets come from the sops-rendered template (see services/sops.nix).
        # The upstream hermes-agent activation script merges this file into
        # ${stateDir}/.hermes/.env at activation, so hermes reads the merged
        # .env at startup — the template path is only read by that script.
        environmentFiles = [
          config.sops.templates."hermes-env".path
        ];

        environment = {
          API_SERVER_ENABLED = "false";
          API_SERVER_HOST = "127.0.0.1";
          HERMES_DASHBOARD = "true";
          HERMES_DASHBOARD_HOST = "127.0.0.1";
          HERMES_DASHBOARD_TUI = "1";
          HERMES_DISABLE_LAZY_INSTALLS = "1";
          # Non-secret gateway access-control config (user/channel IDs), not
          # credentials — kept out of the sops secret store. Previously these
          # rode along in the hand-maintained secrets.env; preserved here so
          # message routing / allow-lists are unchanged.
          TELEGRAM_ALLOWED_USERS = "7130533486";
          TELEGRAM_HOME_CHANNEL = "7130533486";
          DISCORD_ALLOWED_USERS = "950769259301199922";
        };

        extraArgs = [
          "run"
          "--replace"
        ];

        settings = {
          # ── Declarative model/provider (Makora) ────────────────────────
          # Actual credentials stay in ${stateDir}/.hermes/.env via sops
          # (environmentFiles); these api_key values are env-var *references*
          # Hermes resolves at runtime — never inline secrets.
          model = {
            default = "deepseek/deepseek-v4-pro-0813";
            provider = "openrouter";
          };
          # Load the user-space hermes-stats telemetry plugin. Enabled plugins
          # must come from config here: HERMES_MANAGED installs reject
          # `hermes plugins enable` (cannot write config.yaml).
          plugins = {
            enabled = [ "hermes-stats" ];
          };
          auxiliary.vision = {
            provider = "custom";
            model = "gemma-4-31b";
            reasoning_effort = "";
            base_url = "https://api.cerebras.ai/v1";
            api_key = "\${HERMES_AUXILIARY_VISION_API_KEY}";
          };
          custom_providers = [
            {
              name = "Makora";
              base_url = "https://inference.makora.com/v1";
              key_env = "HERMES_CUSTOM_INFERENCE_MAKORA_COM_API_KEY";
              model = "deepseek-ai/DeepSeek-V4-Flash";
              api_mode = "chat_completions";
              models = [
                "deepseek-ai/DeepSeek-V4-Flash"
                "google/gemma-4-26B-A4B"
                "moonshotai/Kimi-K3"
                "zai-org/GLM-5.2-FP8"
                "zai-org/GLM-5.2-NVFP4"
              ];
            }
            {
              name = "FriendliAI";
              base_url = "https://api.friendli.ai/serverless/v1";
              key_env = "FRIENDLI_API_KEY";
              model = "zai-org/GLM-5.2";
              api_mode = "chat_completions";
              models = [
                "zai-org/GLM-5.2"
                "zai-org/GLM-5.3-Flash"
                "deepseek-ai/DeepSeek-V3.2"
                "google/gemma-4-31B-it"
                "MiniMaxAI/MiniMax-M2.5"
              ];
            }
            {
              name = "Databricks";
              base_url = "https://dbc-791cecb8-44a5.cloud.databricks.com/serving-endpoints";
              key_env = "HERMES_DATABRICKS_API_KEY";
              model = "databricks-glm-5-3-flash";
              api_mode = "chat_completions";
              models = [
                "databricks-glm-5-3-flash"
              ];
            }
          ];
          # Direct alias so `/model friendli` resolves to FriendliAI's GLM-5.2
          # from any surface (TUI, Telegram, gateway). provider=custom routes
          # through the OpenAI-compatible custom profile; the matching
          # custom_providers entry supplies base_url + FRIENDLI_API_KEY.
          model_aliases = {
            friendli = {
              model = "zai-org/GLM-5.2";
              provider = "custom";
              base_url = "https://api.friendli.ai/serverless/v1";
            };
            databricks = {
              model = "databricks-glm-5-3-flash";
              provider = "custom";
              base_url = "https://dbc-791cecb8-44a5.cloud.databricks.com/serving-endpoints";
            };
          };
          mcp_servers.computer-use-linux.enabled = true;
          # Route through the Nix-managed `desktop` bridge (head-side wrapper
          # that SSHes to node0 and execs `desktop-session computer-use-linux
          # mcp` in the graphical session). `desktop` resolves on the
          # interactive TUI PATH; the always-on gateway (User=hermes) does not
          # yet have access to the desktop SSH identity — known limitation.
          mcp_servers.computer-use-linux.command = "desktop";
          terminal.backend = "local";
          browser.cdp_url = "http://127.0.0.1:9222";

          # Write-approval guardrails: skills and memory writes require
          # explicit approval rather than being applied automatically.
          memory.write_approval = true;
          skills.write_approval = true;

          # Default reasoning effort for every session start.
          agent.reasoning_effort = "max";

          # Pre-stage multi-profile Telegram routing; no behavior change
          # until tokens and routes are configured.
          gateway.multiplex_profiles = true;
        };

        # Runtime PATH for the gateway: the OpenCode client wrapper plus the
        # NixOS inspection/build/debug toolchain. `nh os build` (unprivileged,
        # via the Nix daemon — hermes is in allowed-users but not trusted) is
        # the validation path; `sudo head-rebuild` (nh os switch as root, see
        # configuration.nix) is the separate deploy path. systemd is declared
        # here explicitly so systemctl/journalctl do not depend on
        # hermes-agent's own propagated inputs.
        extraPackages = [
          config.services.opencode-client.package
          config.modules.system.desktopCommand
          config.programs.nh.package
          pkgs.nix
          pkgs.git
          pkgs.nix-output-monitor
          pkgs.systemd
        ];
      };

      # ── Media read-only guardrail (service sandbox only) ─────────────
      # ProtectSystem=strict already leaves /mnt/disk* and /mnt/user
      # read-only (the only read-write paths are stateDir/workingDirectory);
      # these ReadOnlyPaths make the guardrail explicit and binding.
      systemd.services.hermes-agent = {
        requires = [ "mnt-cache.mount" ];
        after = [ "mnt-cache.mount" ];

        # nh defaults for the gateway: the canonical flake so a bare
        # `nh os build` validates head, and activation logs surfaced for
        # debugging. These merge with the upstream commonUnitEnvironment
        # (HOME, HERMES_HOME, HERMES_MANAGED); they do not relax the sandbox.
        environment = {
          NH_OS_FLAKE = "/srv/nixos-config";
          NH_FLAKE = "/srv/nixos-config";
          NH_SHOW_ACTIVATION_LOGS = "1";

          # Desktop bridge identity for the SERVICE context: route the shared
          # `desktop` wrapper to the sops-rendered hermes-owned SSH key and the
          # declarative system known_hosts, so computer-use / desktop commands
          # spawned by the gateway (User=hermes) reach node0 exactly like the
          # interactive TUI does. No /home/overtoneblue access is implied.
          DESKTOP_SSH_KEY = config.sops.secrets."hermes-desktop-key".path;
          DESKTOP_KNOWN_HOSTS = "/etc/ssh/ssh_known_hosts";
        };

        # Make NixOS security wrappers resolvable so the
        # gateway (User=hermes) can invoke the single NOPASSWD grant
        # `sudo head-rebuild`. systemd generates Environment=PATH from
        # `path` (systemd-lib.nix), and `path` accepts strings; a "/run/wrappers"
        # element expands to /run/wrappers/bin via makeBinPath. This list
        # MERGES with the upstream `path = unitPath` (processPath), so the
        # toolchain above is preserved.
        path = [ "/run/wrappers" ];

        serviceConfig = {
          # REQUIRED for `sudo head-rebuild` to work from the service runtime:
          # the upstream commonServiceConfig sets NoNewPrivileges=true, which
          # blocks all setuid exec — sudo cannot acquire root even with a
          # NOPASSWD grant (live: `setpriv --no-new-privs sudo -n -l` fails).
          # We override it to false so the setuid sudo wrapper can run.
          # sudoers stays the authorization boundary: only the exact
          # `${headRebuild}/bin/head-rebuild ''` command is NOPASSWD (see
          # configuration.nix); every other sudo call needs a password the
          # noninteractive service does not hold. No generic sudo nh / ALL.
          # CONSEQUENCE: a process spawned by the agent can now execute the
          # host's configured setuid/setgid wrappers; sudoers governs sudo,
          # while each other wrapper retains its own authentication/policy.
          # The real escalation surface is the *design*: hermes has
          # admin-group rwx on /srv/nixos-config and the head-rebuild grant,
          # so it can edit the flake and deploy it as root. That capability is
          # the requested one (Nolan deploys through the gateway) and
          # pre-dates this change; it was strictly riskier before (hermes was
          # also wheel + Nix-trusted).
          # sudo relies on the setuid wrapper for escalation, so
          # NoNewPrivileges must stay off. sudoers (hermes ALL=(ALL)
          # NOPASSWD: ALL) is the authorization boundary for that escalation.
          NoNewPrivileges = lib.mkForce false;

          # Broad system administration: drop ProtectSystem=strict. A strict
          # read-only namespace is inherited by every sudo'd root command
          # (even a successful sudo gets a read-only filesystem), which
          # breaks normal host administration. The service and its sudo
          # children now see the real (read-write) filesystem.
          ProtectSystem = lib.mkForce false;

          # Media-data write protection (separate, explicit): /mnt/disk1-3
          # and /mnt/user are mounted read-only in the service namespace by
          # default, independent of ProtectSystem. Caden must explicitly
          # authorize a media operation to change this. Nothing else is
          # pinned read-only.
          ReadOnlyPaths = [
            "/mnt/disk1"
            "/mnt/disk2"
            "/mnt/disk3"
            "/mnt/user"
          ];
        };
      };

      # ── Hermes Desktop backend (`hermes serve`) ───────────────────────
      # The Hermes Desktop app on node0 connects to this JSON-RPC/WebSocket
      # backend instead of spawning its own agent runtime. It shares the
      # gateway's stateDir/HERMES_HOME, so it IS the same head session —
      # same sessions, skills, memory, credentials, and config.yaml. The
      # serve subcommand is headless (no web UI build), so this is a lean
      # always-on unit. Bind is loopback-only; node0 reaches it through the
      # hermes-desktop-tunnel (SSH -L 127.0.0.1:9119) — no firewall change,
      # no LAN exposure.
      systemd.services.hermes-serve = {
        description = "Hermes Agent Desktop backend (serve)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "mnt-cache.mount" ];
        wants = [ "network-online.target" ];
        requires = [ "mnt-cache.mount" ];

        environment = {
          HOME = stateDir;
          HERMES_HOME = "${stateDir}/.hermes";
          HERMES_MANAGED = "true";

          # Same toolchain env as the gateway so the desktop-spawned agent
          # has identical capabilities (deploy, desktop bridge, git, nh).
          NH_OS_FLAKE = "/srv/nixos-config";
          NH_FLAKE = "/srv/nixos-config";
          NH_SHOW_ACTIVATION_LOGS = "1";
          DESKTOP_SSH_KEY = config.sops.secrets."hermes-desktop-key".path;
          DESKTOP_KNOWN_HOSTS = "/etc/ssh/ssh_known_hosts";
        };

        serviceConfig = {
          User = "hermes";
          Group = "hermes";
          WorkingDirectory = "${stateDir}/.hermes/workspace";

          ExecStart = "${config.services.hermes-agent.package}/bin/hermes serve --host 127.0.0.1 --port 9119";

          Restart = "always";
          RestartSec = 5;

          # Shared-state: group-writable like the gateway.
          UMask = "0007";

          # Same service hardening posture as the gateway: sudo head-rebuild
          # needs NoNewPrivileges off; host admin needs ProtectSystem off;
          # media mounts stay read-only.
          NoNewPrivileges = lib.mkForce false;
          ProtectSystem = lib.mkForce false;
          ReadOnlyPaths = [
            "/mnt/disk1"
            "/mnt/disk2"
            "/mnt/disk3"
            "/mnt/user"
          ];
        };

        # Make NixOS security wrappers resolvable (sudo head-rebuild) and
        # keep the same runtime PATH shape as the gateway unit.
        path = [ "/run/wrappers" ];
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

      system.activationScripts."hermes-shared-state" =
        lib.stringAfter
          [
            "hermes-agent-setup"
          ]
          ''
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

            # Shared skill files: enforce group rw + world denied. The agent
            # creates these at runtime
            # with mode 0600, which defeats the directory default ACLs above —
            # the create mode masks the inherited group entry to nothing, so
            # files like skills/nixos-flake-maintenance/SKILL.md end up owner-only
            # despite the ACLs. Scope the repair to skills so unrelated runtime
            # state and credentials retain their intentional modes.
            find ${stateDir}/.hermes/skills -type f \
              -exec chmod g+rw,o-rwx {} + 2>/dev/null || true

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
