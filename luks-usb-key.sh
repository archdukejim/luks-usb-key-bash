#!/bin/bash

# Exit on any command failure within a pipeline
set -o pipefail

# Prompt user for the LUKS partition and USB mount point
read -p "Enter the LUKS partition (e.g., /dev/nvme0n1p3): " luks_volume
read -p "Enter the USB mount point (e.g., /mnt/usb): " usb_mount

# Validation: Check if the USB mount point exists and is a directory
if [ ! -d "$usb_mount" ]; then
    echo "Error: Mount point $usb_mount does not exist or is not a directory."
    exit 1
fi

# Validation: Check if the USB is actually mounted (required for findmnt)
if ! findmnt --target "$usb_mount" > /dev/null; then
    echo "Error: Nothing is mounted at $usb_mount."
    exit 1
fi

usb_key="$usb_mount/unlock.key"

# Retrieve UUIDs for the LUKS volume and the USB device
luks_volume_uuid=$(sudo blkid -s UUID -o value "$luks_volume")
usb_volume_uuid=$(findmnt -no UUID --target "$usb_mount")

# Define the new entry for /etc/crypttab using the passdev keyscript
NEW_LINE="dm_crypt-0  UUID=$luks_volume_uuid  /dev/disk/by-uuid/$usb_volume_uuid:/unlock.key  luks,keyscript=/lib/cryptsetup/scripts/passdev"

# Display current LUKS header information
sudo cryptsetup luksDump "$luks_volume"

# Generate a 4096-bit random key file on the USB drive
sudo dd if=/dev/urandom of="$usb_key" bs=512 count=8

# Add the new key file to an available LUKS slot (requires existing passphrase)
sudo cryptsetup luksAddKey "$luks_volume" "$usb_key"

# Verify the key slot was successfully added
sudo cryptsetup luksDump "$luks_volume"

# Restrict permissions on the key file
sudo chmod 0400 "$usb_key"

# Test that the key file actually unlocks the volume
sudo cryptsetup open --test-passphrase "$luks_volume" --key-file "$usb_key" -v

# Update /etc/crypttab with the new configuration
sudo sed -i "s|^dm_crypt-0.*|$NEW_LINE|" /etc/crypttab

# Rebuild initramfs to include the changes for boot-time unlocking
sudo update-initramfs -u
