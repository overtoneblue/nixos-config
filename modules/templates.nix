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
  javaTemplate = {
    path = ../templates/java;
    description = "Java dev shell with venv and my configured packages/configs";
    welcomeText = ''
      Created Java dev template.

      Next:
        direnv allow
    '';
  };
in
{
  flake.templates = {
    python = pythonTemplate;
    java = javaTemplate;
    default = pythonTemplate;
  };
}
