"""Prepare the reviewed, bounded RainLink traffic accounting overlay."""

from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def replace_exact(text, old, new, count):
    if text.count(old) != count:
        raise RuntimeError("Pinned traffic accounting insertion no longer matches upstream")
    return text.replace(old, new)


def prepare_traffic(lock, source_dir, overlay_dir, replacements, digest):
    for relative, expected in lock["traffic"]["upstreamFiles"].items():
        original = source_dir / relative
        raw = original.read_bytes()
        if digest(raw) != expected:
            raise RuntimeError("Traffic source checksum mismatch: " + relative)
        content = raw.decode("utf-8")
        if relative.endswith("trafficontrol/manager.go"):
            content = replace_exact(content, "\tmemory uint64\n", "\tmemory uint64\n\trainlinkTraffic rainlinkTrafficState\n", 1)
        elif relative.endswith("trafficontrol/tracker.go"):
            content = replace_exact(content, "\tdownload := new(atomic.Int64)\n",
                                    "\tdownload := new(atomic.Int64)\n\tmeter := manager.rainlinkMeter(outbound, metadata.ProcessInfo)\n", 2)
            for direction in ("upload", "download"):
                push = "manager.Push" + direction.capitalize() + "ed(n)"
                content = replace_exact(content, push, push + "\n\t\t\tmeter." + direction + ".Add(n)", 2)
        elif relative.endswith("clashapi/server.go"):
            content = replace_exact(content, '\t\tr.Get("/traffic", traffic(s.ctx, trafficManager))\n',
                                    '\t\tr.Get("/traffic", traffic(s.ctx, trafficManager))\n'
                                    '\t\tr.Get("/rainlink/traffic", rainlinkTraffic(trafficManager))\n', 1)
        else:
            raise RuntimeError("Unreviewed traffic overlay source: " + relative)
        modified = overlay_dir / relative.replace("/", "_")
        modified.write_bytes(content.encode("utf-8"))
        replacements[str(original)] = str(modified)
    for package in ("trafficontrol", "clashapi"):
        destination = source_dir / "experimental/clashapi"
        if package == "trafficontrol":
            destination /= package
        for extension in sorted((ROOT / "native/core" / package).glob("*.go")):
            replacements[str(destination / extension.name)] = str(extension)
