#!/usr/bin/env python3
"""Codec de DNS Stamps (spec: https://dnscrypt.info/stamps-specifications).
Solo lo necesario: DoH (0x02). encode para generar, decode para verificar."""
import base64, sys, json

def b64u_enc(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")

def b64u_dec(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def lp(b: bytes) -> bytes:              # length-prefixed
    assert len(b) < 128
    return bytes([len(b)]) + b

def encode_doh(host: str, path: str, addr: str = "", props: int = 0,
               hashes=()) -> str:
    out = bytes([0x02])
    out += props.to_bytes(8, "little")
    out += lp(addr.encode())
    if hashes:                            # VLP: bit alto = continua
        for i, h in enumerate(hashes):
            flag = 0x80 if i < len(hashes) - 1 else 0x00
            out += bytes([len(h) | flag]) + h
    else:
        out += b"\x00"
    out += lp(host.encode())
    out += lp(path.encode())
    return "sdns://" + b64u_enc(out)

def decode(stamp: str) -> dict:
    assert stamp.startswith("sdns://")
    b = b64u_dec(stamp[7:]); i = 0
    proto = b[i]; i += 1
    assert proto == 0x02, f"no es DoH (proto={proto:#x})"
    props = int.from_bytes(b[i:i+8], "little"); i += 8
    alen = b[i]; i += 1
    addr = b[i:i+alen].decode(); i += alen
    hashes = []
    while True:
        hl = b[i]; i += 1
        cont = hl & 0x80; hl &= 0x7F
        if hl: hashes.append(b[i:i+hl].hex()); i += hl
        if not cont: break
    hlen = b[i]; i += 1
    host = b[i:i+hlen].decode(); i += hlen
    plen = b[i]; i += 1
    path = b[i:i+plen].decode(); i += plen
    assert i == len(b), f"bytes sobrantes: {len(b)-i}"
    return {"proto": "DoH", "props": props, "addr": addr,
            "hashes": hashes, "host": host, "path": path}

if __name__ == "__main__":
    if sys.argv[1] == "encode":
        # encode host path [addr] [props]
        host, path = sys.argv[2], sys.argv[3]
        addr  = sys.argv[4] if len(sys.argv) > 4 else ""
        props = int(sys.argv[5]) if len(sys.argv) > 5 else 0
        print(encode_doh(host, path, addr, props))
    elif sys.argv[1] == "decode":
        print(json.dumps(decode(sys.argv[2]), indent=1))
