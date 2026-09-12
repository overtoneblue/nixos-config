{ self, ... }:
# Self-hosted Matrix homeserver on head: Synapse (native NixOS service) +
# PostgreSQL, public at matrix.cenunix.dev, identity suffix @user:cenunix.dev.
#
# Scope: homeserver only — no bridges, no TURN, no metrics, no extra
# listeners. Hermes bot accounts/profiles are a separate later phase; this
# module must never touch hermes-agent/hermes-serve.
#
# Registration: public registration stays disabled; accounts are created with
# the registration shared secret (matrix-synapse-register_new_matrix_user).
# The secret value never enters the nix store — it lives sops-encrypted in
# secrets/head-matrix.yaml and is rendered at activation. Synapse receives it
# via a rendered config fragment (`registration_shared_secret: ...`) included
# through extraConfigFiles — the pattern the pinned nixpkgs module docs
# prescribe for secret-manager-deployed files (nixos/modules/services/matrix/
# synapse.md, "Registering Matrix users").
{
  flake.nixosModules.headMatrix =
    { config, ... }:
    {
      # ── Registration shared secret (sops) ──────────────────────────────
      # Raw value -> /run/secrets/matrix-registration-shared-secret, 0400,
      # owned by the synapse service user. The sops render dir is root-only,
      # so the file must be matrix-synapse-scoped for the service to read it.
      # restartUnits targets ONLY the synapse unit — never
      # hermes-agent/hermes-serve.
      sops.secrets."matrix-registration-shared-secret" = {
        sopsFile = "/srv/nixos-config/secrets/head-matrix.yaml";
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0400";
        restartUnits = [ "matrix-synapse.service" ];
      };

      # Rendered config fragment consumed via extraConfigFiles below; the
      # placeholder is substituted by sops-install-secrets at activation.
      sops.templates."synapse-registration-secret.yaml" = {
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0400";
        content = "registration_shared_secret: ${config.sops.placeholder."matrix-registration-shared-secret"}\n";
      };

      # ── Synapse homeserver ─────────────────────────────────────────────
      services.matrix-synapse = {
        enable = true;
        settings = {
          server_name = "cenunix.dev";
          public_baseurl = "https://matrix.cenunix.dev";
          # Accounts are created only via the registration shared secret.
          enable_registration = false;

          # Single local listener behind nginx (see nginx-proxy.nix); pinned
          # to the module's own default shape. Loopback only — public traffic
          # arrives via the matrix.cenunix.dev vhost.
          listeners = [
            {
              port = 8008;
              bind_addresses = [ "127.0.0.1" ];
              type = "http";
              tls = false;
              x_forwarded = true;
              resources = [
                {
                  names = [ "client" ];
                  compress = true;
                }
                {
                  names = [ "federation" ];
                  compress = false;
                }
              ];
            }
          ];

          database = {
            name = "psycopg2";
            args = {
              database = "matrix-synapse";
              user = "matrix-synapse";
              # `host` intentionally omitted: the pinned nixpkgs libpq/postgres
              # socketdir patch defaults the unix socket to /run/postgresql for
              # both server and client, and omitting it keeps the module's
              # hasLocalPostgresDB ordering (after/requires postgresql.target).
            };
          };
        };

        # Synapse reads the sops-rendered registration secret fragment as an
        # extra config file (merged after homeserver.yaml).
        extraConfigFiles = [ config.sops.templates."synapse-registration-secret.yaml".path ];
      };

      # ── PostgreSQL (first host-native instance on head) ────────────────
      # nextcloud's postgres is a Docker container (cenunet) — unaffected.
      # Default dataDir (/var/lib/postgresql) = root SSD; nothing under /mnt.
      # Peer auth on the local unix socket maps OS user matrix-synapse to the
      # DB role of the same name — no TCP, no password secret.
      services.postgresql = {
        enable = true;
        ensureDatabases = [ "matrix-synapse" ];
        ensureUsers = [
          {
            name = "matrix-synapse";
            ensureDBOwnership = true;
          }
        ];
      };
    };
}
