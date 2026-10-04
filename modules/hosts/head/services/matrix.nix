{ self, ... }:
# Synapse + PostgreSQL, public at matrix.cenunix.dev, users @user:cenunix.dev.
#
# Public registration is off; create accounts with
# matrix-synapse-register_new_matrix_user and the registration shared secret,
# which reaches Synapse as a sops-rendered extraConfigFiles fragment so it
# never enters the store.
{
  flake.nixosModules.headMatrix =
    { config, ... }:
    {
      sops.secrets."matrix-registration-shared-secret" = {
        sopsFile = "/srv/nixos-config/secrets/head-matrix.yaml";
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0400";
        restartUnits = [ "matrix-synapse.service" ];
      };

      sops.templates."synapse-registration-secret.yaml" = {
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0400";
        content = "registration_shared_secret: ${config.sops.placeholder."matrix-registration-shared-secret"}\n";
      };

      services.matrix-synapse = {
        enable = true;
        settings = {
          server_name = "cenunix.dev";
          public_baseurl = "https://matrix.cenunix.dev";
          enable_registration = false;

          # Loopback only, behind nginx (see nginx-proxy.nix).
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
              # No `host`: the default unix socket keeps the module's
              # hasLocalPostgresDB ordering on postgresql.target.
            };
          };
        };

        extraConfigFiles = [ config.sops.templates."synapse-registration-secret.yaml".path ];
      };

      # Peer auth over the unix socket; no TCP and no DB password.
      # Nextcloud's postgres is a separate Docker container.
      services.postgresql = {
        enable = true;
        # Synapse refuses any collation but C, and ensureDatabases can't set
        # one, so initialise the whole cluster with it. Only affects a fresh
        # cluster.
        initdbArgs = [ "--locale=C" "--encoding=UTF8" ];
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
