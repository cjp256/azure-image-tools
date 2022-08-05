#!/bin/bash

# Create Fedora VHD and upload for use in Azure.
#
# NOTES:
# - Creates image as QCOW2 and converts to VHD afterwards.
# - Ensure that kickstart has "poweroff" instead of "reboot" flag otherwise
#   VM will endlessly reboot & reinstall.
# - Fedora installer is configured to use text mode and it uses tmux.
#   Use ctrl+b+1/2/3 to switch between screens once anaconda launches.
#

set -eux -o pipefail

timestamp="$(date +%Y%m%d%H%M%S)"
qcow2="f36-azure-$timestamp.qcow2"
vhd="f36-azure-$timestamp.vhd"
size="4G"
iso="/home/cpatterson/iso/Fedora-Server-netinst-x86_64-36-1.5.iso"
mnt="tmp-mnt-iso"
ks="https://pagure.io/fork/cjp256/fedora-kickstarts/raw/azure-cloud/f/fedora-cloud-base-azure-flattened.ks"
rg="cpatterson-eastus-rg"
region="eastus"
storage_account="fedoraimages"
container="fedoraimages"
blob_name="$(basename "$vhd")"
sku="Standard_LRS"

mkdir -p "$mnt"
sudo mount -o loop "$iso" "$mnt"

qemu-img create -f qcow2 "$qcow2" "$size"

kvm -cpu host \
  -cdrom "$iso" \
  -drive "file=$qcow2,if=virtio,format=qcow2" \
  -net nic -net user \
  -m 4G \
  -kernel "$mnt/images/pxeboot/vmlinuz" \
  -initrd "$mnt/images/pxeboot/initrd.img" \
  -append "inst.headless inst.loglevel=debug inst.ks=$ks inst.repo=cdrom console=ttyS0" \
  -nographic -serial mon:stdio

sudo umount "$mnt"
sudo rmdir "$mnt"

qemu-img convert -o subformat=fixed,force_size -O vpc "$qcow2" "$vhd"
rm "$qcow2"

az storage account create --resource-group "$rg" --name "$storage_account" --location "$region" --sku "$sku"
az storage container create --account-name "$storage_account" --name "$container"
az storage blob upload -f "$vhd" --account-name "$storage_account" --container "$container" --name "$blob_name" --type page

url="$(az storage blob url \
         --account-name "$storage_account" \
         --container "$container" \
         --name "$blob_name" | sed 's|"||g')"

az image create --resource-group "$rg" --name "$vhd" --location "$region" --os-type Linux --source "$url"
rm "$vhd"
