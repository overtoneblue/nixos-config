{ self, inputs, ... }:
{

  flake.nixosModules.node0Configuration =
    { pkgs, lib, ... }:
    {
      # import any other modules from here
      imports = [
        self.nixosModules.node0Hardware
        # self.nixosModules.niri
      ];

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      environment.systemPackages = with pkgs; [
        firefox
        zed
        helix
        neovim
      ];
    };
}
