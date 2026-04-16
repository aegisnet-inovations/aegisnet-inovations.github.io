import subprocess
import requests
import sys
import os

sys.path.insert(0, "/opt/drop-os")

from memory.vectordb import VectorStore
from exec_engine.engine import ExecutionEngine


def call_llm(system_prompt: str, user_prompt: str) -> str:
    """
    Calls Ollama local LLM at localhost:11434.
    Must return:
    THOUGHT: run_bash | run_code | reply | research
    CMD: <command / code / topic / reply>
    """
    try:
        resp = requests.post(
            "http://localhost:11434/api/generate",
            json={
                "model": "llama3",
                "prompt": f"{system_prompt}\n\nUser: {user_prompt}",
                "stream": False,
            },
            timeout=120,
        )
        resp.raise_for_status()
        return resp.json().get("response", "THOUGHT: reply\nCMD: No response from LLM.")
    except Exception as e:
        return f"THOUGHT: reply\nCMD: LLM error: {e}"


class Orchestrator:
    def __init__(self):
        self.memory = VectorStore("/var/drop-os/memory")
        self.exec_engine = ExecutionEngine()

    def handle_input(self, text: str) -> str:
        self.memory.add_text("conversation", text)

        system_prompt = (
            "You are DROP OS AI Core. You control the machine.\n"
            "Tools:\n"
            "- run_bash: execute shell commands\n"
            "- run_code: write & run code in container\n"
            "- research: deep web research via webintel\n"
            "- reply: natural language only\n"
            "Format strictly:\n"
            "THOUGHT: <run_bash|run_code|research|reply>\n"
            'CMD: <command/code/topic/reply>'
        )

        raw = call_llm(system_prompt, text)
        action, payload = self._parse(raw)

        if action == "run_bash":
            return self._run_bash(payload)
        if action == "run_code":
            return self._run_code(payload)
        if action == "research":
            return self._research(payload)
        return payload

    def _parse(self, raw: str):
        action = "reply"
        cmd = raw.strip()
        for line in raw.splitlines():
            if line.startswith("THOUGHT:"):
                a = line.split(":", 1)[1].strip().lower()
                if a in ["run_bash", "run_code", "research", "reply"]:
                    action = a
            if line.startswith("CMD:"):
                cmd = line.split(":", 1)[1].strip()
        return action, cmd

    def _run_bash(self, command: str) -> str:
        try:
            out = subprocess.check_output(command, shell=True, stderr=subprocess.STDOUT, text=True)
            self.memory.add_text("bash_output", out)
            return f"[bash]\n{out}"
        except subprocess.CalledProcessError as e:
            return f"[bash error]\n{e.output}"

    def _run_code(self, description: str) -> str:
        result = self.exec_engine.run_snippet("python", f"print('DROP exec: {description}')")
        self.memory.add_text("code_run", result)
        return f"[code]\n{result}"

    def _research(self, topic: str) -> str:
        # Write a simple task file for webintel daemon
        with open("/var/drop-os/webintel_tasks.txt", "a") as f:
            f.write(topic + "\n")
        return f"[research] Task queued: {topic}"


class TerminalUI:
    def __init__(self, orch: Orchestrator):
        self.orch = orch

    def run(self):
        print("DROP OS — AI Core")
        while True:
            try:
                user = input("you> ")
            except (EOFError, KeyboardInterrupt):
                break
            resp = self.orch.handle_input(user)
            print(f"drop> {resp}\n")


if __name__ == "__main__":
    orch = Orchestrator()
    ui = TerminalUI(orch)
    ui.run()
