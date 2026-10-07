{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Hermes plugin: Discord server mirror for Hermes desktop (two-way), see
      # packages/hermes-discord-mirror. Pure source — Hermes imports it as-is:
      # head links it into $HERMES_HOME/plugins, node0 installs desktop/plugin.js.
      packages.hermes-discord-mirror = pkgs.runCommand "hermes-discord-mirror-0.1.0" { } ''
        cp -r ${../../packages/hermes-discord-mirror} $out
      '';
    };
}
