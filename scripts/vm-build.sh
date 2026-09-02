#!/bin/bash
# Build the assets for an unattended Omarchy VM on the test laptop: a 40G disk, UEFI vars, and a
# `cidata` drive carrying the installer's answer files (the ISO installs itself when it finds one).
# Mirrors omacom/omarchy-iso: configurator full-disk template + bin/omarchy-iso-test QEMU layout.
set -euo pipefail
VM="${VM_DIR:-$HOME/vm}"; ISO="$VM/omarchy-4.0.2.iso"
USER_NAME="${VM_USER:-kid-vm}"; PASS="${VM_PASS:-omarchy}"; HOST="${VM_HOST:-kids-vm}"
TZ_NAME="${VM_TZ:-America/New_York}"; ENCRYPT="${VM_ENCRYPT:-true}"; SIZE_GB="${VM_SIZE_GB:-40}"
PUBKEY="${VM_PUBKEY:-$(cat "$HOME/.ssh/authorized_keys" 2>/dev/null | head -1)}"
[[ -f $ISO ]] || { echo "missing $ISO"; exit 1; }
mkdir -p "$VM/cidata"; cd "$VM"
[[ -f disk.qcow2 ]] || qemu-img create -f qcow2 disk.qcow2 "${SIZE_GB}G" >/dev/null
[[ -f OVMF_VARS.fd ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd OVMF_VARS.fd
# Partition math, byte for byte the configurator's: 2 GiB ESP at 1 MiB, root fills the rest.
disk=$((SIZE_GB * 1024 * 1024 * 1024)); mib=$((1024*1024))
boot_start=$mib; boot_size=$((2*1024*mib)); main_start=$((boot_start+boot_size)); main_size=$((disk-main_start-mib))
hash=$(openssl passwd -6 "$PASS")
enc_block=""; enc_pw_line=""
if [[ $ENCRYPT == true ]]; then
  enc_pw_line=", \"encryption_password\": $(printf '%s' "$PASS" | jq -Rsa)"
  enc_block=$(cat <<_EOF_
,
        "disk_encryption": { "encryption_type": "luks", "lvm_volumes": [], "iter_time": 2000,
            "partitions": [ "8c2c2b92-1070-455d-b76a-56263bab24aa" ]$enc_pw_line }
_EOF_
)
fi
cat > cidata/user_configuration.json <<_EOF_
{
    "app_config": null, "archinstall-language": "English", "auth_config": {},
    "audio_config": { "audio": "pipewire" },
    "bootloader_config": { "bootloader": "Limine", "uki": false, "removable": false },
    "custom_commands": [],
    "omarchy_install": { "mode": "full_disk", "defer_provisioning": false, "target_mount": "/mnt",
        "boot": { "esp_mount": "/boot", "esp_path": "/EFI/limine", "efi_binary": "limine_x64.efi", "enable_fallback": true },
        "storage": { "kernel": "linux" } },
    "disk_config": { "config_type": "default_layout", "device_modifications": [ { "device": "/dev/vda", "partitions": [
        { "btrfs": [], "dev_path": null, "flags": [ "boot", "esp" ], "fs_type": "fat32", "mount_options": [], "mountpoint": "/boot",
          "obj_id": "ea21d3f2-82bb-49cc-ab5d-6f81ae94e18d",
          "size": { "sector_size": { "unit": "B", "value": 512 }, "unit": "B", "value": $boot_size },
          "start": { "sector_size": { "unit": "B", "value": 512 }, "unit": "B", "value": $boot_start },
          "status": "create", "type": "primary" },
        { "btrfs": [ { "mountpoint": "/", "name": "@" }, { "mountpoint": "/home", "name": "@home" },
                     { "mountpoint": "/var/log", "name": "@log" }, { "mountpoint": "/var/cache/pacman/pkg", "name": "@pkg" } ],
          "dev_path": null, "flags": [], "fs_type": "btrfs", "mount_options": [ "compress=zstd" ], "mountpoint": null,
          "obj_id": "8c2c2b92-1070-455d-b76a-56263bab24aa",
          "size": { "sector_size": { "unit": "B", "value": 512 }, "unit": "B", "value": $main_size },
          "start": { "sector_size": { "unit": "B", "value": 512 }, "unit": "B", "value": $main_start },
          "status": "create", "type": "primary" } ], "wipe": true } ]$enc_block },
    "hostname": "$HOST", "kernels": [ "linux" ], "network_config": { "type": "iso" }, "ntp": true,
    "parallel_downloads": 8, "script": null, "services": [], "swap": true, "timezone": "$TZ_NAME",
    "locale_config": { "kb_layout": "us", "sys_enc": "UTF-8", "sys_lang": "en_US.UTF-8" },
    "mirror_config": { "custom_repositories": [], "custom_servers": [
        {"url": "https://mirror.omarchy.org/\$repo/os/\$arch"},
        {"url": "https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"},
        {"url": "https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"} ], "mirror_regions": {}, "optional_repositories": [] },
    "packages": [ "base-devel", "git", "omarchy-keyring", "omarchy-settings", "omarchy" ],
    "profile_config": { "gfx_driver": null, "greeter": null, "profile": {} },
    "version": "3.0.9"
}
_EOF_
cat > cidata/user_credentials.json <<_EOF_
{
    $( [[ $ENCRYPT == true ]] && printf '"encryption_password": %s,' "$(printf '%s' "$PASS" | jq -Rsa)" )
    "root_enc_password": $(printf '%s' "$hash" | jq -Rsa),
    "users": [ { "enc_password": $(printf '%s' "$hash" | jq -Rsa), "groups": [], "sudo": true, "username": $(printf '%s' "$USER_NAME" | jq -Rsa) } ]
}
_EOF_
echo "Kid VM" > cidata/user_full_name.txt; echo "kids@example.test" > cidata/user_email_address.txt
echo "$ENCRYPT" > cidata/user_encrypt_installation.txt
[[ -n $PUBKEY ]] && echo "$PUBKEY" > cidata/authorized_keys
jq . cidata/user_configuration.json >/dev/null && jq . cidata/user_credentials.json >/dev/null && echo "answer files valid"
rm -f cidata.img; truncate -s 8M cidata.img; mkfs.fat -n cidata cidata.img >/dev/null
for f in cidata/*; do mcopy -i cidata.img "$f" ::/; done
echo "built: $VM/{disk.qcow2,OVMF_VARS.fd,cidata.img}  user=$USER_NAME host=$HOST encrypted=$ENCRYPT"
