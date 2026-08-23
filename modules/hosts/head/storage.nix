{ ... }:
{
  flake.nixosModules.headStorage =
    { ... }:
    {
      # Disk numbers follow the verified inventory order and are pinned by UUID:
      # disk1 = ZVTB4QKW, disk2 = ZVTB4S0J, disk3 = ZVTAZ81M.
      fileSystems."/mnt/disk1" = {
        device = "/dev/disk/by-uuid/e714b3ee-c168-43bb-b84b-9d0d821599e3";
        fsType = "xfs";
      };

      fileSystems."/mnt/disk2" = {
        device = "/dev/disk/by-uuid/cf60661c-0fec-45f0-b770-0fd56b5aa590";
        fsType = "xfs";
      };

      fileSystems."/mnt/disk3" = {
        device = "/dev/disk/by-uuid/bb08a598-e2d9-442d-9a4f-475a72c86867";
        fsType = "xfs";
      };

      fileSystems."/mnt/user" = {
        device = "/mnt/disk1:/mnt/disk2:/mnt/disk3";
        fsType = "fuse.mergerfs";
        depends = [
          "/mnt/disk1"
          "/mnt/disk2"
          "/mnt/disk3"
        ];
        options = [
          "allow_other"
          "cache.files=off"
          "category.action=epall"
          "category.create=mspmfs"
          "category.search=ff"
          "func.getattr=newest"
          "dropcacheonclose=false"
          "minfreespace=10G"
          "branches-mount-timeout=30"
          "branches-mount-timeout-fail=true"
          "x-systemd.mount-timeout=60s"
        ];
      };
    };
}
