{ ... }:
{
  flake.wrappers.starship =
    { pkgs, wlib, ... }:
    let
      toml = pkgs.formats.toml { };
      starshipConfig = toml.generate "starship.toml" {
        add_newline = false;
        scan_timeout = 5;

        git_commit = {
          commit_hash_length = 4;
        };

        character = {
          error_symbol = "[󰊠](bold red)";
          success_symbol = "[󰊠](bold green)";
          vicmd_symbol = "[󰊠](bold yellow)";
          format = "$symbol [|](bold bright-black) ";
        };

        hostname = {
          ssh_only = true;
          format = "[$hostname](bold blue) ";
          disabled = false;
        };
      };
    in
    {
      imports = [ wlib.modules.default ];

      config.package = pkgs.starship;
      config.env.STARSHIP_CONFIG.value = starshipConfig;
      config.meta.description = "Wrapped starship with personal config";
    };

  perSystem =
    { pkgs, self', ... }:
    {
      packages.myStarship = self'.wrappers.starship.wrap {
        inherit pkgs;
      };
    };
}
