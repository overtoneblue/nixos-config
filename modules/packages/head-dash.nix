{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Terminal dashboard for head. See packages/head-dash/README.md.
      packages.head-dash =
        pkgs.buildGoModule rec {
          pname = "head-dash";
          version = "0.2.5";
          src = ../../packages/head-dash;

          vendorHash = "sha256-6RHkrNtHi7+ibgAGdKENcUE79N9FoOMw14c+qcS7Lac=";

          # The usage page shells out to sqlite3 (no Go SQLite driver, see
          # README), which isn't on head's global PATH.
          nativeBuildInputs = [ pkgs.makeWrapper ];
          postInstall = ''
            wrapProgram $out/bin/head-dash \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.sqlite ]}
          '';

          meta.mainProgram = "head-dash";
        };
    };
}
