{ self, inputs, ... }:
{
  # Lenovo ThinkPad X13s (Snapdragon 8cx Gen 3 / sc8280xp), aarch64-linux.
  # Ported from NixLand hosts/callisto. Builds on the laptop itself — head is
  # x86_64 with no aarch64 emulation, so it can only evaluate this config.
  flake.nixosConfigurations.callisto = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.callistoConfiguration
    ];
  };
}
