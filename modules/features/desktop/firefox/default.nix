{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.firefox =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    with lib;
    let
      # startpage = pkgs.substituteAll { src = ./startpage.html; };
      user = config.modules.system.username;
      addons = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system};
      colors = config.lib.stylix.colors.withHashtag;
    in
    {
      hm.programs = {
        firefox = lib.mkForce {
          enable = true;
          # package = pkgs.firefox;
          policies = {
            DisableFirefoxAccounts = true;
            Cookies = {
              Allow = [
                "https://Kagi.com"
                "https://discord.com"
                "https://github.com"
                "https://boot.dev"
                "https://proton.me"
                "https://openai.com"
                "https://youtube.com"
                "https://chatgpt.com"
              ];
            };
            Homepage = {
              StartPage = "homepage";
              URL = "https://my.wgu.edu/";
              Locked = true;

              Additional = [
                "https://docs.python.org/3/"
                "https://discourse.nixos.org/"
                # "https://docs.aws.amazon.com"
                # "https://kubernetes.io/docs/home/"
                # "file:///home/youruser/notes/today.md"
                # "https://chatgpt.com"
              ];
            };
          };
          profiles.cenunix = {
            name = "cenunix";
            isDefault = true;
            search = {
              engines = {
                "kagi" = {
                  urls = [ { template = "https://kagi.com/search?q={searchTerms}"; } ];
                  icon = "https://kagi.com/favicon.ico";
                };
                "bing".metaData.hidden = true;
              };
              force = true;
              default = "kagi";
              privateDefault = "kagi";
              order = [
                "kagi"
              ];
            };
            extensions = {
              force = true;
              packages = with addons; [
                ublock-origin
                bitwarden
                darkreader
                vimium-c
                purpleadblock
              ];
              settings = {
                darkreader = {
                  force = true;
                  settings = {
                    enabled = true;
                    theme = {
                      mode = 1;
                      darkSchemeBackgroundColor = colors.base00;
                      # darkSchemeTextColor = colors.base05;
                    };
                    previewNewDesign = true;
                  };
                };
              };
            };
            bookmarks = { };
            settings = {
              # ===========================================================================
              # Core UI / Theme / Layout
              # ===========================================================================

              "extensions.autoDisableScopes" = 0;
              "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

              "layout.css.prefers-color-scheme.content-override" = 2;
              "ui.systemUsesDarkTheme" = 1;
              "browser.compactmode.show" = true;

              # Sidebar / vertical tabs
              "sidebar.verticalTabs" = true;
              "sidebar.revamp" = true;
              "sidebar.main.tools" = "history";

              # Firefox toolbar / UI layout
              "browser.uiCustomization.state" = builtins.toJSON {
                currentVersion = 20;
                newElementCount = 5;
                dirtyAreaCache = [
                  "nav-bar"
                  "PersonalToolbar"
                  "toolbar-menubar"
                  "TabsToolbar"
                  "widget-overflow-fixed-list"
                ];
                placements = {
                  PersonalToolbar = [ ];
                  TabsToolbar = [
                    "tabbrowser-tabs"
                    "new-tab-button"
                    "alltabs-button"
                  ];
                  nav-bar = [
                    "back-button"
                    "forward-button"
                    "stop-reload-button"
                    "urlbar-container"
                    "downloads-button"
                    "ublock0_raymondhill_net-browser-action"
                    "_testpilot-containers-browser-action"
                    "reset-pbm-toolbar-button"
                    "unified-extensions-button"
                  ];
                  toolbar-menubar = [ "menubar-items" ];
                  unified-extensions-area = [ ];
                  widget-overflow-fixed-list = [ ];
                };
                seen = [
                  "save-to-pocket-button"
                  "developer-button"
                  "ublock0_raymondhill_net-browser-action"
                  "_testpilot-containers-browser-action"
                ];
              };

              # ===========================================================================
              # Startup / Session / New Tab
              # ===========================================================================

              "browser.startup.page" = 1;
              "browser.sessionstore.resume_from_crash" = false;
              "browser.sessionstore.resume_session_once" = false;
              "browser.sessionstore.interval" = 60000;
              "browser.startup.homepage_override.mstone" = "ignore";
              "browser.aboutwelcome.enabled" = false;

              # New tab cleanup
              "browser.newtabpage.enabled" = false;
              "browser.newtabpage.activity-stream.improvesearch.handoffToAwesomebar" = false;
              "browser.newtabpage.activity-stream.default.sites" = "";
              "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
              "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
              "browser.newtabpage.activity-stream.showSponsored" = false;
              "browser.newtabpage.activity-stream.showSponsoredCheckboxes" = false;

              # ===========================================================================
              # Search / URL Bar
              # ===========================================================================

              "browser.search.separatePrivateDefault.ui.enabled" = true;
              "browser.search.update" = false;

              "browser.urlbar.trimHttps" = true;
              "browser.urlbar.untrimOnUserInteraction.featureGate" = true;
              "browser.urlbar.quicksuggest.enabled" = false;
              "browser.urlbar.groupLabels.enabled" = false;
              "browser.urlbar.suggest.engines" = false;
              "browser.urlbar.trending.featureGate" = false;

              # Left as your current choice
              # "browser.search.suggest.enabled" = false;

              "browser.formfill.enable" = false;
              "network.IDN_show_punycode" = true;

              # ===========================================================================
              # Privacy / Security / Anti-Tracking
              # ===========================================================================

              "browser.contentblocking.category" = "strict";
              "privacy.globalprivacycontrol.enabled" = true;
              "privacy.antitracking.isolateContentScriptResources" = true;
              "privacy.history.custom" = true;
              "privacy.userContext.ui.enabled" = true;

              "security.OCSP.enabled" = 0;
              "security.csp.reporting.enabled" = false;
              "security.ssl.treat_unsafe_negotiation_as_broken" = true;
              "security.tls.enable_0rtt_data" = false;
              "browser.xul.error_pages.expert_bad_cert" = true;

              # Left as your current choice
              # "dom.security.https_only_mode" = true;
              "dom.security.https_only_mode_error_page_user_suggestions" = true;

              "network.http.referer.XOriginTrimmingPolicy" = 2;

              "permissions.default.desktop-notification" = 2;
              "permissions.default.geo" = 2;
              "geo.provider.network.url" = "https://beacondb.net/v1/geolocate";
              "permissions.manager.defaultsUrl" = "";

              # ===========================================================================
              # Network / Speculative Loading / Performance
              # ===========================================================================

              "gfx.canvas.accelerated.cache-size" = 256;

              # Left as your current choice
              # "browser.cache.disk.enable" = false;

              "browser.privatebrowsing.forceMediaMemoryCache" = true;
              "media.memory_cache_max_size" = 65536;

              "browser.download.start_downloads_in_tmp_dir" = true;

              "network.http.speculative-parallel-limit" = 0;
              "network.dns.disablePrefetch" = true;
              "network.dns.disablePrefetchFromHTTPS" = true;
              "browser.urlbar.speculativeConnect.enabled" = false;
              "browser.places.speculativeConnect.enabled" = false;
              "network.prefetch-next" = false;

              # ===========================================================================
              # Passwords / Auth / Forms
              # ===========================================================================

              "signon.formlessCapture.enabled" = false;
              "signon.privateBrowsingCapture.enabled" = false;
              "network.auth.subresource-http-auth-allow" = 1;
              "editor.truncate_user_pastes" = false;

              # ===========================================================================
              # Extensions / Mozilla UX / Annoyance Removal
              # ===========================================================================

              "extensions.enabledScopes" = 5;
              "extensions.getAddons.cache.enabled" = false;
              "extensions.getAddons.showPane" = false;
              "extensions.htmlaboutaddons.recommendations.enabled" = false;

              "browser.discovery.enabled" = false;
              "browser.shell.checkDefaultBrowser" = false;
              "browser.preferences.moreFromMozilla" = false;
              "browser.aboutConfig.showWarning" = false;
              "browser.profiles.enabled" = false;
              "browser.uitour.enabled" = false;

              "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
              "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;

              # ===========================================================================
              # Mozilla Telemetry / Experiments / Crash Reports
              # ===========================================================================

              "datareporting.policy.dataSubmissionEnabled" = false;
              "datareporting.healthreport.uploadEnabled" = false;
              "datareporting.usage.uploadEnabled" = false;

              "toolkit.telemetry.unified" = false;
              "toolkit.telemetry.enabled" = false;
              "toolkit.telemetry.server" = "data:,";
              "toolkit.telemetry.archive.enabled" = false;
              "toolkit.telemetry.newProfilePing.enabled" = false;
              "toolkit.telemetry.shutdownPingSender.enabled" = false;
              "toolkit.telemetry.updatePing.enabled" = false;
              "toolkit.telemetry.bhrPing.enabled" = false;
              "toolkit.telemetry.firstShutdownPing.enabled" = false;
              "toolkit.telemetry.coverage.opt-out" = true;
              "toolkit.coverage.opt-out" = true;
              "toolkit.coverage.endpoint.base" = "";

              "browser.newtabpage.activity-stream.feeds.telemetry" = false;
              "browser.newtabpage.activity-stream.telemetry" = false;

              "app.shield.optoutstudies.enabled" = false;
              "app.normandy.enabled" = false;
              "app.normandy.api_url" = "";

              "breakpad.reportURL" = "";
              "browser.tabs.crashReporting.sendReport" = false;

              # ===========================================================================
              # AI / ML / Smart Features
              # ===========================================================================

              "browser.ai.control.default" = "blocked";
              "browser.ml.enable" = false;
              "browser.tabs.groups.smart.enabled" = false;
              "browser.ml.linkPreview.enabled" = false;
              "browser.ml.chat.enabled" = false;
              "browser.ml.chat.menu" = false;

              # ===========================================================================
              # Downloads / PDFs
              # ===========================================================================

              "browser.download.manager.addToRecentDocs" = false;
              "browser.download.open_pdf_attachments_inline" = true;
              "browser.safebrowsing.downloads.remote.enabled" = false;
              "pdfjs.enableScripting" = false;

              # ===========================================================================
              # Fullscreen / Tab / Interaction Niceties
              # ===========================================================================

              "full-screen-api.transition-duration.enter" = "0 0";
              "full-screen-api.transition-duration.leave" = "0 0";

              "browser.bookmarks.openInTabClosesMenu" = false;
              "browser.menu.showViewImageInfo" = true;
              "findbar.highlightAll" = true;
              "layout.word_select.eat_space_to_next_word" = false;

              # ===========================================================================
              # Private Browsing Behavior
              # ===========================================================================

              "browser.privatebrowsing.resetPBM.enabled" = true;

              "general.smoothScroll" = true;
              "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
              "general.smoothScroll.msdPhysics.enabled" = true;
              "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 600;
              "general.smoothScroll.msdPhysics.regularSpringConstant" = 650;
              "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 25;
              "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = "2";
              "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 250;
              "general.smoothScroll.currentVelocityWeighting" = "1";
              "general.smoothScroll.stopDecelerationWeighting" = "1";
              "mousewheel.default.delta_multiplier_y" = 300;
            };
            userContent = ''
              /* All internal about: pages */
              @-moz-document url-prefix("about:"), url-prefix("chrome:") {
                :root {
                  /* Core in-content variables */
                  --in-content-page-background:        ${colors.base00} !important;
                  --in-content-box-background:         ${colors.base00} !important;
                  --in-content-box-background-odd:     ${colors.base00} !important;
                  --in-content-table-background:       ${colors.base00} !important;
                  --in-content-table-header-background:${colors.base00} !important;
                  --in-content-dialog-header-background:${colors.base00} !important;
                  --in-content-box-info-background:    ${colors.base00} !important;

                  --in-content-border-color:           ${colors.base02} !important;
                  --in-content-box-border-color:       ${colors.base02} !important;
                  --card-outline-color:                ${colors.base02} !important;

                  --in-content-page-color:             ${colors.base05} !important;
                  --in-content-text-color:             ${colors.base05} !important;
                }

                html, body {
                  background-color: ${colors.base00} !important;
                  color: ${colors.base05} !important;
                }

                /* Generic form elements on these pages */
                input, textarea, select {
                  background-color: ${colors.base00} !important;
                  color: ${colors.base05} !important;
                  border-color: ${colors.base02} !important;
                  box-shadow: none !important;
                }
              }

              /* 2. about:config specific bits (search bar/header that like to ignore vars) */
              @-moz-document url("about:config") {
                :root, html, body {
                  background-color: ${colors.base00} !important;
                  color: ${colors.base05} !important;
                }

                .sticky-container,
                #config-main,
                #config-container {
                  background-color: ${colors.base00} !important;
                }

                #about-config-search,
                .config-search input[type="search"] {
                  -moz-appearance: none !important;
                  background-color: ${colors.base00} !important;
                  color: ${colors.base05} !important;
                  border: 1px solid ${colors.base02} !important;
                  box-shadow: none !important;
                }
              }
                    
            '';
            userChrome = ''
              :root,
              :root[lwtheme],
              #main-window {
                /* Your palette */
                --my-bg: ${colors.base00} !important;
                --my-bg-2: ${colors.base01} !important;
                --my-fg: ${colors.base05} !important;
                --my-hi: ${colors.base04} !important;

                /* Window / theme frame */
                --lwt-frame: var(--my-bg) !important;
                --lwt-accent-color: var(--my-bg) !important;
                --lwt-text-color: var(--my-fg) !important;

                /* Toolbars */
                --toolbar-bgcolor: var(--my-bg) !important;
                --toolbar-color: var(--my-fg) !important;

                /* URL bar / fields */
                --toolbar-field-background-color: var(--my-bg) !important;
                --toolbar-field-focus-background-color: var(--my-bg) !important;
                --toolbar-field-color: var(--my-fg) !important;
                --toolbar-field-focus-color: var(--my-fg) !important;
                --input-bgcolor: var(--my-bg) !important;
                --input-color: var(--my-fg) !important;

                /* Panels / menus */
                --panel-background: var(--my-bg) !important;
                --panel-color: var(--my-fg) !important;
                --arrowpanel-background: var(--my-bg) !important;
                --arrowpanel-color: var(--my-fg) !important;
                --arrowpanel-border-color: var(--my-bg-2) !important;
                --panel-separator-color: var(--my-bg-2) !important;

                /* Sidebar (native sidebar + vertical tabs) */
                --sidebar-background-color: var(--my-bg) !important;
                --sidebar-text-color: var(--my-fg) !important;
                --sidebar-border-color: var(--my-bg-2) !important;

                /* NEW: Firefox 146-ish vertical-tabs / sidebar pane surface */
                --tabpane-background-color: var(--my-bg) !important;     /* this was #2b2a33 in your screenshot */
                --tabpanel-background-color: var(--my-bg) !important;    
                --tab-hover-background-color: var(--my-bg-2) !important; /* hover blend that can look “default” */

                /* Buttons / hover states (often the “mystery gray”) */
                --button-background-color: var(--my-bg-2) !important;
                --button-color: var(--my-fg) !important;

                --toolbarbutton-icon-fill: var(--my-fg) !important;
                --toolbarbutton-hover-background: var(--my-bg-2) !important;
                --toolbarbutton-active-background: var(--my-bg-2) !important;

                /* Separators that sometimes show default theme color */
                --tabs-navbar-separator-color: var(--my-bg) !important;
                --chrome-content-separator-color: var(--my-bg) !important;

                /* Optional highlight colors */
                --urlbarView-highlight-color: var(--my-fg) !important;
                --urlbarView-highlight-background: var(--my-hi) !important;

                /* Keep titlebar opacity consistent */
                --inactive-titlebar-opacity: 1.0 !important;            
              }
              #TabsToolbar {
                visibility: collapse !important;
              }
              #PersonalToolbar,
              #toolbar,
              #nav-bar {
                background-color: ${colors.base00} !important;
                background-image: none !important;
              }
              tab-close-button.close-icon {
                display: none;
                color: red;
              }
              tab-label-container {
                color: ${colors.base00};
              }
              #_c607c8df-14a7-4f28-894f-29e8722976af_-BAP {
                 color: ${colors.base00};
              }
              #TabsToolbar {
                background-color: ${colors.base00} !important;
              }
              #nav-bar {
                background-color: ${colors.base00};
              }
              #tracking-protection-icon-container {
                background-color: ${colors.base00};
              }
              #appMenu-multiView {
                background-color: ${colors.base00} !important;
              }
              .urlbar-page-action {
                background-color: ${colors.base00};
              }
              .identity-box-button  {
                background-color: ${colors.base00};
              }
              .urlbar-input-box {
                background-color: ${colors.base00};
              }
              #sidebar-main {
                background-color: ${colors.base00} !important;
              }
              .tabbrowser-tab {
                color: ${colors.base05} !important;
                color-scheme: unset;
              }
              tab[selected="true"] > .tab-stack > .tab-background {
                background: ${colors.base01} !important;
              }
              tab:not([selected="true"]) > .tab-stack:hover > .tab-background {
                background: ${colors.base01} !important;
              }
              #firefox-view-button {
                list-style-image : url(nix-snowflake.svg) !important;
              }
            '';
          };
        };
      };
    };
}
