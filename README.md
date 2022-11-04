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
virt-install \
  --connect=qemu:///system \
  --name guest1-fedora36 \
  --memory 6134 \
  --vcpus 2 \
  --disk size=20 \
  --network bridge=br0 \
  --nographics \
  --cdrom /var/lib/libvirt/images/isos/fedora/Fedora-Server-dvd-x86_64-36-1.5.iso \
  --os-variant fedora-unknown \
  --extra-args "console=ttyS0 --- console=ttyS0"

# connect to guest console
virsh console guest1-fedora36
```

## install guest os with cloud-init

templated script

## change IP address in guest os

```bash
sudo nmcli connection modify enp1s0 IPv4.address 10.10.10.111/24
sudo nmcli connection modify enp1s0 IPv4.gateway 10.10.10.1
sudo nmcli connection modify enp1s0 IPv4.dns 10.10.10.1
sudo nmcli connection modify enp1s0 IPv4.method manual

sudo nmcli connection down enp1s0
sudo nmcli connection up enp1s0
```

```
sudo virsh shutdown guest1-fedora36
```
