{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # head-dash: terminal dashboard for the head NixOS server (Bubble Tea +
      # lipgloss). See packages/head-dash/README.md.
      packages.head-dash =
        pkgs.buildGoModule rec {
          pname = "head-dash";
          version = "0.1.0";
          src = ../../packages/head-dash;

          vendorHash = "sha256-6RHkrNtHi7+ibgAGdKENcUE79N9FoOMw14c+qcS7Lac=";

          meta.mainProgram = "head-dash";
        };
    };
}
