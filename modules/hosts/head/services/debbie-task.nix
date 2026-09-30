{ ... }:
{
  flake.nixosModules.headDebbieTask =
    {
      pkgs,
      lib,
      ...
    }:
    let
      # Detached worker: runs the courier, tees the log, records exit status,
      # and parses the courier's session id out of its summary block.
      debbieTaskRunner = pkgs.writeShellApplication {
        name = "debbie-task-runner";
        runtimeInputs = with pkgs; [
          coreutils
          gnused
          gnugrep
          util-linux
        ];
        text = ''
          set -euo pipefail
          id="''${1:?debbie-task-runner: id required}"
          tasks="''${HERMES_HOME:-$HOME/.hermes}/cache/debbie-tasks"
          spec="$tasks/$id.spec"
          log="$tasks/$id.log"
          meta="$tasks/$id.meta"
          provider="$(sed -n 's/^provider=//p' "$meta" | head -1)"
          model="$(sed -n 's/^model=//p' "$meta" | head -1)"
          dir="$(sed -n 's/^dir=//p' "$meta" | head -1)"
          cd "''${dir:-$HOME}"
          set +e
          hermes -p debbie chat -q "$(cat "$spec")" ''${provider:+--provider "$provider"} ''${model:+-m "$model"} >"$log" 2>&1
          rc=$?
          set -e
          printf '%s\n' "$rc" > "$tasks/$id.status"
          sid="$(sed -n 's/^Session:[[:space:]]*//p' "$log" | tail -1)"
          if [ -n "$sid" ]; then printf 'session=%s\n' "$sid" >> "$meta"; fi
          rm -f "$spec"
          exit "$rc"
        '';
      };

      # Dispatcher: debbie-task — background Debbie dispatch whose row shows up
      # in Atlas under the chat it was dispatched from (kind=debbie spawn item).
      debbieTask = pkgs.writeShellApplication {
        name = "debbie-task";
        runtimeInputs = with pkgs; [
          coreutils
          gnused
          gnugrep
          util-linux
        ];
        text = ''
          usage() {
            cat <<'EOF'
          usage: debbie-task [--title TITLE] [--provider P] [--model M] [--dir DIR] -- <spec | @FILE>

          Dispatch a Debbie (debbie profile) task in the background. The task
          appears in Atlas under the chat it was dispatched from.

            --title TITLE    display title (default: first line of the spec)
            --provider P     provider override (default: deepseek)
            --model M        model override (default: deepseek-v4-flash)
            --dir DIR        working directory (default: /srv/nixos-config)
          EOF
          }

          title="" provider="deepseek" model="deepseek-v4-flash" dir="/srv/nixos-config"
          while [ "$#" -gt 0 ]; do
            case "$1" in
              -h|--help) usage; exit 0 ;;
              --title) title="$2"; shift 2 ;;
              --provider) provider="$2"; shift 2 ;;
              --model) model="$2"; shift 2 ;;
              --dir) dir="$2"; shift 2 ;;
              --) shift; break ;;
              *) break ;;
            esac
          done
          if [ "$#" -eq 0 ]; then
            if [ ! -t 0 ]; then spec="$(cat)"; else usage; exit 2; fi
          elif [ "$#" -eq 1 ] && [ "''${1#@}" != "$1" ]; then
            specfile="''${1#@}"
            [ -f "$specfile" ] || { echo "debbie-task: @FILE not found: $specfile" >&2; exit 2; }
            spec="$(cat "$specfile")"
          else
            spec="$*"
          fi
          [ -n "$spec" ] || { echo "debbie-task: empty spec" >&2; exit 2; }
          [ -d "$dir" ] || { echo "debbie-task: --dir does not exist: $dir" >&2; exit 2; }
          if [ -z "$title" ]; then
            title="$(printf '%s' "$spec" | head -1 | cut -c1-72)"
          fi

          tasks="''${HERMES_HOME:-$HOME/.hermes}/cache/debbie-tasks"
          mkdir -p "$tasks"
          id="debb-$(date +%y%m%d-%H%M%S)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
          printf '%s' "$spec" > "$tasks/$id.spec"
          chmod 0640 "$tasks/$id.spec"
          {
            printf 'title=%s\n' "$title"
            if [ -n "''${HERMES_SESSION_ID:-}" ]; then printf 'parent_session=%s\n' "$HERMES_SESSION_ID"; fi
            if [ -n "''${HERMES_SESSION_CHAT_ID:-}" ]; then printf 'parent_chat=%s\n' "$HERMES_SESSION_CHAT_ID"; fi
            printf 'started=%s\n' "$(date +%s)"
            printf 'provider=%s\n' "$provider"
            printf 'model=%s\n' "$model"
            printf 'dir=%s\n' "$dir"
          } > "$tasks/$id.meta"
          chmod 0640 "$tasks/$id.meta"

          setsid nohup "${lib.getExe debbieTaskRunner}" "$id" >/dev/null 2>&1 &
          echo "debbie-task: $id dispatched (debbie · $provider · $model)"
          echo "  log:  $tasks/$id.log"
          echo "  meta: $tasks/$id.meta"
        '';
      };
    in
    {
      environment.systemPackages = [ debbieTask ];
    };
}
