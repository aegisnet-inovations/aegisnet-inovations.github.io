# DROP OS — PRD

## Problem Statement
Build DROP OS: single-user, AI-only OS. No login, no GUI, no multi-user. AI core is the only interface. Bootable ISO for Thermaltake tower (AMD chipset, Gigabyte mobo, DDR3, AMD/ATI GPU — CPU-only compute). Ollama (llama3) local LLM.

## What's Implemented (2026-04-16)
- Complete source tree: ai_core, audio, memory, exec_engine, webintel, hitl — 1:1 with 3-block spec
- call_llm() wired to Ollama HTTP localhost:11434 (llama3)
- Whisper STT wired into audio/daemon.py (base model, fp16=False for CPU-only)
- Audio daemon: captures 5s mic chunks → Whisper transcription → .txt files → memory ingestion
- All shell launchers (bin/) with correct permissions
- Automated build-iso.sh: one-command ISO builder
- Downloadable tarball: drop-os-complete.tar.gz

## Hardware Profile (Thermaltake Tower)
- AMD chipset (vendor 1002), Gigabyte motherboard
- DDR3 RAM, 4 DIMM slots
- AMD/ATI GPU (no CUDA — CPU-only inference)
- Whisper: base model (CPU), Ollama: llama3 8B

## Backlog
- P1: User builds ISO on tower via build-iso.sh
- P2: ChromaDB upgrade for vector store
- P3: Network auto-config in init-drop
