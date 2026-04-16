# DROP OS — PRD

## Problem Statement
Build DROP OS: single-user, AI-only OS. No login, no GUI, no multi-user. AI core is the only interface. Bootable ISO for Thermaltake tower. Ollama (llama3) local LLM.

## What's Implemented (2026-04-16)
- Complete source tree: ai_core, audio, memory, exec_engine, webintel, hitl — 1:1 with 3-block spec
- call_llm() wired to Ollama HTTP localhost:11434
- All shell launchers (bin/) with correct permissions
- Automated build-iso.sh: one-command ISO builder (debootstrap→chroot→Ollama→GRUB→ISO)
- Downloadable tarball: drop-os-complete.tar.gz
- ISO cannot be built in this ARM64 container — script runs on user's x86_64 machine

## Backlog
- P1: User runs build-iso.sh on x86_64 machine → gets drop-os.iso
- P2: Wire Whisper STT into audio daemon
- P2: ChromaDB upgrade for vector store
- P3: Network auto-config in init-drop (dhclient/dhcpcd)
