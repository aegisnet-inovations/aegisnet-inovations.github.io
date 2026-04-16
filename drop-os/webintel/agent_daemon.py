import time
import os
import sys
import requests

sys.path.insert(0, "/opt/drop-os")

from memory.vectordb import VectorStore

TASK_FILE = "/var/drop-os/webintel_tasks.txt"


def main():
    store = VectorStore("/var/drop-os/memory")
    os.makedirs(os.path.dirname(TASK_FILE), exist_ok=True)
    open(TASK_FILE, "a").close()

    while True:
        with open(TASK_FILE) as f:
            topics = [line.strip() for line in f if line.strip()]
        # clear tasks
        open(TASK_FILE, "w").close()

        for topic in topics:
            try:
                # engineer replaces this with real search + crawl
                r = requests.get("https://duckduckgo.com/html/", params={"q": topic}, timeout=10)
                text = r.text[:5000]
                store.add_text("web_research", f"TOPIC: {topic}\n{text}")
            except Exception:
                pass

        time.sleep(15)


if __name__ == "__main__":
    main()
