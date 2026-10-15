{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.discord =
    { pkgs, lib, config, ... }:
    {
      options.modules.programs.discord.vesktop = lib.mkEnableOption "Vesktop instead of official Discord (aarch64)";
      config.hm = {
        # Import stays unconditional (options only); the app is gated.
        imports = [
          inputs.nixcord.homeModules.nixcord
        ];
        programs.nixcord = lib.mkIf (config.modules.programs.desktopApps.enable || config.modules.programs.discord.vesktop) {
          enable = true;
          # aarch64 (callisto): official Discord is x86-only -> Vesktop, same Vencord config.
          discord.enable = !config.modules.programs.discord.vesktop;
          discord.vencord.enable = !config.modules.programs.discord.vesktop;
          vesktop.enable = config.modules.programs.discord.vesktop;
          config = {
            frameless = true;
            plugins = {
              ClearURLs.enable = true;
              # experiments.enable = true;
              f8Break.enable = true;
              fixImagesQuality.enable = true;
              fixSpotifyEmbeds.enable = true;
              fixYoutubeEmbeds.enable = true;
              gameActivityToggle.enable = true;
              hideMedia.enable = true;
              memberCount.enable = true;
              messageLogger.enable = true;
              messageClickActions.enable = true;
              newGuildSettings.enable = true;
              openInApp.enable = true;
              previewMessage.enable = true;
              readAllNotificationsButton.enable = true;
              relationshipNotifier.enable = true;
              reverseImageSearch.enable = true;
              # reviewDB.enable = true;
              serverInfo.enable = true;
              shikiCodeblocks.enable = true;
              showHiddenChannels.enable = true;
              showHiddenThings.enable = true;
              showTimeoutDuration.enable = true;
              silentTyping.enable = true;
              youtubeAdblock.enable = true;
              webScreenShareFixes.enable = true;
            };
          };
        };
      };
    };
}
