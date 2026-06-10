{ self, ... }:

{
  templates = {
    python-dev = {
      path = ./python/flake.nix;
      description = "Python dev shell with venv and my configured packages/configs";
      welcomeText = ''
        Created Python dev template.

        Next:
          direnv allow
          which git
          python --version
      '';
    };

    default = self.templates.python-dev;
  };
}
