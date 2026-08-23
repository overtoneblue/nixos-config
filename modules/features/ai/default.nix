{
  ...
}:
{
  flake.nixosModules.ai =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      virtualisation.oci-containers.backend = "podman";

      virtualisation.oci-containers.containers.comfyui = {
        image = "ghcr.io/utensils/comfyui-nix:latest-cuda";
        autoStart = false;

        ports = [
          "127.0.0.1:8188:8188"
        ];

        volumes = [
          "${config.modules.system.homeDirectory}/ai/comfyui-nix-data:/data"
        ];

        environment = {
          USER = "comfyui";
          LOGNAME = "comfyui";
          HOME = "/data/user";
          TORCHINDUCTOR_CACHE_DIR = "/data/user/.cache/torchinductor";
        };

        extraOptions = [
          "--device=nvidia.com/gpu=all"
        ];

        cmd = [
          "--listen"
          "0.0.0.0"
          "--enable-manager"
          "--lowvram"
        ];
      };

      virtualisation.podman = {
        enable = true;

        # Gives you a `docker` compatibility CLI if something expects Docker.
        dockerCompat = true;

        # Useful for DNS/networking in containers.
        defaultNetwork.settings.dns_enabled = true;
      };

      hardware.nvidia-container-toolkit.enable = true;

      environment.systemPackages = with pkgs; [
        podman
        podman-compose
        docker-compose
      ];
    };
}
