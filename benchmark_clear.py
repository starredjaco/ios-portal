#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["httpx"]
# ///
"""Benchmark adaptive clear method on the iOS portal."""

import asyncio
import sys
import httpx

BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:6643"
LONG_TEXT = "The quick brown fox jumps over the lazy dog. " * 4  # ~180 chars
RECT = "{{91,805},{238,40}}"


async def main():
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=300.0) as client:
        print(f"Connected to {BASE_URL}")
        print(f"Text length: {len(LONG_TEXT)} chars\n")

        # Type text
        print(f"Typing {len(LONG_TEXT)} chars...")
        resp = await client.post("/inputs/type_focused", json={"text": LONG_TEXT})
        resp.raise_for_status()
        print("Typed successfully.")

        input("\n>>> Move the cursor wherever you want, then press Enter to clear...\n")

        # Clear
        print("Clearing...")
        resp = await client.post("/inputs/clear", json={"rect": RECT})
        resp.raise_for_status()
        result = resp.json()
        print(f"  Characters deleted: {result['charactersDeleted']}")
        print(f"  Duration: {result['durationMs']:.1f} ms")
        print(f"  Method: {result['method']}")

        print("\nDone!")


asyncio.run(main())
