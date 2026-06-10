{ ... }:

let
  pythonTemplate = {
    path = ../templates/python;
    description = "Python dev shell with venv and my configured packages/configs";
    welcomeText = ''
      Created Python dev template.

      Next:
        direnv allow
        which git
        python --version
    '';
  };
in
{
  flake.templates = {
    python = pythonTemplate;
    default = pythonTemplate;
  };
}
