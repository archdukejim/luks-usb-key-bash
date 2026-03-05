#!/bin/bash

set -o pipefail

luks_volume="/dev/nvme0n1p3"
usb_mount="/mnt/usb"
usb_key="$usb_mount/unlock.key"

luks_volume_uuid=$(sudo blkid -s UUID -o value $luks_volume)
usb_volume_uuid=$(findmnt -no UUID --target /mnt/usb)
NEW_LINE="dm_crypt-0  UUID=$luks_volume_uuid  /dev/disk/by-uuid/$usb_volume_uuid:/unlock.key  luks,keyscript=/lib/cryptsetup/scripts/passdev"

sudo cryptsetup luksDump $luks_volume

sudo dd if=/dev/urandom of=$usb_key bs=512 count=8

sudo cryptsetup luksAddKey $luks_volume $usb_key

sudo cryptsetup luksDump $luks_volume

sudo chmod 0400 $usb_key

sudo cryptsetup open --test-passphrase $luks_volume --key-file $usb_key -v

sudo sed -i "s|^dm_crypt-0.*|$NEW_LINE|" /etc/crypttab

sudo update-initramfs -u
