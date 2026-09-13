{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # atlas: keyboard-driven workstream TUI for Hermes (Bubble Tea + lipgloss).
      # See packages/atlas/README.md.
      packages.atlas =
        pkgs.buildGoModule rec {
          pname = "atlas";
          version = "0.0.1";
          src = ../../packages/atlas;

          vendorHash = "sha256-uwBJAqN4sIepiiJf9lCDumLqfKJEowQO2tOiSWD3Fig=";

          meta.mainProgram = "atlas";
        };
    };
}
