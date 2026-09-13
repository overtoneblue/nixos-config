{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # atlas: keyboard-driven workstream TUI for Hermes. The source repo and
      # package definition live in /srv/atlas (consumed as the `atlas` flake
      # input); this module only re-exports its package as
      # self.packages.<system>.atlas so hosts can install it.
      packages.atlas = inputs.atlas.packages.${system}.default;
    };
}
