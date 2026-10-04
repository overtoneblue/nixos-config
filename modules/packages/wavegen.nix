{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Matrix bot for WaveSpeedAI image editing.
      packages.wavegen =
        pkgs.python3Packages.buildPythonApplication rec {
          pname = "wavegen";
          version = "0.1.0";
          src = ../../packages/wavegen;
          pyproject = true;
          build-system = with pkgs.python3Packages; [ setuptools ];

          propagatedBuildInputs = with pkgs.python3Packages; [ httpx ];

          meta.mainProgram = "wavegen";
        };

      # Web UI for the same.
      packages.wavegen-web =
        pkgs.python3Packages.buildPythonApplication rec {
          pname = "wavegen-web";
          version = "0.1.0";
          src = ../../packages/wavegen-web;
          pyproject = true;

          build-system = with pkgs.python3Packages; [ setuptools ];

          propagatedBuildInputs = with pkgs.python3Packages; [
            starlette
            uvicorn
            python-multipart
            httpx
            aiofiles
          ];

          meta.mainProgram = "wavegen-web";
        };
    };
}