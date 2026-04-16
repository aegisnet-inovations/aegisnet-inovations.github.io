import os
import json
from typing import List, Dict

# Try ChromaDB first, fall back to simple text store
try:
    import chromadb
    CHROMA_AVAILABLE = True
except ImportError:
    CHROMA_AVAILABLE = False


class VectorStore:
    def __init__(self, base_path: str):
        self.base_path = base_path
        os.makedirs(self.base_path, exist_ok=True)

        if CHROMA_AVAILABLE:
            self._client = chromadb.PersistentClient(path=os.path.join(base_path, "chroma_db"))
            self._collections = {}
            print("DROP memory: ChromaDB active (semantic search enabled)")
        else:
            self._client = None
            print("DROP memory: text-only mode (install chromadb for semantic search)")

    def _get_collection(self, namespace: str):
        if namespace not in self._collections:
            self._collections[namespace] = self._client.get_or_create_collection(
                name=namespace,
                metadata={"hnsw:space": "cosine"},
            )
        return self._collections[namespace]

    def add_text(self, namespace: str, text: str):
        # Always write to flat log (backup + readable)
        log_path = os.path.join(self.base_path, f"{namespace}.log")
        with open(log_path, "a") as f:
            f.write(text.replace("\n", " ") + "\n")

        # Also index in ChromaDB if available
        if CHROMA_AVAILABLE and self._client:
            col = self._get_collection(namespace)
            doc_id = f"{namespace}_{col.count()}"
            col.add(documents=[text], ids=[doc_id])

    def search(self, namespace: str, query: str, limit: int = 10) -> List[Dict]:
        # Use ChromaDB semantic search if available
        if CHROMA_AVAILABLE and self._client:
            col = self._get_collection(namespace)
            if col.count() == 0:
                return []
            results = col.query(query_texts=[query], n_results=min(limit, col.count()))
            docs = results.get("documents", [[]])[0]
            distances = results.get("distances", [[]])[0]
            return [{"text": doc, "distance": dist} for doc, dist in zip(docs, distances)]

        # Fallback: simple substring search on flat log
        log_path = os.path.join(self.base_path, f"{namespace}.log")
        if not os.path.exists(log_path):
            return []
        results = []
        with open(log_path) as f:
            for line in f:
                if query.lower() in line.lower():
                    results.append({"text": line.strip()})
                    if len(results) >= limit:
                        break
        return results
