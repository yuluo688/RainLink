"""Read-only kernel snapshots for the disposable Linux TUN product fixture."""

import argparse
import json
from pathlib import Path
import subprocess


def normalize(value):
    if isinstance(value, dict):
        # Router advertisements count down independently of the client. Keep
        # every address, route selector and rule while omitting elapsed leases.
        return {key: normalize(item) for key, item in value.items()
                if key not in {"expires", "valid_life_time", "preferred_life_time"}}
    if isinstance(value, list):
        return sorted((normalize(item) for item in value), key=lambda item: json.dumps(item, sort_keys=True))
    return value


def snapshot():
    commands = {"links": ["-d", "link", "show"], "addresses": ["address", "show"]}
    for family in ("-4", "-6"):
        commands[f"routes{family}"] = [family, "route", "show", "table", "all"]
        commands[f"rules{family}"] = [family, "rule", "show"]
    return {name: json.loads(subprocess.check_output(["ip", "-j", *args], timeout=5))
            for name, args in commands.items()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    args = parser.parse_args()
    current = snapshot()
    result = {"kernel": current}
    if args.baseline is not None:
        baseline = json.loads(args.baseline.read_text())["kernel"]
        differences = [name for name in current if normalize(current[name]) != normalize(baseline[name])]
        result.update({"restored": not differences, "differences": differences})
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key != "kernel"}))
    if args.baseline is not None and result["differences"]:
        raise SystemExit("Kernel state differs from before capture")
