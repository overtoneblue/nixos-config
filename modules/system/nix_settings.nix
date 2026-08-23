{
  self,
  inputs,
  ...
}:
{
  flake.nixosModules.nix-settings =
    {
      pkgs,
      lib,
      config,
      ...
    }:

    {
      programs.nh = {
        enable = true;
        clean.enable = true;
        clean.extraArgs = "--keep-since 4d --keep 5";
        flake = config.modules.system.flakePath;
      };
      nixpkgs.config = {
        allowUnfree = true;
        allowBroken = false;
      };
      nix = {
        settings = {
          extra-experimental-features = [
            "flakes"
            "nix-command"
            # "ca-derivations"
          ];
          auto-optimise-store = true;
          allowed-users = [
            "root"
            "@wheel"
            config.modules.system.username
          ];
          trusted-users = [
            "root"
            "@wheel"
            config.modules.system.username
          ];
          warn-dirty = false;
          builders-use-substitutes = true;
          extra-substituters = [
            "https://cache.nixos.org"
            "https://nix-community.cachix.org"
            "https://hyprland.cachix.org"
            "https://nix-gaming.cachix.org"
            "https://comfyui.cachix.org"
            "https://noctalia.cachix.org"
          ];
          extra-trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
            "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
            "comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec="
            "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
          ];
        };
      };
    };
}
