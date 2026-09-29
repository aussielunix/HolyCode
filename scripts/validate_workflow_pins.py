#!/usr/bin/env python3
"""Validate immutable action pins and release-workflow guardrails.

The release workflow is intentionally minimal: it builds the multi-architecture
image and publishes it to GitHub Container Registry. This validator only enforces
that every external action is pinned by commit and that the minimal release and
pull-request workflows remain well-formed. There is no Docker Hub, Docker Scout,
Trivy, or registry-account dependency.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
USES_RE = re.compile(r"^\s*uses:\s*([^@\s]+)@([^\s#]+)(?:\s*#\s*(\S+))?\s*$")

REQUIRED_PINS = {
    "actions/checkout": ("3d3c42e5aac5ba805825da76410c181273ba90b1", "v7.0.1"),
    "actions/setup-node": ("820762786026740c76f36085b0efc47a31fe5020", "v7.0.0"),
    "docker/setup-buildx-action": ("f87e5991a6d7451dcb8d9637bfbc97413f497069", "v4.4.1"),
    "docker/login-action": ("dbcb813823bdd20940b903addbd779551569679f", "v4.6.0"),
    "docker/build-push-action": ("c3c9e263c25d99ce0380d002d59b67737d91b0dc", "v7.4.0"),
}


def collect_errors() -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()

    for workflow in sorted(WORKFLOWS.glob("*.yml")):
        text = workflow.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            match = USES_RE.match(line)
            if not match:
                continue
            action, ref, version_comment = match.groups()
            location = f"{workflow.relative_to(ROOT)}:{line_number}"
            if not SHA_RE.fullmatch(ref):
                errors.append(f"{location} uses {action}@{ref}; external actions must be pinned to a 40-char SHA")
                continue
            if action in REQUIRED_PINS:
                expected_ref, expected_version = REQUIRED_PINS[action]
                seen.add(action)
                if ref != expected_ref:
                    errors.append(f"{location} uses {action}@{ref}; expected {expected_ref}")
                if version_comment != expected_version:
                    errors.append(f"{location} must keep comment '# {expected_version}'")

    missing = sorted(set(REQUIRED_PINS) - seen)
    for action in missing:
        errors.append(f"required pinned action is not present: {action}")

    publish = WORKFLOWS / "docker-publish.yml"
    publish_text = publish.read_text(encoding="utf-8")
    if "packages: write" not in publish_text or "contents: read" not in publish_text:
        errors.append("docker-publish.yml must declare packages: write and contents: read permissions")
    if "ghcr.io/aussielunix/holycode" not in publish_text:
        errors.append("docker-publish.yml must publish to ghcr.io/aussielunix/holycode")
    if "linux/amd64" not in publish_text:
        errors.append("docker-publish.yml must build linux/amd64")
    if "provenance: true" not in publish_text:
        errors.append("docker-publish.yml must enable provenance attestations")

    pr_validation = WORKFLOWS / "pr-validation.yml"
    pr_text = pr_validation.read_text(encoding="utf-8")
    for required in (
        "node-version: 24.21.0",
        "python -m unittest discover -s tests",
        "python scripts/validate_workflow_pins.py",
        "python scripts/validate_chromium_seccomp.py",
        "bash scripts/validate_renovate_extraction.sh 44.112.3",
        "bash scripts/smoke_image.sh",
        "bash scripts/test_plugin_modes.sh",
    ):
        if required not in pr_text:
            errors.append(f"pr-validation.yml must contain {required!r}")
    if "scout_sha256" in pr_text or "trivy_sha256" in pr_text:
        errors.append("pr-validation.yml must not require Docker Scout or Trivy")

    return errors


def main() -> int:
    errors = collect_errors()
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("workflow pin validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
