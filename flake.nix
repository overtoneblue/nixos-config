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
    # Upstream main (0.21.0): our TTFB PR merged upstream as #100425
    # (salvage of #98555, merged 2026-09-01, verified surviving the 0.21.0
    # refactor), so the overtoneblue/ttfb-on-main fork pin (@cc09928c) is
    # retired in favor of upstream main.
    #
    # 2026-09-28: fork pin overtoneblue/hermes-agent @ atlas-archive —
    # deployed d0288be5b3 plus one commit plumbing `include_compacted`
    # through GET /api/sessions/{id}/messages (the DB layer already
    # supports it; the route dropped it). Atlas pages the deduped display
    # history so compaction-archived turns stay scrollable. Upstream PR
    # candidate — retire this pin once it merges.
    hermes-agent.url = "github:overtoneblue/hermes-agent/atlas-archive";
    # Atlas: the workstream client app, sourced from the public
    # github:overtoneblue/atlas repo. The sops access-tokens include
    # (modules/hosts/head/configuration.nix) is kept as an inert safety
    # net: revoked/expired tokens don't break public fetches (verified
    # 2026-09-28), and re-privatizing the repo works without a rebuild.
    atlas = {
      url = "github:overtoneblue/atlas";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
