{ ... }:
{
  flake.nixosModules.headPi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      user = config.modules.system.username;
      repository = "/srv/nixos-config";
      stateDir = "/mnt/cache/appdata/pi";
      homeDir = "${stateDir}/home";
      agentDir = "${stateDir}/agent";
      tasksDir = "${stateDir}/tasks";
      tmuxDir = "${stateDir}/tmux";
      socketPath = "${tmuxDir}/pi.sock";

      # Store path, so the server reads exactly what git tracks.
      tmuxConf = ../../../../pi/tmux.conf;

      # Rendered by sops (see services/sops.nix).
      environmentFile = config.sops.templates."pi-env".path;

      # When a client targets a dead socket, most tmux commands (new-session,
      # attach, ...) silently start a fresh unsandboxed server in the caller's
      # context, which is a sandbox escape. `tmux ls` refuses with rc=1 and
      # spawns nothing, so it is the only safe liveness probe. Never reach
      # new-session/attach unless guard passes.
      tmuxShim = ''
        tmuxBin="${pkgs.tmux}/bin/tmux"
        sock="${socketPath}"
        tasks="${tasksDir}"

        # The socket is owner-only (overtoneblue).
        tmux_run() { "$tmuxBin" -S "$sock" "$@"; }

        guard() {
          local prog="$1" probe=""
          if ! systemctl is-active --quiet pi.service; then
            echo "$prog: pi.service is not active - refusing to touch $sock" >&2
            echo "$prog: (a tmux call on a dead socket would AUTO-SPAWN an unsandboxed server)" >&2
            exit 1
          fi
          if [[ ! -S "$sock" ]]; then
            echo "$prog: socket $sock missing although pi.service is active - refusing" >&2
            exit 1
          fi
          if ! probe="$(tmux_run ls 2>&1)"; then
            echo "$prog: pi tmux server not reachable on $sock [$probe] - refusing" >&2
            exit 1
          fi
        }
      '';

      # Runs inside a pi.service tmux pane. Writes the exit code to
      # tasks/<id>.status, which is what pi-task --wait polls for.
      piTaskRunner = pkgs.writeShellApplication {
        name = "pi-task-runner";
        runtimeInputs = with pkgs; [
          bashInteractive
          coreutils
          pi-coding-agent
        ];
        text = ''
          set -euo pipefail

          id=""
          if (( $# > 0 )); then
            id="$1"
          fi
          if [[ -z "$id" ]]; then
            echo "pi-task-runner: missing task id" >&2
            exit 2
          fi

          tasks="${tasksDir}"
          spec="$tasks/$id.spec"
          log="$tasks/$id.log"
          status="$tasks/$id.status"

          meta_get() {
            local k v
            [[ -f "$tasks/$id.meta" ]] || return 0
            while IFS='=' read -r k v; do
              if [[ "$k" == "$1" ]]; then
                printf '%s' "$v"
                return 0
              fi
            done < "$tasks/$id.meta"
            return 0
          }

          title="$(meta_get title)"
          model="$(meta_get model)"
          [[ -n "$title" ]] || title="$id"

          if [[ ! -f "$spec" ]]; then
            echo "pi-task-runner: spec file missing: $spec" >&2
            printf '127\n' > "$status"
            exit 127
          fi

          pi_args=( -p --name "$title" )
          if [[ -n "$model" ]]; then
            pi_args+=( --model "$model" )
          fi

          prompt="$(cat "$spec")"

          {
            printf '===== pi task %s =====\n' "$id"
            printf 'name=%s model=%s dir=%s\n' "$title" "''${model:-default}" "$PWD"
          } | tee "$log"

          set +e
          pi "''${pi_args[@]}" -- "$prompt" 2>&1 | tee -a "$log"
          rc="''${PIPESTATUS[0]}"
          set -e

          printf '%s\n' "$rc" > "$status"
          printf '===== exit=%s =====\n' "$rc" | tee -a "$log"
          exit "$rc"
        '';
      };

      piTask = pkgs.writeShellApplication {
        name = "pi-task";
        runtimeInputs = with pkgs; [
          bashInteractive
          coreutils
          systemd
        ];
        text = ''
          set -euo pipefail

          ${tmuxShim}

          usage() {
            cat <<'USAGE'
          usage: pi-task [--dir DIR] [--name TITLE] [--model MODEL] [--wait [--timeout SECS]] -- <spec text | @FILE>

          Dispatch a pi coding task as a session in the sandboxed pi tmux server
          (pi.service). Prints the task id, an attach command, and the log path.

            --dir DIR       working directory for the task (default: /srv/nixos-config)
            --name TITLE    session display name (default: the generated task id)
            --model MODEL   pi model pattern or ID (e.g. deepseek/deepseek-v4-flash)
            --wait          wait until the task finishes, print the last 50 log
                            lines, and exit with the task's exit code
            --timeout SECS  --wait timeout in seconds (default: 900)
            -h, --help      show this help

          The spec is the text after `--`, or a single `@FILE` token whose file
          contents are used as the spec. With no `--` at all, stdin is read
          when it is not a TTY.
          USAGE
          }

          missing() {
            echo "pi-task: $1 requires a value" >&2
            exit 2
          }

          dir="${repository}"
          name=""
          model=""
          do_wait="0"
          timeout_s="900"
          spec_args=()

          while (( $# > 0 )); do
            case "$1" in
              --dir)     [[ $# -ge 2 ]] || missing --dir;     dir="$2";       shift 2 ;;
              --name)    [[ $# -ge 2 ]] || missing --name;    name="$2";      shift 2 ;;
              --model)   [[ $# -ge 2 ]] || missing --model;   model="$2";     shift 2 ;;
              --wait)    do_wait="1"; shift ;;
              --timeout) [[ $# -ge 2 ]] || missing --timeout; timeout_s="$2"; shift 2 ;;
              -h|--help) usage; exit 0 ;;
              --)        shift; spec_args=("$@"); break ;;
              *)
                echo "pi-task: unknown argument: $1" >&2
                usage >&2
                exit 2
                ;;
            esac
          done

          if (( ''${#spec_args[@]} == 0 )); then
            if [[ ! -t 0 ]]; then
              spec="$(cat)"
            else
              echo "pi-task: no spec given (pass text after -- or a single @FILE token)" >&2
              exit 2
            fi
          elif (( ''${#spec_args[@]} == 1 )) && [[ "''${spec_args[0]}" == @* ]]; then
            spec_file="''${spec_args[0]#@}"
            [[ -f "$spec_file" ]] || { echo "pi-task: @FILE not found: $spec_file" >&2; exit 2; }
            spec="$(cat "$spec_file")"
          else
            spec="''${spec_args[*]}"
          fi
          [[ -n "$spec" ]] || { echo "pi-task: empty spec" >&2; exit 2; }
          [[ -d "$dir" ]] || { echo "pi-task: --dir does not exist: $dir" >&2; exit 2; }

          guard pi-task

          id="pi-$(date +%m%d-%H%M%S)-$(printf '%04x' "$RANDOM")"
          while [[ -e "$tasks/$id.spec" ]]; do
            id="pi-$(date +%m%d-%H%M%S)-$(printf '%04x' "$RANDOM")"
          done
          [[ -n "$name" ]] || name="$id"

          printf '%s\n' "$spec" > "$tasks/$id.spec"
          {
            printf 'title=%s\n' "$name"
            printf 'requester=%s\n' "$(id -un)"
            printf 'dir=%s\n' "$dir"
            printf 'model=%s\n' "$model"
            printf 'created=%s\n' "$(date -Is)"
          } > "$tasks/$id.meta"
          chmod 0640 "$tasks/$id.spec" "$tasks/$id.meta"

          if ! tmux_run new-session -d -s "$id" -c "$dir" "${piTaskRunner}/bin/pi-task-runner" "$id"; then
            rm -f "$tasks/$id.spec" "$tasks/$id.meta"
            echo "pi-task: failed to start tmux session $id" >&2
            exit 1
          fi

          echo "task:   $id"
          echo "attach: tmux -S ${socketPath} attach -t $id"
          echo "log:    $tasks/$id.log"

          if [[ "$do_wait" == "1" ]]; then
            [[ "$timeout_s" =~ ^[0-9]+$ ]] || { echo "pi-task: --timeout must be a non-negative integer" >&2; exit 2; }
            deadline=$(( SECONDS + timeout_s ))
            while [[ ! -f "$tasks/$id.status" ]]; do
              if (( SECONDS >= deadline )); then
                echo "pi-task: timed out after ''${timeout_s}s; task $id is still running" >&2
                tail -n 50 "$tasks/$id.log" 2>/dev/null >&2 || true
                exit 124
              fi
              sleep 2
            done
            echo "--- last 50 log lines for $id:"
            tail -n 50 "$tasks/$id.log" 2>/dev/null || true
            rc="$(cat "$tasks/$id.status")"
            [[ "$rc" =~ ^[0-9]+$ ]] || rc=1
            echo "pi-task: task $id finished with exit code $rc"
            exit "$rc"
          fi
        '';
      };

      piTasks = pkgs.writeShellApplication {
        name = "pi-tasks";
        runtimeInputs = with pkgs; [
          bashInteractive
          coreutils
          systemd
        ];
        text = ''
          set -euo pipefail

          ${tmuxShim}

          usage() {
            cat <<'USAGE'
          usage: pi-tasks [COMMAND]

          Browse and manage pi task sessions in the sandboxed pi tmux server.

            (no args)          interactive overview + pick-to-attach (needs a TTY)
            ls                 list sessions (id, title, age, status)
            attach [ID] [-r]   attach to ID (default: most recent); -r is read-only
            logs ID            show the last lines of a task log
            kill ID            kill one session (never the server)
          USAGE
          }

          meta_get() {
            local sid="$1" key="$2" k v
            if [[ -f "$tasks/$sid.meta" ]]; then
              while IFS='=' read -r k v; do
                if [[ "$k" == "$key" ]]; then
                  printf '%s' "$v"
                  return 0
                fi
              done < "$tasks/$sid.meta"
            fi
            return 0
          }

          age_of() {
            local ts="$1" d
            d=$(( $(date +%s) - ts ))
            if (( d < 60 )); then
              printf '%ds' "$d"
            elif (( d < 3600 )); then
              printf '%dm' "$(( d / 60 ))"
            elif (( d < 86400 )); then
              printf '%dh%02dm' "$(( d / 3600 ))" "$(( (d % 3600) / 60 ))"
            else
              printf '%dd%02dh' "$(( d / 86400 ))" "$(( (d % 86400) / 3600 ))"
            fi
          }

          validate_id() {
            [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "pi-tasks: invalid id: $1" >&2; exit 2; }
          }

          latest() {
            tmux_run list-sessions -F '#{session_created} #{session_name}' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2- || true
          }

          cmd_ls() {
            guard pi-tasks
            local out line sid created title age st rc
            out="$(tmux_run list-sessions -F '#{session_name}|#{session_created}' 2>/dev/null || true)"
            if [[ -z "$out" ]]; then
              echo "pi-tasks: no sessions"
              return 0
            fi
            printf '%-26s %-36s %-10s %s\n' "ID" "TITLE" "AGE" "STATUS"
            while IFS= read -r line; do
              [[ -n "$line" ]] || continue
              sid="''${line%%|*}"
              created="''${line#*|}"
              title="$(meta_get "$sid" title)"
              [[ -n "$title" ]] || title="-"
              age="$(age_of "$created")"
              if [[ -f "$tasks/$sid.status" ]]; then
                rc="$(cat "$tasks/$sid.status" 2>/dev/null || true)"
                st="done(rc=''${rc:-?})"
              else
                st="running"
              fi
              printf '%-26s %-36s %-10s %s\n' "$sid" "$title" "$age" "$st"
            done <<< "$out"
          }

          cmd_attach() {
            local sid="" ro="0"
            while (( $# > 0 )); do
              case "$1" in
                -r) ro="1"; shift ;;
                *)  sid="$1"; shift ;;
              esac
            done
            guard pi-tasks
            if [[ -z "$sid" ]]; then
              sid="$(latest)"
              if [[ -z "$sid" ]]; then
                echo "pi-tasks: no sessions to attach" >&2
                exit 1
              fi
            else
              validate_id "$sid"
            fi
            if ! tmux_run has-session -t "=$sid" 2>/dev/null; then
              echo "pi-tasks: session not found: $sid" >&2
              exit 1
            fi
            local -a att=(attach)
            if (( ro == 1 )); then
              att+=(-r)
            fi
            att+=(-t "$sid")
            tmux_run "''${att[@]}"
          }

          cmd_logs() {
            if (( $# == 0 )); then
              echo "pi-tasks: logs requires an ID" >&2
              exit 2
            fi
            local sid="$1"
            validate_id "$sid"
            if [[ ! -f "$tasks/$sid.log" ]]; then
              echo "pi-tasks: no log for $sid" >&2
              exit 1
            fi
            tail -n 100 "$tasks/$sid.log"
          }

          cmd_kill() {
            if (( $# == 0 )); then
              echo "pi-tasks: kill requires an ID" >&2
              exit 2
            fi
            local sid="$1"
            validate_id "$sid"
            guard pi-tasks
            if ! tmux_run kill-session -t "=$sid" 2>/dev/null; then
              echo "pi-tasks: no such session: $sid" >&2
              exit 1
            fi
            echo "pi-tasks: killed session $sid (server keeps running)"
          }

          cmd_menu() {
            guard pi-tasks
            local out line sid created title age pick n=0
            local -a ids=()
            out="$(tmux_run list-sessions -F '#{session_name}|#{session_created}' 2>/dev/null || true)"
            if [[ -z "$out" ]]; then
              echo "pi-tasks: no sessions"
              return 0
            fi
            while IFS= read -r line; do
              [[ -n "$line" ]] || continue
              sid="''${line%%|*}"
              created="''${line#*|}"
              title="$(meta_get "$sid" title)"
              [[ -n "$title" ]] || title="-"
              age="$(age_of "$created")"
              n=$(( n + 1 ))
              ids+=("$sid")
              printf '%2d) %-26s %-36s %s\n' "$n" "$sid" "$title" "$age"
            done <<< "$out"
            pick=""
            read -r -p "attach to # (empty cancels): " pick || true
            [[ -n "$pick" ]] || return 0
            [[ "$pick" =~ ^[0-9]+$ ]] || { echo "pi-tasks: not a number: $pick" >&2; exit 2; }
            if (( pick < 1 || pick > n )); then
              echo "pi-tasks: out of range" >&2
              exit 2
            fi
            tmux_run attach -t "=''${ids[$(( pick - 1 ))]}"
          }

          cmd=""
          if (( $# > 0 )); then
            cmd="$1"
            shift
          fi
          case "$cmd" in
            ls)        cmd_ls ;;
            attach)    cmd_attach "$@" ;;
            logs)      cmd_logs "$@" ;;
            kill)      cmd_kill "$@" ;;
            -h|--help) usage ;;
            "")
              if [[ -t 0 && -t 1 ]]; then
                cmd_menu
              else
                cmd_ls
              fi
              ;;
            *)
              echo "pi-tasks: unknown command: $cmd" >&2
              usage >&2
              exit 2
              ;;
          esac
        '';
      };

      piClient = pkgs.symlinkJoin {
        name = "pi-client";
        paths = [
          piTask
          piTasks
        ];
        meta.description = "pi delegation wrappers (pi-task, pi-tasks) for the sandboxed pi backend";
      };
    in
    {
      options.services.pi-client.package = lib.mkOption {
        type = lib.types.package;
        default = piClient;
        description = "pi delegation wrapper package (pi-task, pi-tasks).";
      };

      config = {
        # pi/settings.json and pi/models.json are overwritten on every
        # switch; the repo is the source of truth.
        # TODO: also install a pi/AGENTS.md once one exists in the repo.
        system.activationScripts."pi-config" = lib.stringAfter [ "users" ] ''
          install -d -o ${user} -g users -m 0750 ${stateDir} ${agentDir} ${agentDir}/extensions ${agentDir}/skills
          install -d -o ${user} -g users -m 0700 ${homeDir}
          install -d -o ${user} -g users -m 2770 ${tasksDir} ${tmuxDir}
          install -o ${user} -g users -m 0640 \
            ${../../../../pi/settings.json} \
            ${agentDir}/settings.json
          install -o ${user} -g users -m 0640 \
            ${../../../../pi/models.json} \
            ${agentDir}/models.json
        '';

        # The activation script creates these on first switch; tmpfiles
        # re-asserts modes and ownership at boot.
        systemd.tmpfiles.rules = [
          "z ${stateDir} 0750 ${user} users - -"
          "z ${homeDir} 0700 ${user} users - -"
          "z ${agentDir} 0750 ${user} users - -"
          "z ${tasksDir} 2770 ${user} users - -"
          "z ${tmuxDir} 2770 ${user} users - -"
        ];

        environment.systemPackages = [
          config.services.pi-client.package
          pkgs.pi-coding-agent
        ];

        systemd.services.pi = {
          description = "Pi persistent backend (tmux server for delegated pi tasks)";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          requires = [ "mnt-cache.mount" ];
          after = [
            "mnt-cache.mount"
            "network-online.target"
          ];

          # Also the PATH of every task pane.
          path = with pkgs; [
            bashInteractive
            coreutils
            fd
            git
            jq
            nix
            openssh
            ripgrep
            tmux
            pi-coding-agent
            findutils
            gnugrep
            gnused
          ];

          environment = {
            HOME = homeDir;
            PI_CODING_AGENT_DIR = agentDir;
            PI_OFFLINE = "1";
            PI_SKIP_VERSION_CHECK = "1";
            PI_TELEMETRY = "0";
          };

          unitConfig = {
            ConditionPathExists = environmentFile;
            RequiresMountsFor = [
              repository
              stateDir
            ];
          };

          serviceConfig = {
            User = user;
            Group = "users";
            WorkingDirectory = repository;
            EnvironmentFile = environmentFile;

            # -D keeps tmux in the foreground as the main process: a
            # daemonized server is killed as soon as its initial client
            # exits. -D also disables exit-empty, so the server survives with
            # zero sessions.
            ExecStart = "${pkgs.tmux}/bin/tmux -D -f ${tmuxConf} -S ${socketPath}";

            Restart = "always";
            RestartSec = "5s";
            TimeoutStopSec = "30s";
            UMask = "0007";

            # Same hardening as opencode.service.
            CapabilityBoundingSet = "";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            ReadWritePaths = [
              repository
              stateDir
            ];
            InaccessiblePaths = [
              # Leftover Hermes state (credentials) until it is archived.
              "-/mnt/cache/appdata/hermes-agent"
              "-/mnt/user"
              "-/mnt/disk1"
              "-/mnt/disk2"
              "-/mnt/disk3"
              "-/run/docker.sock"
              "-/var/run/docker.sock"
              "-/run/wrappers/bin/sudo"
            ];
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
          };
        };
      };
    };
}
