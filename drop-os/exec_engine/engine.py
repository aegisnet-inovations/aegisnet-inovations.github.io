import subprocess
import tempfile
import os
from textwrap import dedent


class ExecutionEngine:
    def __init__(self, image: str = "python:3.11-slim"):
        self.image = image

    def run_snippet(self, language: str, code: str) -> str:
        if language != "python":
            return "Only Python supported in this build."
        with tempfile.TemporaryDirectory() as tmpdir:
            script_path = os.path.join(tmpdir, "main.py")
            with open(script_path, "w") as f:
                f.write(dedent(code))
            cmd = [
                "docker", "run", "--rm",
                "-v", f"{script_path}:/app/main.py",
                "-w", "/app",
                self.image,
                "python", "main.py",
            ]
            try:
                out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
                return out
            except subprocess.CalledProcessError as e:
                return f"exec error:\n{e.output}"
