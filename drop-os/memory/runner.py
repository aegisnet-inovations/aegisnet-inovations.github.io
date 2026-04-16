import time
import sys
import os

sys.path.insert(0, "/opt/drop-os")

from memory.vectordb import VectorStore

WATCH_PATHS = ["/var/drop-os/audio", "/var/log"]


def main():
    store = VectorStore("/var/drop-os/memory")
    seen = set()
    while True:
        for base in WATCH_PATHS:
            if not os.path.isdir(base):
                continue
            for root, _, files in os.walk(base):
                for name in files:
                    path = os.path.join(root, name)
                    if path in seen:
                        continue
                    seen.add(path)
                    try:
                        with open(path) as f:
                            text = f.read()
                        store.add_text("files", f"{path}: {text[:2000]}")
                    except Exception:
                        pass
        time.sleep(10)


if __name__ == "__main__":
    main()
