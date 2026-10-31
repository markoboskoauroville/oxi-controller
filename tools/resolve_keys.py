#!/usr/bin/env python3
"""resolve_keys.py: Marko's own DaVinci Resolve keyboard profile, read (Marko, 31.10.2026: "Please read my keyboard shortcuts
and work with my own keyboard profile. You need to always read the keyboard to find the right key to trigger").

    python3 tools/resolve_keys.py                 every action with its keys, as JSON (~/.config/e16-resolve-keys.json too)
    python3 tools/resolve_keys.py solo play       the actions whose id contains these words, with keys or "NO SHORTCUT"

Source: ~/Library/Preferences/Blackmagic Design/DaVinci Resolve/keyboard.preset.xml, <PresetListBA> = a Qt data stream:
  uint32 preset count, then per preset: QString name (uint32 byte length + UTF-16BE), uint32 blob length, uint32 1, uint32 action count,
  then per action: QString action id, uint32 number of shortcuts, per shortcut uint32 number of keys + that many uint32 key
  codes (Qt: key | modifiers; 0x02000000 Shift, 0x04000000 Ctrl = ⌘ on the Mac, 0x08000000 Alt = ⌥, 0x10000000 Meta = ⌃).
The first preset is the one in use ("MARKO DAVINCHI KEYBOARD Keys", 31.10.2026).
"""
import json, os, re, struct, sys

PRESET = os.path.expanduser("~/Library/Preferences/Blackmagic Design/DaVinci Resolve/keyboard.preset.xml")
OUT = os.path.expanduser("~/.config/e16-resolve-keys.json")
MODS = [(0x10000000, "⌃"), (0x08000000, "⌥"), (0x02000000, "⇧"), (0x04000000, "⌘")]
NAMED = {0x20: "Space", 0x01000000: "Esc", 0x01000001: "Tab", 0x01000003: "Backspace", 0x01000004: "Return",
         0x01000005: "Enter", 0x01000007: "Delete", 0x01000010: "Home", 0x01000011: "End", 0x01000012: "←",
         0x01000013: "↑", 0x01000014: "→", 0x01000015: "↓", 0x01000016: "PageUp", 0x01000017: "PageDown"}


def keyname(code):
    mods = "".join(sym for bit, sym in MODS if code & bit)
    k = code & 0x01FFFFFF
    if k in NAMED: name = NAMED[k]
    elif 0x01000030 <= k <= 0x01000052: name = "F%d" % (k - 0x01000030 + 1)
    elif 0x20 < k < 0x7F: name = chr(k)
    else: name = "0x%X" % k
    return mods + name


def read():
    x = open(PRESET, encoding="utf-8").read()
    b = bytes.fromhex(re.search(r"<PresetListBA>([0-9a-f]+)</PresetListBA>", x).group(1))
    p = 0
    def u32():
        nonlocal p; v = struct.unpack(">I", b[p:p + 4])[0]; p += 4; return v
    def qstr():
        nonlocal p; n = u32()
        if n == 0xFFFFFFFF: return ""
        s = b[p:p + n].decode("utf-16-be"); p += n; return s
    presets = u32(); u32()                    # how many presets, then (always 1 here) the list's own count
    name = qstr(); u32(); u32()               # the preset's name, its blob length, a 1
    count = u32()
    actions = {}
    for _ in range(count):
        aid = qstr()
        keys = []
        for _ in range(u32()):
            seq = [keyname(u32()) for _ in range(u32())]
            keys.append(" ".join(seq))
        actions[aid] = keys
    return {"preset": name, "presets": presets, "actions": actions}


if __name__ == "__main__":
    d = read()
    json.dump(d, open(OUT, "w"), indent=1, ensure_ascii=False)
    words = [w.lower() for w in sys.argv[1:]]
    if not words:
        print(f"{d['preset']}: {len(d['actions'])} actions, {sum(1 for k in d['actions'].values() if k)} with a shortcut → {OUT}")
    for aid, keys in sorted(d["actions"].items()):
        if words and any(w in aid.lower() for w in words):
            print(f"  {aid:60s} {', '.join(keys) if keys else 'NO SHORTCUT'}")
