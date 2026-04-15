{ self, inputs, ... }:
{
  flake.nixosConfigurations.node0 = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.node0Configuration
      ./system.nix
    ];
  };
}
