# Operating notes

This is the original README, the runbook the author kept while running the lab in 2022-2023. It is kept as it
was, apart from this note, the redactions made before publication (issue #3), and the `lspci` sample below. The paths
`./cloud-init/<vm>/install.sh` and `./windows/<vm>/install.sh` are relative to the KVM user's home directory on the
host, where the `kvm` role generates those scripts. For what the repository is, start at the
[README](../README.md).

## Manual

1. Install Ubuntu with static IP
2. `ssh-copy-id -i ~/.ssh/id_rsa_home ubuntu@ubuntu`
3. ssh into the machine and extend root fs if needed

```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

## play

```bash
# activate venv
source ../ansible-venv/bin/activate

ssh-copy-id -i ~/.ssh/id_rsa_home  ubuntu@kvm1
# first time. --limit option would be helpful. also, you might need to edit .ssh/config
ansible-playbook -Ki inventory/hosts.yml main.yml
# K prompts for sudo password

ansible-playbook -i inventory/hosts.yml main.yml
```

Before running, replace `inventory/group_vars/all.yml` `ssh_authorized_keys` example key with your own public key and set `kvm_windows_vnc_pass` (for example in host/group vars or `--extra-vars`) so Windows VM provisioning does not use an in-repo default.

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
# Illustrative, not captured output. The card was a GeForce RTX 3060 (10de:2504) at 03:00.0,
# with its HDMI audio function (10de:228e) at 03:00.1.
# 03:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060 Lite Hash Rate]
# 03:00.1 Audio device: NVIDIA Corporation GA106 High Definition Audio Controller
# virsh nodedev-list --cap pci

virsh nodedev-dumpxml pci_0000_03_00_0
# => xml for the GPU, check iommu group
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

VNC here was reachable on the LAN only; if you reuse this, bind VNC to localhost and access it through an SSH tunnel.

```xml
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0' passwd='REPLACE_WITH_STRONG_PASSWORD'>
      <listen type='address' address='0.0.0.0'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
    </video>
```
