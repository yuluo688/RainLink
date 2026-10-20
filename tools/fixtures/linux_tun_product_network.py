"""Loopback-free TCP/UDP/DNS receipts for a disposable Linux product VM.

Run ``serve`` inside the origin network namespace. ``probe`` uses ordinary OS
sockets, never the client's local proxy port, and checks the origin's observed
source address. All addresses are private QA addresses; no credentials are read.
"""

import argparse
import ipaddress
import json
from pathlib import Path
import secrets
import socket
import socketserver
import struct
import threading


# Keep the proxy/DNS entry on-link and the origin off-link. Locked sing-tun
# preserves connected routes, so an on-link origin would bypass TUN in every
# mode and could never prove whether the selected proxy mode is working.
ENTRY_IPV4 = "10.77.0.2"
ENTRY_IPV6 = "fd77::2"
IPV4 = "10.78.0.2"
IPV6 = "fd78::2"
PORT = 18080
SOCKET_TIMEOUT = 8
MAX_REQUEST = 2048


def serve(log: Path):
    lock = threading.Lock()

    def record(value):
        with lock, log.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(value, sort_keys=True) + "\n")
            stream.flush()

    def receipt(raw, source, kind):
        value = json.loads(raw)
        if set(value) != {"nonce"} or not isinstance(value["nonce"], str):
            raise ValueError("Invalid QA receipt request")
        result = {"nonce": value["nonce"], "source": source, "kind": kind}
        record(result)
        return json.dumps(result, sort_keys=True).encode() + b"\n"

    class TCP(socketserver.StreamRequestHandler):
        def handle(self):
            self.connection.settimeout(SOCKET_TIMEOUT)
            raw = self.rfile.readline(MAX_REQUEST + 1)
            if not raw.endswith(b"\n") or len(raw) > MAX_REQUEST:
                raise ValueError("Invalid QA TCP framing")
            self.wfile.write(receipt(raw, self.client_address[0], "tcp"))

    class UDP(socketserver.BaseRequestHandler):
        def handle(self):
            raw, endpoint = self.request
            if len(raw) > MAX_REQUEST:
                raise ValueError("Invalid QA UDP framing")
            endpoint.sendto(receipt(raw, self.client_address[0], "udp"), self.client_address)

    class DNS(socketserver.BaseRequestHandler):
        def handle(self):
            raw, endpoint = self.request
            if len(raw) < 17 or len(raw) > MAX_REQUEST or raw[4:6] != b"\x00\x01":
                raise ValueError("Invalid QA DNS header")
            position, labels = 12, []
            while raw[position]:
                length = raw[position]
                if length > 63 or position + length + 1 >= len(raw):
                    raise ValueError("Invalid QA DNS label")
                labels.append(raw[position + 1:position + length + 1].decode("ascii"))
                position += length + 1
            position += 1
            query_type, query_class = struct.unpack("!HH", raw[position:position + 4])
            if query_type not in (1, 28) or query_class != 1:
                raise ValueError("Unsupported QA DNS question")
            address = ipaddress.ip_address(IPV4 if query_type == 1 else IPV6).packed
            answer = b"\xc0\x0c" + struct.pack("!HHIH", query_type, 1, 0, len(address)) + address
            response = raw[:2] + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0) + raw[12:position + 4] + answer
            record({"kind": "dns", "name": ".".join(labels), "queryType": query_type,
                    "source": self.client_address[0]})
            endpoint.sendto(response, self.client_address)

    servers = []
    for family, address, entry in [(socket.AF_INET, IPV4, ENTRY_IPV4),
                                    (socket.AF_INET6, IPV6, ENTRY_IPV6)]:
        for base, handler, port, listen in [(socketserver.ThreadingTCPServer, TCP, PORT, address),
                                           (socketserver.ThreadingUDPServer, UDP, PORT, address),
                                           (socketserver.ThreadingUDPServer, DNS, 53, entry)]:
            server_type = type("QAServer", (base,), {"address_family": family,
                "allow_reuse_address": True, "daemon_threads": True})
            server = server_type((listen, port), handler)
            servers.append(server)
            threading.Thread(target=server.serve_forever, daemon=True).start()
    print("ORIGIN_RECEIPTS_READY", flush=True)
    try:
        threading.Event().wait()
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()


def probe(prefix: str, proxy: bool, dns: bool, output: Path):
    receipts = []
    try:
        for family, target, expected in [(socket.AF_INET, IPV4, IPV4 if proxy else "10.77.0.1"),
                                          (socket.AF_INET6, IPV6, IPV6 if proxy else "fd77::1")]:
            for kind, socket_type in [("tcp", socket.SOCK_STREAM), ("udp", socket.SOCK_DGRAM)]:
                nonce = f"{prefix}-{family.name}-{kind}-{secrets.token_hex(4)}"
                with socket.socket(family, socket_type) as client:
                    client.settimeout(SOCKET_TIMEOUT)
                    client.connect((target, PORT))
                    request = json.dumps({"nonce": nonce}).encode() + b"\n"
                    client.sendall(request)
                    data = b""
                    while not data.endswith(b"\n"):
                        chunk = client.recv(MAX_REQUEST)
                        if not chunk:
                            raise ValueError("Incomplete QA response")
                        data += chunk
                        if len(data) > MAX_REQUEST:
                            raise ValueError("Oversized QA response")
                value = json.loads(data)
                if value != {"nonce": nonce, "source": expected, "kind": kind}:
                    raise AssertionError(f"Unexpected origin receipt: {value}")
                receipts.append(value)
        if dns:
            for family, target, query_type, address in [(socket.AF_INET, "192.0.2.53", 1, IPV4),
                                                        (socket.AF_INET6, "2001:db8::53", 28, IPV6)]:
                nonce = f"{prefix}-{secrets.token_hex(4)}.rainlink.test"
                query_id = secrets.randbelow(65536)
                labels = b"".join(bytes([len(label)]) + label.encode() for label in nonce.split(".")) + b"\x00"
                query = struct.pack("!HHHHHH", query_id, 0x0100, 1, 0, 0, 0) + labels + struct.pack("!HH", query_type, 1)
                with socket.socket(family, socket.SOCK_DGRAM) as client:
                    client.settimeout(SOCKET_TIMEOUT)
                    client.sendto(query, (target, 53))
                    data, _ = client.recvfrom(MAX_REQUEST)
                packed = ipaddress.ip_address(address).packed
                if (len(data) < 12 or data[:2] != query[:2] or
                        data[3] & 0x0F or data[6:8] != b"\x00\x01" or not data.endswith(packed)):
                    raise AssertionError("DNS was not intercepted and resolved by the QA server")
                receipts.append({"kind": "dns", "name": nonce, "queryType": query_type, "answer": address})
    except Exception as error:
        output.write_text(json.dumps({"passed": False, "receipts": receipts,
            "error": str(error)}, indent=2) + "\n", encoding="utf-8")
        raise
    output.write_text(json.dumps({"passed": True, "receipts": receipts}, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "receipts": len(receipts)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["serve", "probe"])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--prefix", default="rainlink-qa")
    parser.add_argument("--proxy", action="store_true")
    parser.add_argument("--dns", action="store_true")
    args = parser.parse_args()
    if args.mode == "serve":
        serve(args.output)
    else:
        probe(args.prefix, args.proxy, args.dns, args.output)
