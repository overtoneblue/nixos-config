{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.element =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      colors = config.lib.stylix.colors.withHashtag;

      elementThemeJson = pkgs.writeText "element-config.json" (
        builtins.toJSON {
          setting_defaults = {
            custom_themes = [
              {
                name = "base16 dark";
                is_dark = true;
                colors = {
                  "accent-color" = colors.base03;
                  accent = colors.base0D;
                  "primary-color" = colors.base0B;
                  "warning-color" = colors.base08;
                  alert = colors.base08;

                  "sidebar-color" = colors.base00;
                  "roomlist-background-color" = colors.base00;
                  "roomlist-text-color" = colors.base05;
                  "roomlist-text-secondary-color" = colors.base04;
                  "roomlist-highlights-color" = colors.base02;
                  "roomlist-separator-color" = colors.base03;

                  "timeline-background-color" = colors.base00;
                  "timeline-text-color" = colors.base05;
                  "secondary-content" = colors.base05;
                  "tertiary-content" = colors.base05;
                  "timeline-text-secondary-color" = colors.base04;
                  "timeline-highlights-color" = colors.base01;

                  "reaction-row-button-selected-bg-color" = colors.base0D;
                  "menu-selected-color" = colors.base0D;
                  "focus-bg-color" = colors.base0D;
                  "room-highlight-color" = colors.base0D;
                  "other-user-pill-bg-color" = colors.base0D;
                  "togglesw-off-color" = colors.base03;
                };

                compound = {
                  "--cpd-color-theme-bg" = colors.base0D;
                  "--cpd-color-bg-canvas-default" = colors.base00;
                  "--cpd-color-bg-subtle-secondary" = colors.base00;
                  "--cpd-color-bg-subtle-primary" = colors.base02;
                  "--cpd-color-bg-action-primary-rest" = colors.base05;
                  "--cpd-color-bg-action-secondary-rest" = colors.base00;
                  "--cpd-color-bg-critical-primary" = colors.base08;
                  "--cpd-color-bg-critical-subtle" = colors.base03;
                  "--cpd-color-bg-critical-hovered" = colors.base08;
                  "--cpd-color-bg-accent-rest" = colors.base0B;
                  "--cpd-color-text-primary" = colors.base05;
                  "--cpd-color-text-secondary" = colors.base04;
                  "--cpd-color-text-action-accent" = colors.base06;
                  "--cpd-color-text-critical-primary" = colors.base08;
                  "--cpd-color-text-success-primary" = colors.base0B;
                  "--cpd-color-icon-primary" = colors.base05;
                  "--cpd-color-icon-secondary" = colors.base04;
                  "--cpd-color-icon-tertiary" = colors.base03;
                  "--cpd-color-icon-accent-tertiary" = colors.base0B;
                  "--cpd-color-border-interactive-primary" = colors.base03;
                  "--cpd-color-border-interactive-secondary" = colors.base03;
                  "--cpd-color-border-critical-primary" = colors.base08;
                  "--cpd-color-border-success-subtle" = colors.base0B;
                };
              }
            ];
          };

          show_labs_settings = true;
        }
      );
    in
    {
      hm.xdg.configFile."Element/config.json".source = elementThemeJson;
    };
}
