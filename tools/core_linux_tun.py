"""Stage the reviewed Linux-only managed-TUN dependency extensions."""
import json
from pathlib import Path
import subprocess

from core_sources import copy_module_sources


def prepare_linux_tun(lock, env, source_dir, replacements, digest, replace_once):
    specification = lock["linuxTUN"]
    for relative, expected in specification["upstreamFiles"].items():
        if digest((source_dir / relative).read_bytes()) != expected:
            raise RuntimeError("Linux TUN upstream file changed: " + relative)
    modules = {}
    for name, entry in specification["modules"].items():
        result = subprocess.run(["go", "mod", "download", "-json", entry["module"] + "@" + entry["version"]],
                                cwd=source_dir, env=env, check=True, capture_output=True, text=True, timeout=120)
        module = json.loads(result.stdout)
        if module.get("Sum") != entry["sum"]:
            raise RuntimeError("Linux TUN dependency checksum mismatch: " + name)
        destination = source_dir / "rainlink-modules" / name
        copy_module_sources(Path(module["Dir"]), destination)
        for relative, expected in entry["files"].items():
            if digest((destination / relative).read_bytes()) != expected:
                raise RuntimeError("Linux TUN dependency file changed: " + name + "/" + relative)
        modules[name] = destination
    manifest = source_dir / "go.mod"
    content = manifest.read_text(encoding="utf-8")
    if "\nreplace " in content:
        raise RuntimeError("Review new upstream replacements before managed TUN build")
    for name, entry in specification["modules"].items():
        content += "\nreplace " + entry["module"] + " => ./rainlink-modules/" + name + "\n"
    manifest.write_bytes(content.encode("utf-8"))

    def patch(path, transform):
        content = path.read_text(encoding="utf-8")
        path.write_bytes(transform(content).encode("utf-8"))

    patch(source_dir / "option/tun.go", lambda content: replace_once(content, "type TunInboundOptions struct {",
        'type TunInboundOptions struct {\n\tRainLinkManaged bool `json:"rainlink_managed,omitempty"`'))
    patch(source_dir / "protocol/tun/inbound.go", lambda content: replace_once(replace_once(content,
        "\taddress := options.Address", "\tif options.RainLinkManaged && (runtime.GOOS != \"linux\" || options.AutoRedirect || options.Platform != nil || len(options.RouteAddressSet) != 0 || len(options.RouteExcludeAddressSet) != 0) {\n"
        '\t\treturn nil, E.New("unsupported RainLink-managed TUN configuration")\n\t}\n\taddress := options.Address'),
        "\t\ttunOptions: tun.Options{", "\t\ttunOptions: tun.Options{\n\t\t\tRainLinkManaged: options.RainLinkManaged,"))
    patch(modules["sing-tun"] / "tun.go", lambda content: replace_once(content, "type Options struct {",
        "type Options struct {\n\tRainLinkManaged bool"))

    def patch_native(content):
        changes = [
            ("func New(options Options) (Tun, error) {", "func New(options Options) (Tun, error) {\n"
             "\tif options.RainLinkManaged {\n\t\tif err := rainLinkValidate(options); err != nil { return nil, err }\n"
             "\t\tif err := rainLinkCheckResources(options, true); err != nil { return nil, err }\n\t}\n"),
            ("open(options.Name, options.GSO)", "open(options.Name, options.GSO, options.RainLinkManaged)"),
            ("func open(name string, vnetHdr bool)", "func open(name string, vnetHdr, exclusive bool)"),
            ("flags := unix.IFF_TUN | unix.IFF_NO_PI", "flags := unix.IFF_TUN | unix.IFF_NO_PI\n\tif exclusive { flags |= unix.IFF_TUN_EXCL }"),
            ("\t\t_ = t.unsetRoute0(tunLink)", "\t\tif !t.options.RainLinkManaged { _ = t.unsetRoute0(tunLink) }"),
            ("\tt.setSearchDomainForSystemdResolved()", "\tif !t.options.RainLinkManaged { t.setSearchDomainForSystemdResolved() }"),
            ("func (t *NativeTun) Close() error {", "func (t *NativeTun) Close() error {\n"
             "\t// The guardian owns exact rule recovery. Closing our exclusive FD\n"
             "\t// removes this device and its routes without deleting by name.\n"
             "\tif t.options.RainLinkManaged { return common.Close(common.PtrOrNil(t.tunFile)) }"),
            ("func (t *NativeTun) UpdateRouteOptions(tunOptions Options) error {",
             "func (t *NativeTun) UpdateRouteOptions(tunOptions Options) error {\n"
             '\tif t.options.RainLinkManaged || tunOptions.RainLinkManaged { return errors.New("RainLink-managed TUN policy requires reconnect") }'),
            ("func (t *NativeTun) setRules() error {", "func (t *NativeTun) setRules() error {\n"
             "\tif t.options.RainLinkManaged { return rainLinkInstallRules(t.options, t.rules()) }"),
            ("func (t *NativeTun) unsetRules() error {", "func (t *NativeTun) unsetRules() error {\n"
             "\tif t.options.RainLinkManaged { return nil }"),
            ("func (t *NativeTun) resetRules() error {", "func (t *NativeTun) resetRules() error {\n"
             '\tif t.options.RainLinkManaged { return errors.New("RainLink-managed TUN policy requires reconnect") }'),
        ]
        for old, new in changes:
            content = replace_once(content, old, new)
        return content

    patch(modules["sing-tun"] / "tun_linux.go", patch_native)
    patch(modules["netlink"] / "rule.go", lambda content: replace_once(content, "type Rule struct {",
        "type Rule struct {\n\tProtocol uint8"))

    def patch_rule(content):
        content = replace_once(content, "\tif rule.IPProto > 0 {",
            "\tif rule.Protocol != 0 {\n\t\treq.AddData(nl.NewRtAttr(unix.FRA_PROTOCOL, []byte{rule.Protocol}))\n\t}\n\tif rule.IPProto > 0 {")
        return replace_once(content, "\t\t\tcase unix.RTA_TABLE:",
            '\t\t\tcase unix.FRA_PROTOCOL:\n\t\t\t\tif len(attrs[j].Value) != 1 { return nil, fmt.Errorf("invalid policy protocol attribute") }\n'
            "\t\t\t\trule.Protocol = attrs[j].Value[0]\n\t\t\tcase unix.RTA_TABLE:")

    patch(modules["netlink"] / "rule_linux.go", patch_rule)
    # Name the embedded field so the pinned dependency passes go vet without
    # relying on struct field order. This preserves the upstream wire data.
    patch(modules["netlink"] / "addr_linux.go", lambda content: replace_once(content,
        "cachedata := nl.IfaCacheInfo{unix.IfaCacheinfo{",
        "cachedata := nl.IfaCacheInfo{IfaCacheinfo: unix.IfaCacheinfo{"))
    root = Path(__file__).resolve().parent.parent
    for extension in sorted((root / "native/core/linux_tun").glob("*.go")):
        replacements[str(modules["sing-tun"] / extension.name)] = str(extension)
    modified = [source_dir / name for name in ["option/tun.go", "protocol/tun/inbound.go"]]
    modified += [modules[name] / relative for name, entry in specification["modules"].items() for relative in entry["files"]]
    subprocess.run(["gofmt", "-w", *map(str, modified)], check=True, timeout=30)
