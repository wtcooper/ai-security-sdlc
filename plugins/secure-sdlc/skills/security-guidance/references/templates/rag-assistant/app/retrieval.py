"""Entitlement-filtered retrieval. The filter is applied IN the query, before any chunk is fetched.

TODO(data-minimization): never post-filter — dropping content after retrieval still leaked it into memory/logs.
TODO(memory-rag-integrity): the payload schema {tenant, acl, source, ingested_at, doc_id} is the contract with ingest.py.
"""
from __future__ import annotations

import os

from qdrant_client import QdrantClient
from qdrant_client.models import FieldCondition, Filter, MatchAny, MatchValue

COLLECTION = os.environ["QDRANT_COLLECTION"]


def client() -> QdrantClient:
    # TODO(memory-rag-integrity): read-only API key/JWT for the app; ingest gets the write key.
    return QdrantClient(url=os.environ["QDRANT_URL"])


def entitlement_filter(identity: dict) -> Filter:
    return Filter(must=[
        FieldCondition(key="tenant", match=MatchValue(value=identity["tenant"])),
        FieldCondition(key="acl", match=MatchAny(any=[identity["user"], *identity.get("groups", [])])),
    ])


def retrieve(identity: dict, query_vector: list[float], k: int = 6) -> list[dict]:
    hits = client().query_points(COLLECTION, query=query_vector, query_filter=entitlement_filter(identity), limit=k, with_payload=True).points
    # TODO(memory-rag-integrity): freshness check — drop hits whose ingested_at is older than your staleness policy.
    return [{"doc_id": h.payload["doc_id"], "source": h.payload["source"], "text": h.payload["text"], "score": h.score} for h in hits]
