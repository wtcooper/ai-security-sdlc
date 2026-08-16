"""Ingest: fetch → sanitise → chunk → embed → upsert with permission metadata. Runs as a job with the ONLY write credential.

TODO(memory-rag-integrity): whoever can write embeddings decides every future answer — this job's identity is the trust anchor.
"""
from __future__ import annotations

import os
import time
import uuid

from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, PointStruct, VectorParams

GW, COLL = os.environ["AISEC_GATEWAY_BASE_URL"], os.environ["QDRANT_COLLECTION"]


def fetch_documents() -> list[dict]:
    """TODO: your connector. Return [{doc_id, tenant, acl: [principals], source, text}].
    TODO(data-minimization): the connector's grant is the widest in the system — read-only, scoped to the corpus you index."""
    return []


def sanitise(text: str) -> str:
    """TODO(prompt-injection): strip/neutralise instruction-like content, hidden text, zero-width chars, HTML comments at ingest — it is cheap here."""
    return text


def main() -> None:
    qc = QdrantClient(url=os.environ["QDRANT_URL"])   # TODO(memory-rag-integrity): write-scoped API key/JWT
    if not qc.collection_exists(COLL):
        qc.create_collection(COLL, vectors_config=VectorParams(size=1536, distance=Distance.COSINE))   # TODO: size = your embedding dim
    emb = OpenAIEmbeddings(base_url=f"{GW}/v1", model=os.environ["AISEC_EMBED_MODEL"], api_key=os.environ.get("AISEC_GATEWAY_API_KEY", "unused"))
    splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=100)
    now = time.time()
    for d in fetch_documents():
        chunks = splitter.split_text(sanitise(d["text"]))
        vecs = emb.embed_documents(chunks)
        points = [PointStruct(id=str(uuid.uuid5(uuid.NAMESPACE_URL, f"{d['doc_id']}#{i}")), vector=v,
                              payload={"doc_id": d["doc_id"], "tenant": d["tenant"], "acl": d["acl"], "source": d["source"], "ingested_at": now, "text": c})
                  for i, (c, v) in enumerate(zip(chunks, vecs))]
        qc.upsert(COLL, points)     # TODO(memory-rag-integrity): also delete chunks for docs removed/de-permissioned at source


if __name__ == "__main__":
    main()
