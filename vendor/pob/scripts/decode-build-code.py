#!/usr/bin/env python3
"""Decode PoB build codes to XML. Stdin: build code, Stdout: XML."""
import sys, base64, zlib

def main():
    code = sys.stdin.read().strip()
    if not code:
        print("ERROR: Empty build code", file=sys.stderr)
        sys.exit(1)

    # URL-safe base64 → standard base64
    code = code.replace("-", "+").replace("_", "/")
    # Fix padding
    padding = 4 - len(code) % 4
    if padding < 4:
        code += "=" * padding

    try:
        data = base64.b64decode(code)
    except Exception as e:
        print(f"ERROR: Invalid base64: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        xml = zlib.decompress(data, -15)  # raw deflate (no header/checksum)
    except Exception as e:
        print(f"ERROR: Decompression failed: {e}", file=sys.stderr)
        sys.exit(1)

    sys.stdout.write(xml.decode("utf-8"))

if __name__ == "__main__":
    main()
