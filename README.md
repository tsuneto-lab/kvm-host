# kvm-host

A home lab built between November 2022 and January 2023, and no longer operated. This repository holds the Ansible
that built two machines: a KVM host (`kvm1`) with its guests, and a GPU machine (`ubuntu-gpu`).

Five CentOS guests ran a Kubernetes cluster. Two other guests, one Linux and one Windows, received the host's GPU
through VFIO passthrough, and that is the part most worth reading.

## GPU passthrough

The host `kvm1` had an NVIDIA GeForce RTX 3060 (PCI IDs `10de:2504` for the GPU, `10de:228e` for its HDMI audio
function) at PCI address `03:00`. The host also had the NVIDIA driver installed, so the card was not reserved for
guests at boot. Instead, it was taken away from the host each time a GPU guest started, and given back when the
guest stopped.

`kvm1` was an Intel X79 workstation board with a server CPU. That comes from the author's memory, and the code
agrees: the IOMMU flag is Intel's, and the USB controllers passed to the Windows guest sit at the addresses the X79
chipset uses (see below).

### Enabling the IOMMU

`roles/kvm/tasks/iommu.yml` adds `intel_iommu=on` to `GRUB_CMDLINE_LINUX`. It first runs `lineinfile` in check mode
to see if the flag is already present. Only if it is missing does it insert the flag, regenerate `grub.cfg` and
reboot. A second run changes nothing and does not reboot.

### Handing the card to a guest

The Linux GPU guest, `ubuntu-gpu-kvm1`, is created by `virt-install` with `--machine q35` and one `--host-device`
for each PCI function of the card (`roles/kvm/templates/virt-install.sh.j2`). That makes the card a
libvirt-managed host device: libvirt detaches it from the host when the guest starts and reattaches it when the
guest stops.

libvirt can only do that cleanly if nothing on the host is using the card. Here, the host's NVIDIA driver and its
EFI framebuffer both held it. So a libvirt hook clears the host side first.

libvirt runs `/etc/libvirt/hooks/qemu` at each stage of a guest's life. The dispatcher in `roles/kvm/files/hooks/qemu`
runs whatever executables sit in `qemu.d/<guest>/<stage>/<sub-stage>/`. Only `ubuntu-gpu-kvm1` has any:

```
guest start (prepare/begin): detach-gpu.sh
  1. unbind efi-framebuffer.0                   the host console lets go of the card's memory
  2. modprobe -r nvidia_uvm, nvidia_drm,        unload the driver stack, dependants first,
     nvidia_modeset, nvidia, i2c_nvidia_gpu     so no host module holds the device
  3. virsh nodedev-detach pci_0000_03_00_0      detach both functions; they share an IOMMU
     virsh nodedev-detach pci_0000_03_00_1      group, so they must go to the guest together
  4. modprobe vfio, vfio_pci, vfio_iommu_type1  the drivers that hand the device to QEMU
        |
        v
  libvirt starts the guest with the card attached
        |
        v
guest stop (release/end): attach-gpu.sh
  1. modprobe -r vfio, vfio_pci, vfio_iommu_type1
  2. virsh nodedev-reattach both functions
  3. modprobe the nvidia modules, in reverse order
  4. nvidia-xconfig --query-gpu-info            query the card, output discarded
  5. bind efi-framebuffer.0
```

The order has one reason behind it: a device still held by a host driver cannot be detached. The framebuffer and
the NVIDIA modules come off first, and come back last. The scripts carry the original Japanese comments. Some steps
in them are rough; see [Rough edges](#rough-edges-found-on-re-reading).

The guest is defined with autostart disabled. The card therefore stays with the host until someone starts the guest.

### The Windows guest

`windows-vm1` also got the card, but without hooks. Its install script (`roles/kvm/templates/windows/install.sh.j2`)
only creates the VM. The `<hostdev managed='yes'>` entries were then added by hand with `virsh edit`; the steps are
in [docs/operating.md](docs/operating.md).

### What the two GPU guests were for

The configuration answers this in part.

- `windows-vm1` is set up as a desktop. It has a VNC display with a qxl video device, a `host-passthrough` CPU
  (see the operating notes), and `--features kvm_hidden=on`. That last one is the usual workaround for the NVIDIA
  Windows driver refusing to run once it detects a VM (error "Code 43"). The install script also carries
  commented-out passthrough of PCI devices `00:1a.0` and `00:1d.0`. On the X79 chipset, those are the two USB 2.0
  (EHCI) controllers, and passing them through is how a VM gets a real keyboard and mouse. The workload is not recorded.
- `ubuntu-gpu-kvm1` is headless (`--graphics none`, and no desktop packages in cloud-init). The commented commands
  in `roles/stable-diffusion/tasks/stable_diffusion.yml` run Stable Diffusion's `txt2img.py` as the guest user and
  serve the output directory over HTTP. It was a GPU compute guest.

## The rest of the lab

**Every host (`common` role).** Installs SSH keys and disables password login. Grants the Ansible user passwordless
sudo. Replaces the installer's netplan config with a bridge `br0` and a static address, applies it, and reboots.
Adds a systemd unit that turns on Wake-on-LAN (`ethtool ... wol g`) at boot. Finally, upgrades packages.

**The KVM host (`kvm` role).** Checks for hardware virtualization (`vmx`/`svm`, `kvm-ok`), enables the IOMMU,
installs libvirt, and creates a `kvm-user`. It mounts a separate disk on `/var/lib/libvirt/images` and installs
the hooks above. For each Linux guest in `inventory/host_vars/kvm1/vms.yml`, it does four things:

- unpacks a distro cloud image (CentOS Stream 8 or Ubuntu 20.04) into the guest's disk;
- grows the disk to the requested size with `qemu-img resize`;
- builds a cloud-init NoCloud seed ISO (`meta-data`, `user-data`, `network-config`) with the user, SSH keys and
  a static address on the bridge;
- writes an `install.sh` and a `destroy.sh` for the guest.

Ansible stops there. The guests were created by running those scripts by hand.

**The Kubernetes nodes (`k8s-node` role, `k8s-nodes.yml`).** Five guests, `centos-vm1` to `centos-vm5`, listed in
`guests/hosts.yml`. The role loads the kernel modules the service mesh needed (`br_netfilter`, `nf_nat`, the
iptables modules). It also installs the Longhorn prerequisites: the iSCSI initiator with a fixed initiator name
per node, and the NFS client. Kubernetes itself was installed on these nodes with Kubespray, and the cluster was
run from separate repositories that are not public. This work came first, in November 2022; the GPU guests are
separate machines from December.

**The GPU machine (`ubuntu-gpu`).** A second-hand AMD Ryzen 7 3700-class machine, bought in January 2023, that
dual-boots Ubuntu and Windows. The RTX 3060 moved into it from `kvm1` (see below). The
`dualboot` role installs `efibootmgr`. It also reads the "Windows Boot Manager" entry from `grub.cfg` and writes a
`reboot-into-windows.sh` that runs `grub-reboot` with that entry and restarts. Ubuntu stays the default, and
Windows is a one-time choice. With Wake-on-LAN, the machine could be woken over the network and sent into Windows
without anyone at the keyboard.

**The GPU and ML stack (`nvidia`, `ml`, `docker`, `nvidia-docker`, `stable-diffusion` roles).** Installs the
`nvidia-driver-470-server` package and sets the default boot target to text mode. Then it installs CUDA 11.4 from
NVIDIA's repository, Git LFS, Anaconda, Docker and `nvidia-docker2`. Finally, it clones the Stable Diffusion v1 and
v2 repositories and copies model checkpoints from the control machine. `main.yml` applies this to `ubuntu-gpu` on
bare metal. `nvidia-ml.yml` with `inventory_nvidia_ml/hosts.yml` applies it inside the guest `ubuntu-gpu-kvm1`.

## How the GPU work evolved

The commit history shows the order of things:

| Date       | Change                                                                        |
|------------|-------------------------------------------------------------------------------|
| 2022-11    | KVM host, cloud-image guests, CentOS nodes, Longhorn prerequisites            |
| 2022-12-18 | Windows guest                                                                 |
| 2022-12-20 | GPU passthrough to `ubuntu-gpu-kvm1`, with the libvirt hooks                  |
| 2022-12-30 | Stable Diffusion inside that guest                                            |
| 2023-01-03 | RTX 3060 moves to `ubuntu-gpu`: dual boot, ML stack on bare metal; Wake-on-LAN |
| 2023-01-07 | Docker and `nvidia-docker2`                                                   |

The code does not say why the GPU work left the VM after two weeks. The author remembers why: a second-hand Ryzen
machine was bought, and the RTX 3060 was moved into it. The Ryzen machine's own, older NVIDIA card most likely went
into `kvm1` in exchange, though that memory is less certain. `kvm1` stays in the `nvidia` group after the move,
which fits. Whether the passthrough was used again with that card is not recorded.

The Stable Diffusion work of the time included a Twitter bot, kept in a separate private repository, that ran as a
container with `docker run --gpus all`. It was created on 2023-01-08, after the card had moved and a day after
`nvidia-docker2` was added, so it most likely ran on `ubuntu-gpu`.

## Choices and trade-offs

This section was written in 2026, three years after the work. An AI agent led the retrospective by reading the
repository and its history, because the author's own memory of it had faded. A few facts come from memory:

- the card was an RTX 3060, and the author never owned the GeForce GT 240 that an `lspci` sample in the old README
  showed;
- `kvm1` was an Intel X79 machine, and `ubuntu-gpu` a second-hand Ryzen machine bought in January 2023;
- the RTX 3060 moved from the first to the second, and the Ryzen's own card probably went the other way.

Everything else is read from the code and the commit history.

### Getting the GPU to a guest

There were three options:

1. Bind the card to `vfio-pci` at boot. This is simple and deterministic, but the host can never use its own driver
   for the card.
2. Let libvirt detach and reattach a managed host device.
3. Write hooks that unload the host's driver stack around each guest start.

This repository mixes the second and third: managed host devices, plus hooks that clear the host first. The first
option was considered. A `vfio_pciids` variable with the card's IDs, and a `vfio-pci.ids=` variant of the GRUB
edit, are both still there as comments. What was gained is a card that the host keeps between guest runs. What it
cost is a sequence of kernel module operations that runs on every guest start and stop, and that can leave the card
half-attached if a step fails. Why the host needed the NVIDIA driver at all is not recorded.

### Rough edges found on re-reading

- `attach-gpu.sh` unloads `vfio` before `vfio_pci`, which depends on it. That step most likely fails.
- Neither hook script uses `set -e`, so a failed step does not stop the ones after it.
- The explicit `modprobe` of the vfio modules after `nodedev-detach` is probably redundant, because
  `nodedev-detach` binds the device to `vfio-pci` itself.
- The PCI addresses are hard-coded in the hook scripts, the `virt-install` template and the Windows notes. Hooks
  exist for only one guest. When the card moved to another machine, none of this could follow it.
- The IOMMU task only knows Intel's flag. On an AMD host `intel_iommu=on` is ignored, which is harmless, but the
  role does not check the CPU vendor.
- In `cloud-init-per-instance.yml`, `chattr –i` is written with an en dash rather than a hyphen, so that command
  cannot have worked as written.
- The NVIDIA driver task has `ignore_errors: true`, so a failed install does not stop the play.

### Defining virtual machines

There were three options: templated shell scripts calling `virt-install` (what this repository does), the
`community.libvirt` Ansible modules with domain XML, or a Terraform/OpenTofu libvirt provider. The scripts were the
quickest to write. But Ansible only generates them; it never knows whether a VM exists or matches its definition.
Re-running the playbook cannot bring a guest back to a known state. A commented-out `community.libvirt.virt_pool`
task notes an install error with the Python libvirt bindings, which may be why the modules were not used.

### Guest images

The guests use distro cloud images plus per-instance cloud-init, rather than images baked ahead of time with a tool
such as Packer. That keeps the repository small, and each guest's identity is readable in `vms.yml`. What it costs
is that every guest starts from a generic image. Anything beyond users and network, such as Longhorn's
prerequisites, needs a second playbook (`k8s-nodes.yml`) run after boot.

### Robustness of the Ansible itself

The IOMMU task edits GRUB with `lineinfile` and decides what changed from a check-mode run. Then it shells out to
`grub-mkconfig` and reboots. The network and driver tasks reboot the same way. It works.
Handlers, `ansible-lint` and a check-mode run in CI would have made it safer to re-run.

### Secrets and identity

SSH keys and the Windows VNC password were plain values in the inventory. Before publication they were replaced
with a placeholder and a required variable (issue #3). The history still contains the originals, deliberately: an
SSH public key is not a secret, and the machine the password protected no longer exists. `ansible-vault` or SOPS
would have been the right tools. The VNC display listened on all interfaces and was reachable on the LAN only.
Anyone reusing this should bind it to localhost and use an SSH tunnel.

### The Kubernetes layer

The cluster ran Kubespray on five CentOS Stream guests. The other options were k3s directly on the host, or an
immutable node OS such as Talos. Kubespray on VMs is the heaviest of the three. It needs separate node machines,
each prepared with kernel modules and storage packages, which is what `k8s-node` provides. In return, the
cluster looks like a conventional multi-node installation. Why Kubespray was chosen is not recorded.

## Running it

This has not been run since early 2023. To use it on your own machines:

- Put your SSH public key in `inventory/group_vars/all.yml`.
- Set `kvm_windows_vnc_pass` (host or group vars, or `--extra-vars`). The Windows install script refuses to render
  without it.
- Adjust addresses, interface names and the image disk in `inventory/host_vars/`.
- Place the cloud images and Windows ISOs listed there under `roles/kvm/files/images/{xz,windows}/`, and any Stable
  Diffusion checkpoints under `roles/stable-diffusion/files/models/`. These are gitignored.
- Install the `community.general` and `ansible.posix` collections.

```bash
ansible-playbook -K -i inventory/hosts.yml main.yml              # the hosts
ansible-playbook -i guests/hosts.yml k8s-nodes.yml               # the Kubernetes nodes
ansible-playbook -i inventory_nvidia_ml/hosts.yml nvidia-ml.yml  # the ML stack inside the GPU guest
```

The original runbook, including the manual passthrough and VNC steps, is in [docs/operating.md](docs/operating.md).

## License

[MIT](LICENSE)
