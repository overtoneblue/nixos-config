{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # wavegen: standalone Matrix bot for WaveSpeedAI image editing
      # (ByteDance Seedream V5.0 Pro Edit). See packages/wavegen/wavegen.py.
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

      # wavegen-web: web UI for WaveSpeedAI image editing.
      # (Starlette + uvicorn, queue with 2-parallel workers, history, retry).
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