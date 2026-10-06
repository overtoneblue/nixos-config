{ ... }:
{
  # `<host>-rebuild [switch|boot|test]` — the one deploy path on every host.
  #
  # Run it with sudo. It re-launches itself as a transient systemd unit (named
  # after the command) and follows that unit's journal until it finishes, then
  # exits with the unit's exit code. The activation therefore runs under PID 1:
  # killing the caller (Ctrl-C, a gateway restart from the deploy itself) does
  # not interrupt it, and the unit name doubles as a lock against concurrent
  # deploys. A failed build never activates; there is no separate build gate.
  #
  # When webhookFile is set, start/finish/failure are posted to Discord.
  flake.nixosModules.rebuild =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.modules.system.rebuild;
      host = config.networking.hostName;
      flake = config.modules.system.flakePath;
      cmd = cfg.command;

      run = pkgs.writeShellApplication {
        name = "${cmd}-run";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          gawk
          gnugrep
          gnused
          git
          jq
          config.nix.package
          config.programs.nh.package
        ];
        text = ''
          mode="$1"
          # nh/activation need the full system profile (nix, systemctl, ...).
          export PATH="$PATH:/run/current-system/sw/bin"

          hook=${lib.escapeShellArg (if cfg.webhookFile == null then "" else cfg.webhookFile)}
          t0=$(date +%s)
          tmp=$(mktemp -d)
          trap 'rm -rf "$tmp"' EXIT

          notify() {
            if [ -z "$hook" ] || [ ! -r "$hook" ]; then return 0; fi
            jq -n --arg c "$1" --arg u ${lib.escapeShellArg host} \
              '{username: $u, content: $c, allowed_mentions: {parse: []}}' > "$tmp/msg.json"
            # URL goes in via curl's stdin config so it never shows up in argv.
            printf 'url = "%s"\n' "$(< "$hook")" |
              curl -K - -fsS -m 10 -H 'Content-Type: application/json' \
                --data-binary @"$tmp/msg.json" -o /dev/null || true
          }

          g() { git -c safe.directory='*' -C ${lib.escapeShellArg flake} "$@" 2>/dev/null; }
          rev="$(g rev-parse --abbrev-ref HEAD || echo '?')@$(g rev-parse --short HEAD || echo '?')"
          [ -z "$(g status --porcelain)" ] || rev="$rev+dirty"
          subject=$(g log -1 --format=%s | cut -c1-90 || true)

          old=$(readlink -f /run/current-system)
          notify "🔨 \`$mode\` started · \`$rev\` $subject · by ''${REBUILD_CALLER:-root}"

          set +e
          nh os "$mode" ${lib.escapeShellArg "${flake}#${host}"} \
            --elevation-strategy none \
            --bypass-root-check \
            --no-nom \
            --show-activation-logs 2>&1 | tee "$tmp/log"
          rc=''${PIPESTATUS[0]}
          set -e

          dt=$(( $(date +%s) - t0 ))
          if [ "$rc" -eq 0 ]; then
            gen=$(readlink /nix/var/nix/profiles/system | sed 's/^system-\(.*\)-link$/\1/')
            if [ "$mode" = boot ]; then
              new=$(readlink -f /nix/var/nix/profiles/system)
            else
              new=$(readlink -f /run/current-system)
            fi
            what="gen $gen · \`$(basename "$new" | cut -c1-8)\`"
            [ "$new" != "$old" ] || what="$what (no change)"
            notify "✅ \`$mode\` done in ''${dt}s · $what · \`$rev\`"
            echo "${cmd}: $mode OK in ''${dt}s ($what)"
          else
            tail=$(sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$tmp/log" | grep -v '^[[:space:]]*$' | tail -n 25 | tail -c 1400 || true)
            notify "❌ \`$mode\` FAILED (rc $rc) after ''${dt}s · \`$rev\`
          \`\`\`
          $tail
          \`\`\`
          full log: \`journalctl -u ${cmd}\`"
            echo "${cmd}: $mode FAILED rc=$rc after ''${dt}s" >&2
          fi
          exit "$rc"
        '';
      };

      rebuild = pkgs.writeShellApplication {
        name = cmd;
        runtimeInputs = [ pkgs.coreutils config.systemd.package ];
        text = ''
          usage() { echo "usage: sudo ${cmd} [switch|boot|test]" >&2; exit 64; }
          case "$#" in
            0) mode=switch ;;
            1) case "$1" in switch|boot|test) mode="$1" ;; *) usage ;; esac ;;
            *) usage ;;
          esac
          [ "$(id -u)" -eq 0 ] || { echo "${cmd}: needs root — run: sudo ${cmd} $mode" >&2; exit 77; }

          if systemctl is-active --quiet ${cmd}.service; then
            echo "${cmd}: a deploy is already running — follow: journalctl -fu ${cmd}" >&2
            exit 75
          fi

          journalctl -q -f -n0 -o cat -u ${cmd}.service &
          follow=$!
          trap 'kill "$follow" 2>/dev/null || true' EXIT

          rc=0
          systemd-run --unit=${cmd} --collect --quiet --wait \
            -p Type=oneshot -p TimeoutStartSec=3600 \
            --setenv=SUDO_UID="''${SUDO_UID:-}" \
            --setenv=REBUILD_CALLER="''${SUDO_USER:-root}" \
            ${lib.getExe run} "$mode" || rc=$?
          sleep 0.3 # let journald flush the tail before the follower dies
          exit "$rc"
        '';
      };
    in
    {
      options.modules.system.rebuild = {
        command = lib.mkOption {
          type = lib.types.str;
          default = "${host}-rebuild";
          description = "Name of the deploy command (and of its transient unit).";
        };
        webhookFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Root-readable file holding a Discord webhook URL for build notifications.";
        };
      };

      config = {
        environment.systemPackages = [ rebuild ];
        system.build.rebuild = rebuild;

        # Passwordless for the primary user, exactly these argument lists.
        # sudo matches the invoked path, so pin the stable profile path rather
        # than a store path. In sudoers, "" means "no arguments".
        security.sudo.extraRules = [
          {
            users = [ config.modules.system.username ];
            runAs = "root";
            commands =
              map
                (args: {
                  command = "/run/current-system/sw/bin/${cmd} ${args}";
                  options = [ "NOPASSWD" ];
                })
                [
                  "\"\""
                  "switch"
                  "boot"
                  "test"
                ];
          }
        ];
      };
    };
}
