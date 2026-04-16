{ self, inputs, ... }:
{
  flake.nixosModules.dev =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        self.packages.${pkgs.system}.myNvf
        self.packages.${pkgs.system}.myZsh
        self.packages.${pkgs.system}.myStarship
      ];

      programs.zsh.enable = true;
      environment.pathsToLink = [ "/share/zsh" ];

      users.users.cenunix.shell = self.packages.${pkgs.system}.myZsh;
    };
  perSystem =
    { pkgs, self', ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [
          self'.packages.myNvf
          self'.packages.myZsh
          self'.packages.myStarship
          pkgs.git
          pkgs.direnv
          pkgs.nix-direnv
          pkgs.fd
          pkgs.ripgrep
          pkgs.eza
          pkgs.bat
          pkgs.zoxide
          pkgs.fzf
        ];

        shellHook = ''
          export EDITOR=nvim
          export VISUAL=nvim

          if [ -z "$IN_MY_DEV_ZSH" ]; then
            export IN_MY_DEV_ZSH=1
            exec ${self'.packages.myZsh}/bin/zsh
          fi
        '';
      };
    };

}
