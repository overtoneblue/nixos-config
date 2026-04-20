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
        :root {
          --color-elevated-background-tertiary: ${colors.base02};
        }
        body.dark-theme {
          background-color: ${colors.base00};
          color: ${colors.base05}; 
        }

        /* left most bar */
        .NavTabs {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        .NavTabs__ItemButton:hover {
          background-color: ${colors.base02} !important;
        }

        .NavTabs__Item[aria-selected="true"] > span > .NavTabs__ItemButton {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        /* buttons in qr and link section of personal user profile */
        .UsernameLinkModalBody__actions__save,
        .UsernameLinkModalBody__actions__color {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        /* second to left bar */
        .NavSidebar {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* view archive button when clicking on ... */
        .ContextMenu__popper--single-item {
          background-color: ${colors.base01} !important;
          color: ${colors.base05} !important;
        }

        .module-conversation-list__item--contact-or-conversation--is-selected {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        /* no archived chat text */
        .module-left-pane__archive-helper-text {
          background-color: ${colors.base00} !important;
          color: ${colors.base04} !important;
        }

        .module-conversation-list__item--contact-or-conversation:hover,
        .module-conversation-list__item--contact-or-conversation:focus,
        .module-conversation-list__item--archive-button:hover,
        .module-conversation-list__item--archive-button:focus {
          background-color: ${colors.base02} !important;
        }

        .Inbox__no-conversation-open {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* the bar at the top containing your contact name */
        .module-ConversationHeader {
          background-color: ${colors.base00} !important;
          color: ${colors.base06} !important;
        }

        /* call, search, etc button present at conversation header */
        .module-ConversationHeader__button:hover,
        .module-ConversationHeader__button:focus {
          background-color: ${colors.base02} !important;
        }

        /* ... menu at conversation header */
        .react-contextmenu {
          background-color: ${colors.base01} !important;
          color: ${colors.base05} !important;
          border-color: ${colors.base03} !important;
        }

        /* ... menu hover */
        .react-contextmenu-item--selected {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        /* the vm player that appears at top */
        .MiniPlayer {
          background-color: ${colors.base02} !important;
          color: ${colors.base06} !important;
        }

        /* conversation area */
        .module-timeline {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* messages */
        /* from */
        .module-message__container--incoming {
          background-color: ${colors.base01} !important;
          color: ${colors.base05} !important;
        }
        /* outgoing */
        .dark-theme .module-message__container--outgoing,
        .dark-theme .module-message__container--outgoing-ultramarine {
          background-image: none !important;
          background-color: ${colors.base03} !important;
          color: ${colors.base05} !important;
        }

        /* replying box */
        .module-quote--incoming > .module-quote__primary,
        .module-quote--incoming > .module-quote__icon-container {
          background-color: ${colors.base02} !important;
          border: 0px !important;
          color: ${colors.base05} !important;
        }

        /* call again button */
        .module-Button--system-message {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        /* the area where you write message, attach file, send vm, etc. */
        .CompositionArea {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* the actual typing box */
        .module-composition-input__input {
          background-color: ${colors.base01} !important;
          color: ${colors.base05} !important;
          border-color: ${colors.base03} !important;
        }

        .module-composition-input__input::placeholder {
          color: ${colors.base04} !important;
        }

        /* Chat search box interior color*/
        .dark-theme .module-SearchInput__input {
          background-color: ${colors.base01} !important;
          color: ${colors.base05} !important;
        }

        /* the today or yesterday thing that appears when you scroll up */
        .TimelineDateHeader--floating {
          background-color: ${colors.base01} !important;
          color: ${colors.base05} !important;
        }

        .TimelineFloatingHeader__spinner-container {
          background-color: ${colors.base01} !important;
        }

        .ScrollDownButton {
          background-color: ${colors.base01} !important;
          color: ${colors.base06} !important;
        }

        /* background when contact isn't selected */
        .CallsTab__EmptyState {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* background when contact is selected */
        .CallsTab__ConversationCallDetails {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* contact list sidebar item */
        .CallsList__ItemTile:hover {
          background-color: ${colors.base02} !important;
        }

        .CallsList__ItemTile[aria-selected="true"] {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        .CallsNewCall_ItemActionButton {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }


        .dark-theme .Stories {
          background: ${colors.base00};
        }
        .Stories__placeholder {
          background-color: ${colors.base00} !important;
        }

        /* background of user details panel */
        .ConversationPanel,
        .ConversationPanel__header {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* disappearing message timer */
        .module-select > select {
          background-color: ${colors.base01} !important;
          color: ${colors.base05} !important;
          border-color: ${colors.base03} !important;
        }

        /* nickname, chatcolor, add to group and other button */
        .ConversationDetails-panel-row__root--button:hover {
          background-color: ${colors.base02} !important;
        }

        /* nickname edit menu */
        .Input__container {
          background-color: ${colors.base01} !important;
          border-color: ${colors.base03} !important;
          color: ${colors.base05} !important;
        }

        /* add to group button background color */
        .ConversationDetails-groups__add-to-group-icon {
          background-color: ${colors.base01} !important;
          color: ${colors.base06} !important;
        }

        /* the user profile, signal connection and safety number popup */
        .module-Modal {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* mark as verified or clear verification button */
        .module-SafetyNumberViewer__button > button {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        /* background when viewing image */
        .Lightbox__animated {
          background-color: ${colors.base00} !important;
        }

        /* many of the buttons */
        .module-Button {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
          border-color: ${colors.base03} !important;
        }

        .module-Button:hover {
          background-color: ${colors.base02} !important;
        }

        .module-Button--secondary--destructive {
          color: ${colors.base08} !important;
        }

        /* side panel of settings */
        .Preferences__page-selector {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* main settings panel */
        .Preferences__settings-pane {
          background-color: ${colors.base00} !important;
          color: ${colors.base05} !important;
        }

        /* page selector selected background */
        .Preferences__button--selected {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        .Preferences__button:focus {
          background-color: ${colors.base02} !important;
        }

        /* language and chat color button */
        .Preferences__control--clickable:hover {
          background-color: ${colors.base02} !important;
        }

        .module-calling__container {
          background-color: ${colors.base00} !important;
        }

        /* cancel and settings button */
        .CallSettingsButton__Button {
          background-color: ${colors.base01} !important;
          color: ${colors.base06} !important;
        }

        /* the bar at the bottom during calls */
        .CallControls {
          background-color: ${colors.base01} !important;
        }

        /* mic and camera button */
        .CallingButton__icon {
          background-color: ${colors.base03} !important;
          color: ${colors.base06} !important;
        }

        /* your pfp box during call */
        .module-calling__background {
          background-color: ${colors.base01} !important;
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
