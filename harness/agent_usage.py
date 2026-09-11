#!/usr/bin/env python3
"""Extract token usage from an agent's machine-readable output.

claude:   `claude -p --output-format json` prints one JSON object with `usage`.
opencode: `opencode run --format json` prints one JSON event per line; step
          events carry a `tokens` object with input/output (and reasoning) counts.
Prints a JSON object {input_tokens, output_tokens, cost_usd}.
"""
import json
import sys


def claude_usage(text):
    doc = json.loads(text.strip().splitlines()[-1])
    usage = doc.get("usage", {})
    return {"input_tokens": usage.get("input_tokens", 0)
            + usage.get("cache_read_input_tokens", 0)
            + usage.get("cache_creation_input_tokens", 0),
            "output_tokens": usage.get("output_tokens", 0),
            "cost_usd": doc.get("total_cost_usd"),
            "num_turns": doc.get("num_turns")}


def token_objects(node):
    if isinstance(node, dict):
        tokens = node.get("tokens")
        if isinstance(tokens, dict) and "input" in tokens and "output" in tokens:
            yield tokens
        for value in node.values():
            yield from token_objects(value)
    elif isinstance(node, list):
        for value in node:
            yield from token_objects(value)


def opencode_usage(text):
    events = [json.loads(line) for line in text.splitlines() if line.startswith("{")]
    tokens = [t for event in events for t in token_objects(event)]
    return {"input_tokens": sum(int(t.get("input", 0)) for t in tokens),
            "output_tokens": sum(int(t.get("output", 0)) + int(t.get("reasoning", 0) or 0) for t in tokens),
            "cost_usd": None,
            "num_turns": len(tokens)}


def main():
    tool, path = sys.argv[1], sys.argv[2]
    text = open(path, encoding="utf-8", errors="replace").read()
    try:
        usage = claude_usage(text) if tool == "claude" else opencode_usage(text)
    except (json.JSONDecodeError, IndexError):
        usage = {"input_tokens": None, "output_tokens": None, "cost_usd": None, "num_turns": None}
    print(json.dumps(usage))


if __name__ == "__main__":
    main()
