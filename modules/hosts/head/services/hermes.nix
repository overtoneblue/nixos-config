{ inputs, ... }:
{
  flake.nixosModules.headHermes =
    { ... }:
    let
      stateDir = "/mnt/cache/appdata/hermes-agent";
    in
    {
      imports = [
        inputs.hermes-agent.nixosModules.default
      ];

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
      };

      systemd.services.hermes-agent = {
        requires = [ "mnt-cache.mount" ];
        after = [ "mnt-cache.mount" ];
      };
    };
}
