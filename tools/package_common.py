"""Shared byte verification for the desktop distribution tools."""

import hashlib
from pathlib import Path
import re


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def app_version(root: Path) -> str:
    match = re.search(
        r"^version:\s*(.+)$",
        (root / "app/pubspec.yaml").read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if match is None:
        raise ValueError("The application version is missing")
    return match.group(1).strip()
