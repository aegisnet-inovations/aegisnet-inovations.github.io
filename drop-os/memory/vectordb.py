import os
import json
from typing import List, Dict


class VectorStore:
    # simple text store; engineer replaces with real embeddings/Chroma
    def __init__(self, base_path: str):
        self.base_path = base_path
        os.makedirs(self.base_path, exist_ok=True)

    def add_text(self, namespace: str, text: str):
        path = os.path.join(self.base_path, f"{namespace}.log")
        with open(path, "a") as f:
            f.write(text.replace("\n", " ") + "\n")

    def search(self, namespace: str, query: str, limit: int = 10) -> List[Dict]:
        path = os.path.join(self.base_path, f"{namespace}.log")
        if not os.path.exists(path):
            return []
        results = []
        with open(path) as f:
            for line in f:
                if query.lower() in line.lower():
                    results.append({"text": line.strip()})
                    if len(results) >= limit:
                        break
        return results
