# LUKS USB Unlocker Script
This script automates the process of setting up a USB key file to automatically unlock a LUKS-encrypted partition at boot using the passdev keyscript. It handles key generation, LUKS slot integration, and system configuration.
## Features

* Safety First: Includes a dry-run mode, automatic backup of /etc/crypttab, and a cleanup function to remove keys if the process fails.
* Validation: Checks for required dependencies (cryptsetup, findmnt, etc.) and verifies the existence of the passdev keyscript.
* Persistence: Uses device UUIDs in the configuration to ensure the system finds the correct USB drive even if its device name (e.g., /dev/sdb1) changes.
* Testing: Automatically tests the newly generated key against the LUKS volume before committing changes to the system.

## Prerequisites

* A LUKS-encrypted partition (e.g., your root or data partition).
* A USB drive formatted with a standard filesystem (EXT4, VFAT, etc.) and mounted to a directory.
* The passdev script, typically provided by packages like cryptsetup-run or cryptsetup-initramfs on Debian/Ubuntu.

## Usage

   1. Mount your USB drive to a known location (e.g., /mnt/usb).
   2. Make the script executable:
   
   `chmod +x luks_usb_setup.sh`
   
   3. Run the script as root:
   
   `sudo ./luks_usb_setup.sh`
   
   4. Follow the prompts:
   * Provide the path to your LUKS partition (e.g., /dev/nvme0n1p3).
      * Provide the USB mount point (e.g., /mnt/usb).
      * Choose whether to perform a dry run first to see the planned changes without applying them.
   
## How it Works

   1. Key Generation: Creates a 4096-bit random key file on the USB drive.
   2. LUKS Integration: Adds this key file to an available slot in your LUKS header. You will be prompted for an existing passphrase to authorize this.
   3. Crypttab Update: Configures /etc/crypttab with the keyscript=/lib/cryptsetup/scripts/passdev option, pointing to the USB device's UUID.
   4. Initramfs Update: Rebuilds the initial RAM disk so the system knows to look for the USB drive during the boot process.

## Security Warning
The USB drive acts as a physical key to your data. Anyone with physical access to this USB drive can unlock your encrypted partition. It is recommended to keep the USB drive in a secure location or carry it with you.
