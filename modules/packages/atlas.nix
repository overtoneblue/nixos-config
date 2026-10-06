{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # atlas: keyboard-driven workstream client for Hermes. The source repo
      # and package definitions live in the `atlas` flake input
      # (github:overtoneblue/atlas); this module only re-exports its packages
      # so hosts can install them:
      #   atlas          — TUI + atlasd (head)
      #   atlas-electron — Electron desktop app + atlasd + web UI + entry
      #                    (node0)
      packages.atlas = inputs.atlas.packages.${system}.default;
      packages.atlas-electron = inputs.atlas.packages.${system}.atlas-electron;
    };
}
