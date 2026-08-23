{ lib, config, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.modules.system = {
    username = mkOption {
      type = types.str;
      default = "overtoneblue";
      description = "Primary user account name shared by all hosts.";
    };

    homeDirectory = mkOption {
      type = types.str;
      default = "/home/${config.modules.system.username}";
      description = "Home directory of the primary user account.";
    };

    flakePath = mkOption {
      type = types.nullOr types.str;
      default = "${config.modules.system.homeDirectory}/nixos-config";
      description = "Flake path used by nh, or null for remotely managed hosts.";
    };

    extraGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional groups for the primary user account on this host.";
    };
  };
}
