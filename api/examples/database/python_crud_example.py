#!/usr/bin/env python3
"""
PeopleChain Monitor • Python CRUD example (requests)

Prerequisites:
  pip install requests

Usage:
  python3 python_crud_example.py

This script demonstrates:
  - Create (POST)
  - List with filtering (GET ?q=)
  - Read by id (GET)
  - Update (PUT)
  - Partial update (PATCH)
  - Delete (DELETE)
"""

import json
import requests

BASE = "http://127.0.0.1:8081"
COLLECTION = "notes"  # Example collection name; you can use any string


def pretty(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False)


def create_note(title: str, body: str, tags=None, note_id=None):
    payload = {"id": note_id, "data": {"title": title, "body": body, "tags": tags or []}}
    r = requests.post(f"{BASE}/api/db/{COLLECTION}", json=payload, timeout=10)
    r.raise_for_status()
    return r.json()


def list_notes(q: str | None = None, limit: int = 50, offset: int = 0):
    params = {"limit": str(limit), "offset": str(offset)}
    if q:
        params["q"] = q
    r = requests.get(f"{BASE}/api/db/{COLLECTION}", params=params, timeout=10)
    r.raise_for_status()
    return r.json()


def read_note(note_id: str):
    r = requests.get(f"{BASE}/api/db/{COLLECTION}/{note_id}", timeout=10)
    r.raise_for_status()
    return r.json()


def replace_note(note_id: str, data: dict):
    r = requests.put(f"{BASE}/api/db/{COLLECTION}/{note_id}", json={"data": data}, timeout=10)
    r.raise_for_status()
    return r.json()


def patch_note(note_id: str, data: dict):
    r = requests.patch(f"{BASE}/api/db/{COLLECTION}/{note_id}", json={"data": data}, timeout=10)
    r.raise_for_status()
    return r.json()


def delete_note(note_id: str):
    r = requests.delete(f"{BASE}/api/db/{COLLECTION}/{note_id}", timeout=10)
    r.raise_for_status()
    return r.json()


def main():
    print("1) Create two notes")
    n1 = create_note("First note", "Hello from Python", ["demo", "python"])  # auto id
    n2 = create_note("Second note", "This matches filter", ["demo", "filter"])
    print(pretty(n1))
    print(pretty(n2))

    print("\n2) List all notes (limit=10)")
    print(pretty(list_notes(limit=10)))

    print("\n3) Filter notes containing 'filter'")
    print(pretty(list_notes(q="filter")))

    print("\n4) Read first note by id")
    nid = n1["id"]
    print(pretty(read_note(nid)))

    print("\n5) Replace it with PUT (overwrites data)")
    print(pretty(replace_note(nid, {"title": "Updated title", "body": "Replaced body", "tags": ["updated"]})))

    print("\n6) Patch it with PATCH (shallow merge)")
    print(pretty(patch_note(nid, {"tags": ["updated", "patched"], "extra": 123})))

    print("\n7) Delete second note")
    print(pretty(delete_note(n2["id"])))

    print("\n8) List again")
    print(pretty(list_notes()))


if __name__ == "__main__":
    main()
