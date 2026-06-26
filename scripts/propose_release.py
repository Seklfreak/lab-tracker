#!/usr/bin/env python3
"""Decide the next semver bump + write release notes for the commits since the last
release, using Claude. Writes {"bump","notes"} to release.json and prints the bump.

Falls back to a patch bump with the raw commit list if no API key is set or the API
call fails, so auto-releases never block on the AI step.

Usage: propose_release.py <previous-tag>   (env: ANTHROPIC_API_KEY, HEAD_SHA)
"""
import json
import os
import subprocess
import sys

PREV = sys.argv[1] if len(sys.argv) > 1 else ""
HEAD = os.environ.get("HEAD_SHA", "HEAD")
RANGE = f"{PREV}..{HEAD}" if PREV else HEAD


def git(*args: str) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True).stdout.strip()


commits = git("log", RANGE, "--no-merges", "--pretty=format:- %s")
stat = git("diff", "--stat", f"{PREV}..{HEAD}") if PREV else git("show", "--stat", "--oneline", HEAD)


def write(bump: str, notes: str) -> None:
    json.dump({"bump": bump, "notes": notes}, open("release.json", "w"))
    print(bump)


def fallback(reason: str) -> None:
    sys.stderr.write(f"AI step skipped ({reason}); defaulting to patch bump.\n")
    body = commits or "Maintenance release."
    write("patch", f"## Changes\n\n{body}\n")


if not os.environ.get("ANTHROPIC_API_KEY"):
    fallback("ANTHROPIC_API_KEY not set")
    sys.exit(0)

try:
    import anthropic

    tool = {
        "name": "propose_release",
        "description": "Propose the semantic-version bump and release notes.",
        "input_schema": {
            "type": "object",
            "properties": {
                "bump": {"type": "string", "enum": ["major", "minor", "patch"]},
                "notes": {
                    "type": "string",
                    "description": "User-facing markdown release notes. Group into sections "
                    "(e.g. Features / Fixes / Maintenance) as relevant; omit empty sections; be concise.",
                },
            },
            "required": ["bump", "notes"],
        },
    }
    prompt = f"""You decide the next semantic-version bump and write release notes for lab-tracker,
a self-hosted lab-results tracker (Go API + React frontend + MCP server). It is pre-1.0 (0.x).

Choose the bump:
- patch: bug fixes, refactors, chores, docs, CI, dependency bumps.
- minor: new user-facing features or notable backwards-compatible enhancements.
- major: only genuinely breaking changes to the API, data model, or deploy contract.
  Pre-1.0, strongly prefer minor over major unless clearly breaking.

Previous release: {PREV or "(none yet)"}

Commits:
{commits or "(no commit messages)"}

Files changed:
{stat or "(none)"}

Call propose_release with the bump and concise, user-facing markdown notes."""

    client = anthropic.Anthropic()
    msg = client.messages.create(
        # Haiku is plenty for bump-classification + concise notes; override if desired.
        model=os.environ.get("RELEASE_MODEL", "claude-haiku-4-5"),
        max_tokens=2000,
        tools=[tool],
        tool_choice={"type": "tool", "name": "propose_release"},
        messages=[{"role": "user", "content": prompt}],
    )
    result = next(b.input for b in msg.content if b.type == "tool_use")
    bump = result["bump"] if result.get("bump") in ("major", "minor", "patch") else "patch"
    write(bump, result.get("notes") or (commits or "Maintenance release."))
except Exception as e:  # noqa: BLE001 — never block a release on the AI step
    fallback(f"API error: {e}")
