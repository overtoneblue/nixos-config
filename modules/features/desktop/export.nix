{
  self,
  ...
}:
{
  flake.nixosModules.desktop =
    { ... }:
    {
      imports = [
        self.nixosModules.hyprland
        self.nixosModules.discord
        self.nixosModules.signal
        self.nixosModules.element
        self.nixosModules.noctalia
        self.nixosModules.firefox
      ];
    };
}
