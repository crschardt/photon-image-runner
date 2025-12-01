#!/bin/bash
set -euxo pipefail

####
# Clean up and shrink image
####
image="$1"
shrink="$2"

if [[ -e "${rootdir}/etc/resolv.conf.bak" ]]; then
    mv "${rootdir}/etc/resolv.conf.bak" "${rootdir}/etc/resolv.conf"
fi

if [[ -n "${bootdev}" ]]; then
    echo "Zero filling empty space on boot partition"
    (cat /dev/zero > "${rootdir}/boot/zeros" 2>/dev/null || true); sync; rm "${rootdir}/boot/zeros";
    umount "${rootdir}/boot"
fi

echo "Zero filling empty space"
(cat /dev/zero > "${rootdir}/zeros" 2>/dev/null || true); sync; rm "${rootdir}/zeros";

umount --recursive "${rootdir}"

if [[ ${shrink,,} = y* && ${rootpartition} -gt 0 ]]; then
    echo "Resizing root filesystem to minimal size."
    e2fsck -v -f -p -E discard "${rootdev}"
    resize2fs -M "${rootdev}"
    rootfs_blocksize=$(tune2fs -l ${rootdev} | grep "^Block size" | awk '{print $NF}')
    rootfs_blockcount=$(tune2fs -l ${rootdev} | grep "^Block count" | awk '{print $NF}')

    echo "Resizing rootfs partition."
    rootfs_partstart=$(parted -m --script "${loopdev}" unit B print | grep "^${rootpartition}:" | awk -F ":" '{print $2}' | tr -d 'B')
    rootfs_partsize=$((${rootfs_blockcount} * ${rootfs_blocksize}))
    rootfs_partend=$((${rootfs_partstart} + ${rootfs_partsize} - 1))
    rootfs_partoldend=$(parted -m --script "${loopdev}" unit B print | grep "^${rootpartition}:" | awk -F ":" '{print $3}' | tr -d 'B')
    if [ "$rootfs_partoldend" -gt "$rootfs_partend" ]; then
        echo y | parted ---pretend-input-tty "${loopdev}" unit B resizepart "${rootpartition}" "${rootfs_partend}"
    else
        echo "Rootfs partition not resized as it was not shrunk"
    fi

    free_space=$(parted -m --script "${loopdev}" unit B print free | tail -1)
    if [[ "${free_space}" =~ "free" ]]; then
        initial_image_size=$(stat -L --printf="%s" "${image}")
        image_size=$(echo "${free_space}" | awk -F ":" '{print $2}' | tr -d 'B')
        if [[ "${part_type}" == "gpt" ]]; then
            # for GPT partition table, leave space at the end for the secondary GPT 
            # it requires 33 sectors, which is 16896 bytes
            image_size=$((image_size + 16896))
        fi            
        echo "Shrinking image from ${initial_image_size} to ${image_size} bytes."
        truncate -s "${image_size}" "${image}"
        losetup --set-capacity "${loopdev}"
        if [[ "${part_type}" == "gpt" ]]; then
            # use sgdisk to fix the secondary GPT after truncation 
            sgdisk -e "${image}"
        fi
    fi
fi

losetup --detach "${loopdev}"