#!/bin/bash
set -euo pipefail

image="$1"
additional_mb=$2
minimum_free=$3
rootpartition=$4
echo "rootpartition=${rootpartition}" >> "$GITHUB_ENV"

####
# Prepare and mount the image
####

loopdev=$(losetup --find --show --partscan ${image})
echo "loopdev=${loopdev}" >> "$GITHUB_ENV"

echo "Partitions in the mounted image:"
lsblk "${loopdev}"

part_type=$(blkid -o value -s PTTYPE "${loopdev}")
echo "part_type=${part_type}" >> "$GITHUB_ENV"
echo "Image is using ${part_type} partition table"

rootdev="${loopdev}p${rootpartition}"
echo "rootdev=${rootdev}" >> "$GITHUB_ENV"
echo "Root device is: ${rootdev}"

rootdir="./rootfs"
rootdir="$(realpath ${rootdir})"
mkdir --parents ${rootdir}

if [[ ${minimum_free} -gt 0 ]]; then
    mount "${rootdev}" "${rootdir}"
    echo "Space in root directory:"
    df --block-size=M "${rootdir}"
    free=$( df --block-size=$((1024*1024)) --output=avail "${rootdir}" |  tail -n1)
    umount "${rootdir}"
    need=$(( ${minimum_free} - ${free} ))
    if [[ ${additional_mb} -lt ${need} ]]; then
        additional_mb=${need}
    fi
fi

if [[ ${additional_mb} -gt 0 ]]; then
    echo "Resizing the disk image by ${additional_mb}MB"
    dd if=/dev/zero bs=1M count=${additional_mb} >> ${image}
    losetup --set-capacity ${loopdev}
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

mount "${rootdev}" "${rootdir}"
echo "rootdir=${rootdir}" >> "$GITHUB_ENV"
echo "Root directory is: ${rootdir}"

echo "Space in root directory:"
df --block-size=M "${rootdir}"

# Set up the environment
mount -t proc /proc "${rootdir}/proc"
mount -t sysfs /sys "${rootdir}/sys"
mount --rbind /dev "${rootdir}/dev"

# Temporarily replace resolv.conf for networking
mv -v "${rootdir}/etc/resolv.conf" "${rootdir}/etc/resolv.conf.bak"
cp -v /etc/resolv.conf "${rootdir}/etc/resolv.conf"
