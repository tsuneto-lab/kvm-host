## play

```bash
# activate venv
source ../ansible-venv/bin/activate

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

## install guest os

```bash
# kvm-user@kvm1
./

# connect to guest console
virsh console guest1-fedora36
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

## change IP address in guest os (old)

using cloud-init instead.

```bash
sudo nmcli connection modify enp1s0 IPv4.address 10.10.10.111/24
sudo nmcli connection modify enp1s0 IPv4.gateway 10.10.10.1
sudo nmcli connection modify enp1s0 IPv4.dns 10.10.10.1
sudo nmcli connection modify enp1s0 IPv4.method manual

sudo nmcli connection down enp1s0
sudo nmcli connection up enp1s0
```

## resize disk

```bash
virsh shutdown fedora-vm1
qemu-img resize -f raw /var/lib/libvirt/images/fedora-vm1.raw 10G
virsh start fedora-vm1

ssh kvm-user@fedora-vm1
sudo lsblk
df
```

## clean up

```
./cloud-init/centos-vm1/destroy.sh
```

### old

```
virsh shutdown fedora-vm1
virsh undefine fedora-vm1
rm /var/lib/libvirt/images/fedora-vm1.raw
```

```bash
# local
ssh-keygen -R 10.10.10.111
```

## guests

```bash
source ../ansible-venv/bin/activate

ansible-playbook -i guests/hosts.yml k8s-nodes.yml
```
