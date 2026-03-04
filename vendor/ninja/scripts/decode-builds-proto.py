#!/usr/bin/env python3
"""Decode poe.ninja builds protobuf responses.

Usage:
    python3 decode-builds-proto.py search     < input.pb > output.json
    python3 decode-builds-proto.py dictionary < input.pb > output.json

Modes:
    search     - Decode search response: total, dimensions[], dictionaries[]
    dictionary - Decode dictionary response: id, values[]

Uses only Python stdlib (no protobuf library needed).
"""
import json
import sys


def decode_varint(data, idx):
    """Decode a protobuf varint starting at idx. Returns (value, new_idx)."""
    if idx >= len(data):
        raise ValueError(f"varint: index {idx} out of bounds (len={len(data)})")
    result = 0
    shift = 0
    for i in range(10):  # max 10 bytes for 64-bit varint
        if idx >= len(data):
            raise ValueError("varint: unexpected end of data")
        byte = data[idx]
        idx += 1
        result |= (byte & 0x7F) << shift
        if (byte & 0x80) == 0:
            return result, idx
        shift += 7
    raise ValueError("varint: exceeded 10 iterations")


def decode_field(data, idx):
    """Decode a protobuf field tag + value. Returns (field_number, wire_type, value, new_idx)."""
    tag, idx = decode_varint(data, idx)
    field_number = tag >> 3
    wire_type = tag & 0x07

    if wire_type == 0:  # varint
        value, idx = decode_varint(data, idx)
        return field_number, wire_type, value, idx
    elif wire_type == 2:  # length-delimited
        length, idx = decode_varint(data, idx)
        if idx + length > len(data):
            raise ValueError(
                f"length-delimited: need {length} bytes at {idx}, "
                f"but only {len(data) - idx} available"
            )
        value = data[idx : idx + length]
        return field_number, wire_type, value, idx + length
    elif wire_type == 1:  # 64-bit fixed
        if idx + 8 > len(data):
            raise ValueError("fixed64: unexpected end of data")
        value = data[idx : idx + 8]
        return field_number, wire_type, value, idx + 8
    elif wire_type == 5:  # 32-bit fixed
        if idx + 4 > len(data):
            raise ValueError("fixed32: unexpected end of data")
        value = data[idx : idx + 4]
        return field_number, wire_type, value, idx + 4
    else:
        raise ValueError(f"unsupported wire type {wire_type} for field {field_number}")


def decode_count_message(data):
    """Decode a Count message: field 1=number (varint). Absent field 1 -> number=0 (proto3 default)."""
    idx = 0
    number = 0  # proto3 default
    count = 0
    while idx < len(data):
        field_number, wire_type, value, idx = decode_field(data, idx)
        if field_number == 1 and wire_type == 0:
            number = value
        elif field_number == 2 and wire_type == 0:
            count = value
    return {"number": number, "count": count}


def decode_dimension(data):
    """Decode a Dimension message: field 1=id, field 2=dictionaryId, field 3=counts[]."""
    idx = 0
    dim_id = ""
    dictionary_id = ""
    counts = []
    while idx < len(data):
        field_number, wire_type, value, idx = decode_field(data, idx)
        if field_number == 1 and wire_type == 2:
            dim_id = value.decode("utf-8")
        elif field_number == 2 and wire_type == 2:
            dictionary_id = value.decode("utf-8")
        elif field_number == 3 and wire_type == 2:
            counts.append(decode_count_message(value))
    return {"id": dim_id, "dictionaryId": dictionary_id, "counts": counts}


def decode_dictionary_entry(data):
    """Decode a Dictionary entry in search response: field 1=id, field 2=hash."""
    idx = 0
    dict_id = ""
    dict_hash = ""
    while idx < len(data):
        field_number, wire_type, value, idx = decode_field(data, idx)
        if field_number == 1 and wire_type == 2:
            dict_id = value.decode("utf-8")
        elif field_number == 2 and wire_type == 2:
            dict_hash = value.decode("utf-8")
    return {"id": dict_id, "hash": dict_hash}


def decode_search_inner(data):
    """Decode inner search message: field 1=total, field 2=dimensions[], field 6=dictionaries[]."""
    idx = 0
    total = 0
    dimensions = []
    dictionaries = []
    while idx < len(data):
        field_number, wire_type, value, idx = decode_field(data, idx)
        if field_number == 1 and wire_type == 0:
            total = value
        elif field_number == 2 and wire_type == 2:
            dimensions.append(decode_dimension(value))
        elif field_number == 6 and wire_type == 2:
            dictionaries.append(decode_dictionary_entry(value))
        # Ignore other fields
    return {"total": total, "dimensions": dimensions, "dictionaries": dictionaries}


def decode_search(data):
    """Decode search response: unwrap outer message, then decode inner search."""
    # Outer wrapper: field 1 (length-delimited) contains the actual search message
    idx = 0
    while idx < len(data):
        field_number, wire_type, value, idx = decode_field(data, idx)
        if field_number == 1 and wire_type == 2:
            return decode_search_inner(value)
    raise ValueError("search: no outer wrapper field 1 found")


def decode_dictionary(data):
    """Decode dictionary response: field 1=id, field 2=values[] (repeated string)."""
    idx = 0
    dict_id = ""
    values = []
    while idx < len(data):
        field_number, wire_type, value, idx = decode_field(data, idx)
        if field_number == 1 and wire_type == 2:
            dict_id = value.decode("utf-8")
        elif field_number == 2 and wire_type == 2:
            values.append(value.decode("utf-8"))
    return {"id": dict_id, "values": values}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("search", "dictionary"):
        print("Usage: decode-builds-proto.py search|dictionary < input > output", file=sys.stderr)
        sys.exit(1)

    mode = sys.argv[1]
    data = sys.stdin.buffer.read()

    if not data:
        print("ERROR: empty input", file=sys.stderr)
        sys.exit(1)

    try:
        if mode == "search":
            result = decode_search(data)
        else:
            result = decode_dictionary(data)
    except (ValueError, UnicodeDecodeError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    json.dump(result, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
