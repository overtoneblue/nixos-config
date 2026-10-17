{ self, inputs, ... }:
# Hermes Desktop as a pure client of head's backend, for machines other than
# node0 (no agent runtime, no computer-use, no reverse tunnels). The app talks
# to http://127.0.0.1:9119, which a user-level SSH tunnel carries over the
# tailnet to head's loopback-only hermes-serve, as the tunnel-only
# hermes-tunnel account (modules/hosts/head/services/hermes-tunnel.nix).
#
# Per machine, once: create the tunnel key on the machine itself
#   ssh-keygen -t ed25519 -N "" -C "$(hostname)-hermes-tunnel" -f ~/.ssh/hermes_desktop_tunnel
# then add its .pub (`hermesTunnel`) and the machine's tailnet IPs to
# modules/hosts/_machines.nix, and allow the machine to tag:head:22 in the
# tailnet ACL. Needs the host's `hm` (home-manager) alias.
{
  flake.nixosModules.hermesDesktopClient =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      backend = "http://127.0.0.1:9119";
      head = (import ../../hosts/_machines.nix).head;
      keyFile = "${config.modules.system.homeDirectory}/.ssh/hermes_desktop_tunnel";

      remoteToken = pkgs.writeShellApplication {
        name = "hermes-desktop-remote-token";
        runtimeInputs = [
          pkgs.curl
          pkgs.gnused
          pkgs.coreutils
        ];
        text = builtins.readFile ./desktop-remote-token.sh;
      };

      # The token never enters the store: the launcher fetches it through the
      # tunnel at every start. Without a token the app reports it (URL set,
      # token missing) instead of starting a second agent runtime here.
      desktop = inputs.hermes-agent.packages.${system}.desktop.override {
        extraEnv.HERMES_DESKTOP_REMOTE_URL = backend;
        extraRun = [
          ''
            HERMES_DESKTOP_REMOTE_TOKEN="$(${lib.getExe remoteToken} ${backend})"
            export HERMES_DESKTOP_REMOTE_TOKEN
          ''
        ];
      };
    in
    {
      hm.home.packages = [ desktop ];

      # Same Discord-server mirror plugin as node0 (pure JS; backend half on head).
      hm.home.file.".hermes/desktop-plugins/discord-mirror/plugin.js" = {
        source = "${self.packages.${system}.hermes-discord-mirror}/desktop/plugin.js";
        force = true;
      };

      # Pinned, so the tunnel never trusts an unknown host key.
      programs.ssh.knownHosts.head = {
        hostNames = [
          "head"
          "head.tail8c2dd3.ts.net"
          head.ip
        ];
        publicKey = head.hostKey;
      };

      hm.systemd.user.services.hermes-desktop-tunnel = {
        Unit = {
          Description = "Hermes Desktop backend tunnel to head (tailnet)";
          # The key is created by hand once (see the top of this file).
          ConditionPathExists = keyFile;
        };
        Service = {
          ExecStart = ''
            ${lib.getExe pkgs.openssh} -F none -N -T \
              -i ${keyFile} \
              -o BatchMode=yes \
              -o IdentitiesOnly=yes \
              -o StrictHostKeyChecking=yes \
              -o GlobalKnownHostsFile=/etc/ssh/ssh_known_hosts \
              -o UserKnownHostsFile=/dev/null \
              -o ConnectTimeout=10 \
              -o ExitOnForwardFailure=yes \
              -o ServerAliveInterval=15 \
              -o ServerAliveCountMax=3 \
              -L 127.0.0.1:9119:127.0.0.1:9119 \
              hermes-tunnel@${head.ip}
          '';
          Restart = "always";
          RestartSec = 10;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
