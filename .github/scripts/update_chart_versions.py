#!/usr/bin/env python3
"""
Minimal helper to bump chart `appVersion` and `version` lines without reformatting the file.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


SEMVER_RE = re.compile(r"(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\s*$")
APP_VERSION_RE = re.compile(r"(?m)^(appVersion:\s*).+$")


@dataclass
class ChartVersion:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, text: str) -> "ChartVersion":
        match = SEMVER_RE.search(text)
        if not match:
            raise ValueError("Unable to find semantic version line")
        return cls(*(int(group) for group in match.groups()))

    def bump_patch(self) -> "ChartVersion":
        return ChartVersion(self.major, self.minor, self.patch + 1)

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"


def update_chart(chart_path: Path, new_engine_version: str) -> None:
    content = chart_path.read_text(encoding="utf-8")

    current_version = ChartVersion.parse(content)
    bumped_version = current_version.bump_patch()

    if not APP_VERSION_RE.search(content):
        raise ValueError("Unable to find appVersion line")

    content = APP_VERSION_RE.sub(r"\g<1>" + new_engine_version, content, count=1)
    content = SEMVER_RE.sub(f"version: {bumped_version}", content, count=1)

    chart_path.write_text(content, encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bump Log10x chart versions")
    parser.add_argument("--engine-version", required=True, help="New Log10x engine version")
    parser.add_argument("charts", nargs="+", help="Paths to Chart.yaml files")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    for chart in args.charts:
        update_chart(Path(chart), args.engine_version)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except Exception as exc:  # pylint: disable=broad-exception-caught
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)

