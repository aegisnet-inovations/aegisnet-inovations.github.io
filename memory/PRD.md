# DROP OS — Product Requirements Document

## Original Problem Statement
Build DROP OS: a single-user, AI-only operating system where the AI core replaces the traditional shell/desktop as the primary interface. Bootable ISO for bare metal (Thermaltake tower).

## Architecture
- Custom init (PID 1) → launches 5 background daemons + AI core in foreground
- AI Core: Ollama LLM (llama3) via HTTP, parses THOUGHT/CMD format
- Memory: File-based vector store (pluggable to ChromaDB)
- Audio: Always-on mic capture via sounddevice (Whisper STT ready)
- Execution: Docker-isolated Python code runner
- WebIntel: DuckDuckGo research → memory ingestion
- HITL: Diff-based patch approval gate

## What's Been Implemented (2026-04-16)
- Complete source tree at /app/drop-os/ matching 3-block spec
- All 7 shell launchers (bin/)
- All 6 Python modules (ai_core, audio, memory, exec_engine, webintel, hitl)
- call_llm() wired to Ollama HTTP API
- VectorStore, ExecutionEngine, Orchestrator tested and passing
- README with full ISO build instructions

## User Personas
- Single power user on dedicated hardware (Thermaltake tower)

## Prioritized Backlog
- P0: [DONE] Source tree implementation
- P1: ISO build automation script
- P2: Real Whisper STT integration in audio daemon
- P2: ChromaDB upgrade path for vector store
