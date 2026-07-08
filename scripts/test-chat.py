#!/usr/bin/env python3
"""Smoke test for llama-server — sends a single chat completion request."""

import json
import sys
import time
from urllib import request, error

SERVER = "192.168.1.12"
PORT = 8080
URL = f"http://{SERVER}:{PORT}/v1/chat/completions"

PAYLOAD = {
    "messages": [
        {"role": "system", "content": "You are a helpful AI assistant. Answer concisely."},
        {"role": "user", "content": "What is the capital of Indonesia? Reply in one sentence."}
    ],
    "max_tokens": 100,
    "temperature": 0.7,
    "stream": False,
}


def test_chat():
    print(f"Testing {URL}")
    req = request.Request(
        URL,
        data=json.dumps(PAYLOAD).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    try:
        with request.urlopen(req, timeout=120) as resp:
            body = json.loads(resp.read())
            elapsed = time.time() - t0
            choice = body["choices"][0]
            content = choice["message"]["content"]
            tokens = body.get("usage", {})
            print(f"\n  Response ({elapsed:.1f}s):")
            print(f"  {content.strip()}")
            print(f"\n  Tokens: prompt={tokens.get('prompt_tokens')}, "
                  f"completion={tokens.get('completion_tokens')}, "
                  f"total={tokens.get('total_tokens')}")
            return True
    except error.HTTPError as e:
        print(f"\n  HTTP {e.code}: {e.read().decode()[:500]}")
        return False
    except error.URLError as e:
        print(f"\n  Connection failed: {e.reason}")
        return False


if __name__ == "__main__":
    ok = test_chat()
    sys.exit(0 if ok else 1)
