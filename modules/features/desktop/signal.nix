{ self, ... }:
{
  flake.nixosModules.signal =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = [
        self.packages.${pkgs.stdenv.hostPlatform.system}.mySignal
      ];
    };

  perSystem =
    { pkgs, config, ... }:
    let
      colors = config.myTheme.colors;

      signalCss = pkgs.writeText "signal-theme.css" ''
        .dark-theme .NavTabs,
        .dark-theme .NavSidebar {
          background-color: #0b0e14 !important;
        }
      '';
    in
    {
      packages.mySignal = pkgs.signal-desktop.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.asar ];

        postInstall = (old.postInstall or "") + ''
          set -euo pipefail

          echo "Patching packaged Signal app.asar..."

          tmp="$(mktemp -d)"
          appdir="$tmp/app"

          cp "$out/share/signal-desktop/app.asar" "$tmp/app.asar"
          if [ -d "$out/share/signal-desktop/app.asar.unpacked" ]; then
            cp -r "$out/share/signal-desktop/app.asar.unpacked" "$tmp/app.asar.unpacked"
            chmod -R u+w "$tmp/app.asar.unpacked"
          fi
          chmod u+w "$tmp/app.asar"

          (
            cd "$tmp"
            asar extract ./app.asar ./app
          )

          test -d "$appdir/stylesheets"

          cp ${signalCss} "$appdir/stylesheets/stylix-signal.css"

          for f in \
            "$appdir/stylesheets/manifest.css" \
            "$appdir/stylesheets/manifest_bridge.css" \
            "$appdir/stylesheets/tailwind.css"
          do
            if [ -f "$f" ] && ! grep -Fq 'stylix signal override' "$f"; then
              {
                cat "$f"
                printf '\n\n/* stylix signal override */\n'
                cat "$appdir/stylesheets/stylix-signal.css"
              } > "$f.new"
              mv "$f.new" "$f"
            fi
          done

          rm -f "$out/share/signal-desktop/app.asar"
          rm -rf "$out/share/signal-desktop/app.asar.unpacked"

          (
            cd "$tmp"
            asar pack --unpack '*.node' ./app ./new.asar
          )

          cp "$tmp/new.asar" "$out/share/signal-desktop/app.asar"
          if [ -d "$tmp/app.asar.unpacked" ]; then
            cp -r "$tmp/app.asar.unpacked" "$out/share/signal-desktop/app.asar.unpacked"
          fi
        '';
      });
    };
}
