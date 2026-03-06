#!/bin/bash

# Exit on any command failure within a pipeline
set -o pipefail

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo or as root."
   exit 1
fi

# Cleanup function to remove the key file if the script fails midway
cleanup() {
    if [ -f "$usb_key" ] && [ "$key_added" != "true" ]; then
        echo "Cleaning up temporary key file: $usb_key"
        rm -f "$usb_key"
    fi
}
trap cleanup EXIT

# Validation: Check for required binary dependencies
for cmd in cryptsetup findmnt blkid dd sed update-initramfs; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed."
        exit 1
    fi
done

# Timeout for prompts (in seconds)
T_OUT=60

# Prompt user for the LUKS partition and USB mount point with timeouts
if ! read -t $T_OUT -p "Enter the LUKS partition (e.g., /dev/nvme0n1p3): " luks_volume; then
    echo -e "\nError: Input timeout reached."
    exit 1
fi

if ! read -t $T_OUT -p "Enter the USB mount point (e.g., /mnt/usb): " usb_mount; then
    echo -e "\nError: Input timeout reached."
    exit 1
fi

if ! read -t $T_OUT -p "Dry run? (y/n): " dry_run; then
    dry_run="n"
fi

# Validation: Check if the passdev keyscript exists (required for boot-time USB unlocking)
if [ ! -f "/lib/cryptsetup/scripts/passdev" ]; then
    echo "Error: /lib/cryptsetup/scripts/passdev not found. Install 'cryptsetup-run' or 'cryptsetup-initramfs'."
    exit 1
fi

# Validation: Check if the USB mount point exists and is a directory
if [ ! -d "$usb_mount" ]; then
    echo "Error: Mount point $usb_mount does not exist or is not a directory."
    exit 1
fi

# Validation: Check if the USB is actually mounted
if ! findmnt --target "$usb_mount" > /dev/null; then
    echo "Error: Nothing is mounted at $usb_mount."
    exit 1
fi

usb_key="$usb_mount/unlock.key"
key_added="false"

# Retrieve UUIDs for the LUKS volume and the USB device
luks_volume_uuid=$(blkid -s UUID -o value "$luks_volume")
usb_volume_uuid=$(findmnt -no UUID --target "$usb_mount")

# Define the new entry for /etc/crypttab using the passdev keyscript
NEW_LINE="dm_crypt-0  UUID=$luks_volume_uuid  /dev/disk/by-uuid/$usb_volume_uuid:/unlock.key  luks,keyscript=/lib/cryptsetup/scripts/passdev"

if [[ "$dry_run" =~ ^[Yy]$ ]]; then
    echo -e "\n--- DRY RUN SUMMARY (No changes made) ---"
    echo "Target LUKS:     $luks_volume (UUID: $luks_volume_uuid)"
    echo "Target USB:      $usb_mount (UUID: $usb_volume_uuid)"
    echo "Key to create:   $usb_key"
    echo "Keyscript:       /lib/cryptsetup/scripts/passdev (Verified)"
    echo "Crypttab entry:  $NEW_LINE"
    echo "------------------------------------------"
    exit 0
fi

# Backup /etc/crypttab before modification
echo "Backing up /etc/crypttab to /etc/crypttab.bak"
cp /etc/crypttab /etc/crypttab.bak

# Display current LUKS header information
cryptsetup luksDump "$luks_volume"

# Generate a 4096-bit random key file on the USB drive
dd if=/dev/urandom of="$usb_key" bs=512 count=8

# Add the new key file to an available LUKS slot (requires existing passphrase)
if cryptsetup luksAddKey "$luks_volume" "$usb_key"; then
    key_added="true"
else
    echo "Error: Failed to add key to LUKS volume."
    exit 1
fi

# Verify the key slot was successfully added
cryptsetup luksDump "$luks_volume"

# Restrict permissions on the key file
chmod 0400 "$usb_key"

# Test that the key file actually unlocks the volume
cryptsetup open --test-passphrase "$luks_volume" --key-file "$usb_key" -v

# Final confirmation before permanent system changes
echo -e "\n--- FINAL WARNING ---"
echo "The script is about to modify /etc/crypttab and rebuild your initramfs."
echo "New entry: $NEW_LINE"
if ! read -t $T_OUT -p "Apply these changes to the system? (y/n): " confirm || [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\nAborting before system modification."
    exit 1
fi

# Update /etc/crypttab with the new configuration
sed -i "s|^dm_crypt-0.*|$NEW_LINE|" /etc/crypttab

# Rebuild initramfs to include the changes for boot-time unlocking
update-initramfs -u

# Final Summary
echo -e "\n--- Configuration Summary ---"
echo "LUKS Volume:      $luks_volume (UUID: $luks_volume_uuid)"
echo "USB Mount Point:  $usb_mount (UUID: $usb_volume_uuid)"
echo "Key File Path:    $usb_key"
echo "Crypttab Entry:   $NEW_LINE"
echo "Backup Created:   /etc/crypttab.bak"
echo "-----------------------------"
echo "Setup complete. Please ensure your USB is plugged in during the next boot."
