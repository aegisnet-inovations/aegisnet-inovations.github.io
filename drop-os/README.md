# DROP OS — Build & Install

Single-user, AI-only operating system. No login, no GUI, no multi-user.
AI core is the primary and only interface.

## Boot Flow

BIOS/UEFI → GRUB → Linux kernel → init=/opt/drop-os/bin/init-drop → DROP OS AI Core

## ISO Build Pipeline (Debian)

On a build machine with root access:

### a) Create rootfs

```
debootstrap stable /mnt/drop-root http://deb.debian.org/debian
```

### b) Chroot

```
chroot /mnt/drop-root /bin/bash
```

### c) Inside chroot, install dependencies

```
apt-get update
apt-get install -y linux-image-amd64 grub-pc python3 python3-pip docker.io \
                   alsa-utils curl git
```

### d) Copy DROP OS tree

```
mkdir -p /opt/drop-os
# copy all files from /app/drop-os/ into /opt/drop-os/
cp -r /path/to/drop-os/* /opt/drop-os/
pip3 install -r /opt/drop-os/requirements.txt
```

### e) Install Ollama (for local LLM)

```
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3
```

### f) Make launchers executable

```
chmod +x /opt/drop-os/bin/init-drop
chmod +x /opt/drop-os/bin/drop-*
```

### g) Configure GRUB

Install GRUB to the ISO tree or target disk.
Ensure GRUB cmdline includes:

```
linux /boot/vmlinuz-... root=/dev/sdX1 ro init=/opt/drop-os/bin/init-drop
```

### h) Exit chroot, build ISO

```
mkdir -p /mnt/iso/boot/grub
# copy kernel, initrd, grub.cfg into /mnt/iso/boot/...
grub-mkrescue -o drop-os.iso /mnt/iso
```

## What Happens on Boot

1. Kernel uses `init=/opt/drop-os/bin/init-drop`
2. No login or multi-user services run
3. `/opt/drop-os` contains all code
4. Docker, Python, audio stack, and network are available
5. You land directly in the DROP OS AI core interface (`you> ` prompt)

## Subsystems

| Daemon | Script | Purpose |
|--------|--------|---------|
| drop-core | ai_core/orchestrator.py | AI interface, LLM via Ollama |
| drop-audio | audio/daemon.py | Always-on mic capture |
| drop-memory | memory/runner.py | File watcher → vector store |
| drop-webintel | webintel/agent_daemon.py | Web research → memory |
| drop-hitl | hitl/tui.py | Patch approval gate |
| drop-exec | exec_engine/engine.py | Docker code execution |
