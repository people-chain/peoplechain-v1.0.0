#!/usr/bin/env python3
# Minimal Python client for PeopleChain monitor REST + WebSocket
#
# Usage:
#   pip install requests websocket-client
#   BASE_URL=http://192.168.1.50:8081 python3 peoplechain_api_example.py
#
# Defaults to http://127.0.0.1:8081 if BASE_URL is not provided.

import json
import os
import time
from urllib.parse import urlencode

import requests
from websocket import create_connection


BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:8081")


def get(path, params=None):
    url = f"{BASE_URL}{path}"
    if params:
        url = f"{url}?{urlencode(params)}"
    r = requests.get(url, timeout=10)
    r.raise_for_status()
    return r.json()


def rest_demo():
    print("== REST: /api/info")
    print(json.dumps(get("/api/info"), indent=2))

    print("\n== REST: /api/peers")
    print(json.dumps(get("/api/peers", {"limit": 10}), indent=2))

    print("\n== REST: /api/blocks (tip..tip-2)")
    print(json.dumps(get("/api/blocks", {"from": "tip", "count": 3}), indent=2))


def ws_demo():
    ws_url = BASE_URL.replace("http://", "ws://").replace("https://", "wss://") + "/ws"
    print(f"\n== WS: connecting to {ws_url}")
    ws = create_connection(ws_url, timeout=10)
    try:
        ws.send(json.dumps({"type": "get_info"}))
        t_end = time.time() + 5
        while time.time() < t_end:
            msg = ws.recv()
            print("WS:", msg)
    finally:
        ws.close()


if __name__ == "__main__":
    print(f"Using BASE_URL={BASE_URL}")
    rest_demo()
    ws_demo()
