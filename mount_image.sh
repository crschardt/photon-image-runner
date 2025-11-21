#!/bin/bash
set -euo pipefail

image="$1"
additional_mb=$2
rootpartition=$3
echo "rootpartition=${rootpartition}" >> "$GITHUB_ENV"

####
# Prepare and mount the image
####

if [[ ${additional_mb} -gt 0 ]]; then
    dd if=/dev/zero bs=1M count=${additional_mb} >> ${image}
fi

loopdev=$(losetup --find --show --partscan ${image})
echo "loopdev=${loopdev}" >> "$GITHUB_ENV"

part_type=$(blkid -o value -s PTTYPE "${loopdev}")
echo "Image is using ${part_type} partition table"

if [[ ${additional_mb} -gt 0 ]]; then
    echo "Resizing the disk image by ${additional_mb}MB"
    if [[ "${part_type}" == "gpt" ]]; then
        sgdisk --move-second-header "${loopdev}"
    fi
    parted --script "${loopdev}" resizepart ${rootpartition} 100%
    e2fsck -p -f "${loopdev}p${rootpartition}"
    resize2fs "${loopdev}p${rootpartition}"
    echo "Finished resizing disk image."
fi

sync

echo "Partitions in the mounted image:"
lsblk "${loopdev}"

rootdev="${loopdev}p${rootpartition}"
echo "rootdev=${rootdev}" >> "$GITHUB_ENV"
echo "Root device is: ${rootdev}"

rootdir="./rootfs"
rootdir="$(realpath ${rootdir})"

mkdir --parents ${rootdir}
mount "${rootdev}" "${rootdir}"
echo "rootdir=${rootdir}" >> "$GITHUB_ENV"
echo "Root directory is: ${rootdir}"

# Set up the environment
mount -t proc /proc "${rootdir}/proc"
mount -t sysfs /sys "${rootdir}/sys"
mount --rbind /dev "${rootdir}/dev"

# Temporarily replace resolv.conf for networking
mv -v "${rootdir}/etc/resolv.conf" "${rootdir}/etc/resolv.conf.bak"
cp -v /etc/resolv.conf "${rootdir}/etc/resolv.conf"
