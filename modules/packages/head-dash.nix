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
          version = "0.2.0";
          src = ../../packages/head-dash;

          vendorHash = "sha256-6RHkrNtHi7+ibgAGdKENcUE79N9FoOMw14c+qcS7Lac=";

          # The usage page shells out to `sqlite3 -readonly -json` against the
          # Hermes and OpenCode state databases (deliberately no Go SQLite
          # driver — see README). head's global PATH does not carry sqlite3,
          # so the wrapper anchors it into the binary's own PATH.
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postInstall = ''
            wrapProgram $out/bin/head-dash \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.sqlite ]}
          '';

          meta.mainProgram = "head-dash";
        };
    };
}
