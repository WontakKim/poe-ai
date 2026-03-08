#!/usr/bin/env python3
"""PoB XML manipulation tool.

Subcommands:
  swap-item   -- Replace item text in a slot
  swap-gem    -- Replace a gem in a skill group
  set-config  -- Set a config input value
  encode      -- Encode XML to PoB build code
  list-slots  -- List item slots as JSON
  list-gems   -- List gem groups as JSON

Usage:
  python3 pob-xml-manipulate.py <subcommand> --input build.xml [options]

Output goes to stdout. Errors go to stderr with non-zero exit.
"""

import argparse
import base64
import glob as _glob
import json
import os
import sys
import xml.etree.ElementTree as ET
import zlib


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def parse_xml(path):
    """Parse XML from file path. Supports /dev/stdin for piped input."""
    try:
        tree = ET.parse(path)
    except ET.ParseError as exc:
        print(f"ERROR: XML parse error: {exc}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"ERROR: file not found: {path}", file=sys.stderr)
        sys.exit(1)
    return tree


def write_xml(tree):
    """Write XML tree to stdout as UTF-8 text."""
    root = tree.getroot()
    ET.indent(tree, space="\t")
    xml_bytes = ET.tostring(root, encoding="unicode", xml_declaration=False)
    # PoB XML starts with <?xml version="1.0" ...?> in file saves,
    # but build codes use raw XML without declaration.
    print('<?xml version="1.0" encoding="UTF-8"?>')
    print(xml_bytes)


def find_items_section(root):
    """Return the <Items> element, creating it if absent."""
    items = root.find("Items")
    if items is None:
        items = ET.SubElement(root, "Items")
    return items


def find_skills_section(root):
    """Return the first <SkillSet> inside <Skills>, or <Skills> itself for
    builds that have no SkillSet wrapper."""
    skills = root.find("Skills")
    if skills is None:
        print("ERROR: no <Skills> section found", file=sys.stderr)
        sys.exit(1)
    # Modern PoB wraps groups in <SkillSet>; older builds put <Skill> directly
    skill_set = skills.find("SkillSet")
    if skill_set is not None:
        return skill_set
    return skills


def find_config_section(root):
    """Return the <Config> element, creating it if absent."""
    config = root.find("Config")
    if config is None:
        config = ET.SubElement(root, "Config")
    return config


def next_item_id(items):
    """Return the next unused integer item id."""
    max_id = 0
    for item in items.findall("Item"):
        try:
            item_id = int(item.get("id", "0"))
        except ValueError:
            continue
        if item_id > max_id:
            max_id = item_id
    return max_id + 1


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_swap_item(args):
    tree = parse_xml(args.input)
    root = tree.getroot()
    items = find_items_section(root)

    # Normalise item text: convert literal \n to newlines
    item_text = args.item_text.replace("\\n", "\n")

    # Search for slot in direct children and inside ItemSet elements
    slot_elem = None
    for s in items.findall("Slot"):
        if s.get("name") == args.slot:
            slot_elem = s
            break
    if slot_elem is None:
        for item_set in items.findall("ItemSet"):
            for s in item_set.findall("Slot"):
                if s.get("name") == args.slot:
                    slot_elem = s
                    break
            if slot_elem is not None:
                break

    if slot_elem is not None:
        item_id = slot_elem.get("itemId")
        # Find the corresponding <Item>
        item_elem = None
        for it in items.findall("Item"):
            if it.get("id") == item_id:
                item_elem = it
                break
        if item_elem is None:
            print(f"ERROR: <Item id=\"{item_id}\"> not found", file=sys.stderr)
            sys.exit(1)
        item_elem.text = item_text
    else:
        # Create new Item + Slot
        new_id = next_item_id(items)
        new_item = ET.SubElement(items, "Item")
        new_item.set("id", str(new_id))
        new_item.text = item_text
        new_slot = ET.SubElement(items, "Slot")
        new_slot.set("name", args.slot)
        new_slot.set("itemId", str(new_id))

    write_xml(tree)


def _lookup_gem_ids(gem_db_path, gem_name):
    """Look up skillId and gemId for a gem by its display name."""
    for f in sorted(_glob.glob(os.path.join(gem_db_path, "*.json"))):
        if os.path.basename(f) == "source.json":
            continue
        with open(f) as fh:
            gems = json.load(fh)
        if not isinstance(gems, list):
            continue
        for g in gems:
            if g.get("name") == gem_name:
                skill_id = g["id"]
                if skill_id.startswith("Support"):
                    gem_id = "Metadata/Items/Gems/" + skill_id.replace(
                        "Support", "SupportGem", 1
                    )
                else:
                    gem_id = "Metadata/Items/Gems/SkillGem" + skill_id
                return skill_id, gem_id
    return None, None


def cmd_swap_gem(args):
    tree = parse_xml(args.input)
    root = tree.getroot()
    skill_set = find_skills_section(root)

    skill_groups = skill_set.findall("Skill")
    group_idx = args.group - 1  # 1-based to 0-based
    if group_idx < 0 or group_idx >= len(skill_groups):
        print(
            f"ERROR: group {args.group} out of range "
            f"(1..{len(skill_groups)})",
            file=sys.stderr,
        )
        sys.exit(1)

    # Resolve new gem IDs from DB if provided
    new_skill_id, new_gem_id = None, None
    if args.gem_db:
        new_skill_id, new_gem_id = _lookup_gem_ids(args.gem_db, args.new)

    group = skill_groups[group_idx]
    found = False
    for gem in group.findall("Gem"):
        if gem.get("nameSpec") == args.old:
            gem.set("nameSpec", args.new)
            if new_skill_id:
                gem.set("skillId", new_skill_id)
                gem.set("variantId", new_skill_id)
            if new_gem_id:
                gem.set("gemId", new_gem_id)
            found = True
            break

    if not found:
        print(
            f"ERROR: gem \"{args.old}\" not found in group {args.group}",
            file=sys.stderr,
        )
        sys.exit(1)

    write_xml(tree)


def cmd_set_config(args):
    tree = parse_xml(args.input)
    root = tree.getroot()
    config = find_config_section(root)

    key = args.key
    value = args.value

    # Detect value type
    if value.lower() in ("true", "false"):
        attr_name = "boolean"
        attr_value = value.lower()
    else:
        try:
            float(value)
            attr_name = "number"
            attr_value = value
        except ValueError:
            attr_name = "string"
            attr_value = value

    # Find existing input or create new
    input_elem = None
    for inp in config.findall("Input"):
        if inp.get("name") == key:
            input_elem = inp
            break

    if input_elem is None:
        input_elem = ET.SubElement(config, "Input")
        input_elem.set("name", key)

    # Clear old type attributes before setting new
    for old_attr in ("boolean", "number", "string"):
        if old_attr in input_elem.attrib:
            del input_elem.attrib[old_attr]

    input_elem.set(attr_name, attr_value)
    write_xml(tree)


def cmd_encode(args):
    tree = parse_xml(args.input)
    root = tree.getroot()
    xml_bytes = ET.tostring(root, encoding="UTF-8", xml_declaration=True)

    # Raw deflate: strip 2-byte zlib header and 4-byte checksum
    compressed = zlib.compress(xml_bytes, 9)
    raw_deflated = compressed[2:-4]

    # Base64 encode, then URL-safe substitution (PoB convention)
    b64 = base64.b64encode(raw_deflated).decode("ascii")
    code = b64.replace("+", "-").replace("/", "_").rstrip("=")
    print(code)


def cmd_list_slots(args):
    tree = parse_xml(args.input)
    root = tree.getroot()
    items = find_items_section(root)

    # Build item id → text lookup
    item_map = {}
    for item in items.findall("Item"):
        item_id = item.get("id")
        text = (item.text or "").strip()
        item_map[item_id] = text

    result = []
    # Search for slots in direct children and inside ItemSet elements
    all_slots = list(items.findall("Slot"))
    for item_set in items.findall("ItemSet"):
        all_slots.extend(item_set.findall("Slot"))
    for slot in all_slots:
        name = slot.get("name", "")
        item_id = slot.get("itemId", "")
        text = item_map.get(item_id, "")
        # First 3 lines as preview
        lines = text.split("\n")
        preview = "\n".join(lines[:3])
        result.append({
            "name": name,
            "itemId": item_id,
            "preview": preview,
        })

    json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
    print()


def cmd_list_gems(args):
    tree = parse_xml(args.input)
    root = tree.getroot()
    skill_set = find_skills_section(root)

    result = []
    for idx, skill in enumerate(skill_set.findall("Skill"), start=1):
        slot = skill.get("slot", "")
        gems = []
        for gem in skill.findall("Gem"):
            gems.append({
                "nameSpec": gem.get("nameSpec", ""),
                "skillId": gem.get("skillId", ""),
                "level": gem.get("level", ""),
                "quality": gem.get("quality", ""),
                "enabled": gem.get("enabled", "true"),
            })
        result.append({
            "group": idx,
            "slot": slot,
            "gems": gems,
        })

    json.dump(result, sys.stdout, indent=2, ensure_ascii=False)
    print()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="PoB XML manipulation tool",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # swap-item
    p_si = sub.add_parser("swap-item", help="Replace item text in a slot")
    p_si.add_argument("--input", required=True, help="Input XML path")
    p_si.add_argument("--slot", required=True, help="Slot name (e.g. 'Body Armour')")
    p_si.add_argument("--item-text", required=True, help="New item text (use \\n for newlines)")

    # swap-gem
    p_sg = sub.add_parser("swap-gem", help="Replace a gem in a skill group")
    p_sg.add_argument("--input", required=True, help="Input XML path")
    p_sg.add_argument("--group", required=True, type=int, help="Skill group index (1-based)")
    p_sg.add_argument("--old", required=True, help="Current gem nameSpec")
    p_sg.add_argument("--new", required=True, help="New gem nameSpec")
    p_sg.add_argument("--gem-db", default=None, help="Path to skill-gem DB dir for ID resolution")

    # set-config
    p_sc = sub.add_parser("set-config", help="Set a config input value")
    p_sc.add_argument("--input", required=True, help="Input XML path")
    p_sc.add_argument("--key", required=True, help="Config input name")
    p_sc.add_argument("--value", required=True, help="Value (auto-detects type)")

    # encode
    p_en = sub.add_parser("encode", help="Encode XML to PoB build code")
    p_en.add_argument("--input", required=True, help="Input XML path")

    # list-slots
    p_ls = sub.add_parser("list-slots", help="List item slots as JSON")
    p_ls.add_argument("--input", required=True, help="Input XML path")

    # list-gems
    p_lg = sub.add_parser("list-gems", help="List gem groups as JSON")
    p_lg.add_argument("--input", required=True, help="Input XML path")

    args = parser.parse_args()

    dispatch = {
        "swap-item": cmd_swap_item,
        "swap-gem": cmd_swap_gem,
        "set-config": cmd_set_config,
        "encode": cmd_encode,
        "list-slots": cmd_list_slots,
        "list-gems": cmd_list_gems,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
