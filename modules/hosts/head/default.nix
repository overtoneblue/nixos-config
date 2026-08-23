{ self, inputs, ... }:
{
  flake.nixosConfigurations.head = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.headConfiguration
    ];
  };
}
