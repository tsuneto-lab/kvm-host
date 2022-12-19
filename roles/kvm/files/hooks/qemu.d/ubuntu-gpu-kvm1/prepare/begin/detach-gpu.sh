#!/bin/bash
set -x

# フレームバッファも止める
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

# nvidiaのカーネルモジュールをunloadする
modprobe -r nvidia_uvm
modprobe -r nvidia_drm
modprobe -r nvidia_modeset
modprobe -r nvidia
modprobe -r i2c_nvidia_gpu

sleep 2

# Host OSからGPUをdetachする
virsh nodedev-detach pci_0000_03_00_0
virsh nodedev-detach pci_0000_03_00_1

#  vfio をロードする
modprobe vfio
modprobe vfio_pci
modprobe vfio_iommu_type1
