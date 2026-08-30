{ self, inputs, ... }:
{
  flake.nixosConfigurations.head = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.headConfiguration
    ];
    # Expose the flake `self` to nixosConfigurations so modules can reference
    # flake packages (e.g. self.packages.${system}.head-dash).
    specialArgs = {
      inherit self;
    };
  };
}
