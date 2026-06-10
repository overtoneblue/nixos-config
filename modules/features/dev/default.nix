{ self, inputs, ... }:
{
  flake.nixosModules.dev =
    { pkgs, ... }:
    let
      devinit = pkgs.writeShellScriptBin "devinit" ''
        nix flake init --refresh --template "github:overtoneblue/nixos-config#$1" && direnv allow
      '';
    in
    {
      environment.systemPackages = [
        devinit
        self.packages.${pkgs.system}.myNvf
        self.packages.${pkgs.system}.myZsh
        self.packages.${pkgs.system}.myStarship
        self.packages.${pkgs.system}.myWezterm
        self.packages.${pkgs.system}.myGit
        pkgs.git-filter-repo
        pkgs.eza
        pkgs.btop
        pkgs.jq
      ];

      programs.zsh.enable = true;
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
      environment.pathsToLink = [
        "/share/zsh"
        "/share/nix-direnv"
      ];
      users.users.cenunix.shell = self.packages.${pkgs.system}.myZsh;
    };
  perSystem =
    { pkgs, self', ... }:
    {
      devShells.dev = pkgs.mkShell {
        packages = [
          self'.packages.myNvf
          self'.packages.myZsh
          self'.packages.myStarship
          self'.packages.myWezterm
          self'.packages.myGit
          pkgs.git-filter-repo
          pkgs.direnv
          pkgs.nix-direnv
          pkgs.fd
          pkgs.ripgrep
          pkgs.eza
          pkgs.bat
          pkgs.zoxide
          pkgs.fzf
          pkgs.btop
          pkgs.jq
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
