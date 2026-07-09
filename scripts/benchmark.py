#!/usr/bin/env python3
"""Benchmark llama-server — measures tokens/sec generation speed."""

import json
import sys
import time
from urllib import request, error

SERVER = "<server-lan-ip>"
PORT = 8080
URL = f"http://{SERVER}:{PORT}/v1/chat/completions"

BENCH_PROMPTS = [
    "Explain what a GPU is in one paragraph.",
    "Write a short poem about artificial intelligence.",
    "List five benefits of renewable energy with one sentence each.",
    "What is the difference between RAM and VRAM? Explain simply.",
    "Write a Python function that calculates fibonacci numbers recursively.",
]

TEST_HEADER = """
╔══════════════════════════════════════════════════════════╗
║           Qwen 2.5 14B — ROCm Benchmark                 ║
╚══════════════════════════════════════════════════════════╝
"""


def benchmark_once(prompt: str) -> dict:
    payload = {
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 200,
        "temperature": 0.0,
        "stream": False,
    }
    req = request.Request(
        URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.time()
    with request.urlopen(req, timeout=180) as resp:
        body = json.loads(resp.read())
    elapsed = time.time() - t0
    usage = body.get("usage", {})
    timings = body.get("timings", {})
    return {
        "prompt": prompt[:80] + "...",
        "elapsed": elapsed,
        "prompt_tokens": usage.get("prompt_tokens", 0),
        "completion_tokens": usage.get("completion_tokens", 0),
        "tokens_per_sec": timings.get("predicted_per_second", 0),
    }


def main():
    print(TEST_HEADER)
    results = []
    for i, prompt in enumerate(BENCH_PROMPTS, 1):
        print(f"[{i}/{len(BENCH_PROMPTS)}] {prompt[:60]}...", end=" ", flush=True)
        try:
            r = benchmark_once(prompt)
            results.append(r)
            print(f"  {r['completion_tokens']} tokens in {r['elapsed']:.1f}s "
                  f"({r['tokens_per_sec']:.1f} tok/s)")
        except Exception as e:
            print(f"  FAIL: {e}")

    if results:
        avg_tps = sum(r["tokens_per_sec"] for r in results) / len(results)
        total_tokens = sum(r["completion_tokens"] for r in results)
        total_time = sum(r["elapsed"] for r in results)
        print(f"\n{'─' * 56}")
        print(f"Results: {len(results)}/{len(BENCH_PROMPTS)} passed")
        print(f"Average:  {avg_tps:.1f} tokens/sec")
        print(f"Total:    {total_tokens} tokens in {total_time:.1f}s")
        print(f"{'─' * 56}")


if __name__ == "__main__":
    main()
