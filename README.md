## play

```bash
# activate venv
source ../ansible-venv/bin/activate

ssh-copy-id -i ~/.ssh/id_rsa_home  ubuntu@kvm1
# first time. --limit option would be helpful.
ansible-playbook -Ki inventory/hosts.yml main.yml
# K prompts for sudo password

ansible-playbook -i inventory/hosts.yml main.yml
```

## put guest os image

```bash
wget https://download.fedoraproject.org/pub/fedora/linux/releases/36/Server/x86_64/iso/Fedora-Server-dvd-x86_64-36-1.5.iso
mkdir -p /var/lib/libvirt/images/isos/fedora/
mv Fedora-Server-dvd-x86_64-36-1.5.iso /var/lib/libvirt/images/isos/fedora/
sudo chown -R libvirt-qemu:kvm /var/lib/libvirt/images/isos/ # not completely sure about the owner
```

## install guest os with cloud-init

templated script

```
./cloud-init/centos-vm1/install.sh
./cloud-init/centos-vm2/install.sh
./cloud-init/centos-vm3/install.sh
./cloud-init/centos-vm4/install.sh
./cloud-init/centos-vm5/install.sh
./cloud-init/centos-vm6/install.sh
```

## resize disk

```bash
virsh shutdown fedora-vm1
# qemu-img resize -f raw /var/lib/libvirt/images/fedora-vm1.raw 10G
# or resize it using this playbook
virsh start fedora-vm1

# cloud images usually automatically expands volumes
# ssh kvm-user@fedora-vm1
# sudo lsblk
# df
```

## clean up

```
./cloud-init/centos-vm1/destroy.sh
```

## guests

```bash
source ../ansible-venv/bin/activate

ansible-playbook -i guests/hosts.yml k8s-nodes.yml
```

## windows

```
<-- after </features> -->
<-- replace cpu -->
<cpu mode='host-passthrough' check='none'>
  <topology sockets='1' cores='8' threads='1'/>
</cpu>

virsh # qemu-monitor-command <domain> --hmp change  vnc :5
qemu-monitor-command <domain> --hmp change  vnc none
```

## pci passthrough

set pci id to install script (hard coded for windows ATM)

```bash
lspci | grep NVIDIA
# 03:00.0 VGA compatible controller: NVIDIA Corporation GT215 [GeForce GT 240] (rev a2)
# 03:00.1 Audio device: NVIDIA Corporation High Definition Audio Controller (rev a1)
# virsh nodedev-list --cap pci

virsh nodedev-dumpxml pci_0000_03_00_0
# => xml for GeForce GT 240 check iommu group
virsh nodedev-dumpxml pci_0000_03_00_1
# => xml for a device in same iommu group
```

install with `--host-device=pci_0000_03_00_0`
or edit exiting vm as follows

```xml
# virsh edit windows-vm1
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
     <address domain='0' bus='3' slot='0' function='0'/>
  </source>
</hostdev>
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
     <address domain='0' bus='3' slot='0' function='1'/>
  </source>
</hostdev>
```

virsh start windows-vm1
