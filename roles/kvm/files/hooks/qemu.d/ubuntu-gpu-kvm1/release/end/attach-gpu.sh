#!/bin/bash
set -x

# vfioを unloadする
modprobe -r vfio
modprobe -r vfio_pci
modprobe -r vfio_iommu_type1

# Host OSからGPUをattachする
virsh nodedev-reattach pci_0000_03_00_0
virsh nodedev-reattach pci_0000_03_00_1

# nvidiaのカーネルモジュールをloadする
modprobe i2c_nvidia_gpu
modprobe nvidia
modprobe nvidia_modeset
modprobe nvidia_drm
modprobe nvidia_uvm

nvidia-xconfig --query-gpu-info > /dev/null 2>&1

sleep 2

# framebuffer
echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind
