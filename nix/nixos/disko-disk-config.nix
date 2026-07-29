{ config, lib, ... }:

let
  firmwarePartition = lib.recursiveUpdate {
    # label = "FIRMWARE";
    priority = 1;

    type = "0700"; # Microsoft basic data
    attributes = [
      0 # Required Partition
    ];

    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      # mountpoint = "/boot/firmware";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  espPartition = lib.recursiveUpdate {
    # label = "ESP";

    type = "EF00"; # EFI System Partition (ESP)
    attributes = [
      2 # Legacy BIOS Bootable, for U-Boot to find extlinux config
    ];

    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      # mountpoint = "/boot";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
        "umask=0077"
      ];
    };
  };

in
{

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  # networking.hostId is set somewhere else
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  disko.devices = {
    disk.nvme0 = {
      type = "disk";
      device = "/dev/nvme0n1";
      # Only used when building a flashable .raw image via
      # `disko.devices.disk.nvme0.imageName`/`system.build.diskoImages`
      # (nix build .#nixosConfigurations.flybrain-rpi5.config.system.build.diskoImages).
      # Not used for a live install (e.g. via nixos-anywhere), where disko
      # partitions the real device and "100%" below means the whole disk.
      # Keep this comfortably under your NVMe's real capacity (a "500GB"
      # drive is usually ~465 GiB usable) and bump it if the build fails
      # because the image is too small.
      imageSize = "440G";
      content = {
        type = "gpt";
        partitions = {

          FIRMWARE = firmwarePartition {
            label = "FIRMWARE";
            content.mountpoint = "/boot/firmware";
          };

          ESP = espPartition {
            label = "ESP";
            content.mountpoint = "/boot";
          };

          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool"; # zroot
            };
          };

        };
      };
    }; # nvme0

    zpool = {
      rpool = {
        type = "zpool";

        # zpool properties
        options = {
          ashift = "12";
          autotrim = "on"; # see also services.zfs.trim.enable
        };

        # zfs properties
        rootFsOptions = {
          # "com.sun:auto-snapshot" = "false";
          # https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/
          compression = "lz4";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          # https://rubenerd.com/forgetting-to-set-utf-normalisation-on-a-zfs-pool/
          normalization = "formD";
          dnodesize = "auto";
          mountpoint = "none";
          canmount = "off";
        };

        postCreateHook =
          let
            poolName = "rpool";
          in
          "zfs list -t snapshot -H -o name | grep -E '^${poolName}@blank$' || zfs snapshot ${poolName}@blank";

        datasets = {

          # stuff which can be recomputed/easily redownloaded, e.g. nix store
          local = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          "local/nix" = {
            type = "zfs_fs";
            options = {
              reservation = "128M";
              mountpoint = "legacy"; # to manage "with traditional tools"
            };
            mountpoint = "/nix"; # nixos configuration mountpoint
          };

          # _system_ data
          system = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
            };
          };
          "system/root" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/";
          };
          "system/var" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/var";
          };

          # _user_ and _user service_ data. safest, long retention policy
          safe = {
            type = "zfs_fs";
            options = {
              copies = "2";
              mountpoint = "none";
            };
          };
          "safe/home" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/home";
          };
          "safe/var/lib" = {
            type = "zfs_fs";
            options = {
              mountpoint = "legacy";
            };
            mountpoint = "/var/lib";
          };

        };
      };
    };
  };
}
