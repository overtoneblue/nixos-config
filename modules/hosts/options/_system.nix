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

    desktopCommand = mkOption {
      type = types.package;
      description = ''
        `desktop` command: SSH bridge into the node0 graphical session.
        Defined on head (modules/hosts/head/configuration.nix) and referenced
        by the head system profile (interactive overtoneblue TUI) and by
        services.hermes-agent extraPackages (gateway PATH) so both the TUI and
        the hermes service can run desktop commands on node0.
      '';
    };
  };
}
