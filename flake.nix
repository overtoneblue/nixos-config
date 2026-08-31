{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    comfyui-nix.url = "github:utensils/comfyui-nix";
    hyprland.url = "github:hyprwm/hyprland";
    computer-use-linux = {
      url = "github:agent-sh/computer-use-linux";
      flake = false;
    };
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "github:kaylorben/nixcord";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # PR 98555 (first_chunk_at in post_api_request) — fork branch pinned at
    # upstream rev 3a915c46 + the PR commit 4ba91eedf8. Revert to
    # github:NousResearch/hermes-agent once the PR merges.
    hermes-agent.url = "github:overtoneblue/hermes-agent/feature/first-chunk-at-hook";
    # hermes-agent.url = "github:NousResearch/hermes-agent";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
