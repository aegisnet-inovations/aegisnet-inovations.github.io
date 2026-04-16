# DROP OS — PRD

## Problem Statement
Build DROP OS: single-user, AI-only OS for Thermaltake tower (AMD chipset, Gigabyte mobo, DDR3, AMD/ATI GPU — CPU-only). Ollama llama3 local LLM. Bootable ISO.

## What's Implemented (2026-04-16)
- Complete source tree 1:1 with 3-block spec
- call_llm() → Ollama HTTP localhost:11434 (llama3)
- Whisper STT in audio/daemon.py (base model, fp16=False, CPU-only)
- ChromaDB semantic search in vectordb.py (all-MiniLM-L6-v2 embeddings, cosine similarity, with flat-log fallback)
- Network auto-detect in init-drop (finds first NIC, dhcpcd/dhclient)
- Ollama auto-start in init-drop
- Automated build-iso.sh (one command → drop-os.iso)
- Downloadable tarball: drop-os-complete.tar.gz

## Backlog
- P1: User builds ISO on x86_64 machine
- P3: Tune Ollama model for AMD hardware (llama3 vs phi3:mini)
