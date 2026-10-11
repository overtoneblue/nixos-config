{ self, inputs, ... }:
{
  flake.nixosModules.callistoConfiguration =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      # `sudo callisto-rebuild` (modules/system/rebuild.nix). Webhook file is
      # placed by hand like node0; absent file = no notifications.
      modules.system.rebuild = {
        command = "callisto-rebuild";
        webhookFile = "${config.modules.system.homeDirectory}/.config/nixos-rebuild/discord-webhook";
      };

      imports = [
        self.nixosModules.options
        self.nixosModules.rebuild
        ./_system.nix
        self.nixosModules.callistoHardware
        self.nixosModules.base
        self.nixosModules.nix-settings
        self.nixosModules.network
        self.nixosModules.tailscale
        self.nixosModules.sound
        inputs.home-manager.nixosModules.home-manager
        (lib.mkAliasOptionModule [ "hm" ] [ "home-manager" "users" config.modules.system.username ])
        self.nixosModules.theme
        self.nixosModules.dev
        self.nixosModules.desktop
        # Deliberately absent: ai (CUDA ComfyUI), hermes (node0 computer-use).
      ];

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      hm.home.stateVersion = "25.11";

      # Same list as node0; modules.programs.desktopApps.enable = false (see
      # _system.nix) drops the heavy groups, leaving desktop + system.
      modules.packages.groups = [
        "media"
        "comms"
        "apps"
        "desktop"
        "gaming"
        "system"
      ];

      # ------------------------------------------------------------------
      # Boot — copied verbatim from NixLand hosts/callisto/default.nix.
      # The X13s is finicky: do not "modernise" this (nixos-hardware,
      # systemd-boot, different kernel) without a rollback plan.
      # ------------------------------------------------------------------
      boot = {
        loader.grub = {
          enable = true;
          efiSupport = true;
          efiInstallAsRemovable = true;
          device = "nodev";
          extraFiles = {
            "devicetree.dtb" =
              "${config.boot.kernelPackages.kernel}/dtbs/qcom/sc8280xp-lenovo-thinkpad-x13s.dtb";
          };
          extraPerEntryConfig = "devicetree ($drive1)//devicetree.dtb";
          extraConfig = ''
            terminal_input console
            terminal_output gfxterm
          '';
        };
        #loader.efi.canTouchEfiVariables = true;
        loader.efi.efiSysMountPoint = "/boot";

        kernelPackages = pkgs.linuxPackages_latest;
        kernelParams = [
          "efi=novamap,noruntime"
          "clk_ignore_unused"
          "pd_ignore_unused"
          "arm64.nopauth"
          "iommu.passthrough=0"
          "iommu.strict=0"
          "pcie_aspm.policy=powersupersave"
          "root=PARTUUID=89578242-4aef-8e4f-8ecc-99829a0611c8"
          #"dtb=${config.boot.kernelPackages.kernel}/dtbs/qcom/${dtbname}"
        ];
        initrd = {
          includeDefaultModules = false;
          availableKernelModules = [
            "nvme"
            "phy_qcom_qmp_pcie"
            # "pcie_qcom"
            "i2c_hid_of"
            "i2c_qcom_geni"
            "leds_qcom_lpg"
            "pwm_bl"
            "qrtr"
            "pmic_glink_altmode"
            "gpio_sbu_mux"
            "phy_qcom_qmp_combo"
            "panel-edp"
            "msm"
            "phy_qcom_edp"
            "v4l2_mem2mem"
            "venus_core"
            "venus_dec"
            "venus_enc"
          ];
        };
      };

      hardware = {
        # enableRedistributableFirmware = true;
        # firmwareCompression = "none";
        # firmware = [ pkgs.linux-firmware ];
        deviceTree.enable = true;
      };

      # armlaptop bits NixLand applied via core/ (audio.nix, misc.nix):
      # X13s audio needs the ALSA UCM profiles; upower for battery state.
      environment.systemPackages = [ pkgs.alsa-ucm-conf ];
      services.upower.enable = true;

      # ------------------------------------------------------------------
      # User: overtoneblue replaces NixLand's cenunix. With mutable users the
      # old cenunix account is dropped on first switch; /home/cenunix stays.
      # initialPassword only applies when the account is first created —
      # change it immediately (passwd) after the first boot.
      # ------------------------------------------------------------------
      users.users.${config.modules.system.username}.initialPassword = "changeme";

      services.greetd = {
        enable = true;
        settings.default_session = {
          user = "greeter";
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --cmd '${lib.getExe config.programs.uwsm.package} start -eD Hyprland:GNOME -- hyprland.desktop'";
        };
      };

      services.openssh = {
        enable = true;
        openFirewall = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      networking.hostName = "callisto";

      # NixLand set this for every host (hosts/shared).
      time.hardwareClockInLocalTime = true;

      # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
      system.stateVersion = "24.11";
    };
}
