#!/usr/bin/env python3
"""Writes the App Store Connect .p8 key from $P8_TEXT to a clean PEM file, whatever shape it
arrived in: real or escaped (\\n) line breaks, quotes or spaces around it, base64 of the whole
file, or just the key body without the BEGIN/END lines. Prints only shapes, never key text."""
import base64, os, re, sys

out = sys.argv[1]
raw = os.environ.get("P8_TEXT", "")
text = raw.replace("\\r", "").replace("\\n", "\n").replace("\r", "").strip().strip('"\'').strip()

def shape(value):
    """What kind of value this is, without showing it (a file path is fine to show)."""
    if value.startswith(("/", "~")):
        return f"a file path: {value}"
    for prefix in ("Encrypted(", "@", "$", "http"):
        if value.startswith(prefix):
            return f"a value starting with {prefix}"
    return "text starting with " + ("a letter" if value[:1].isalpha() else "a digit" if value[:1].isdigit() else "a symbol")


def find_key_file():
    """Codemagic can hand over a path, or keep the integration's key as a file on the Mac."""
    path = os.path.expanduser(os.path.expandvars(text))
    if len(text) < 1024 and os.path.isfile(path):
        return path
    key_id = os.environ.get("ASC_KEY_ID", "")
    home = os.path.expanduser("~")
    for root, dirs, files in os.walk(home):
        depth = root[len(home):].count(os.sep)
        dirs[:] = [d for d in dirs if depth < 3 and d not in ("Library", "redclip-tmp", "clone", "programs", "Applications")]
        for name in files:
            if name.endswith(".p8") and (not key_id or key_id in name):
                return os.path.join(root, name)
    return None


if "BEGIN" not in text:
    print(f"The key arrived as {shape(text)}.")
    found = find_key_file()
    if found:
        print(f"Reading the key from {found}.")
        text = open(found, encoding="utf-8", errors="replace").read().replace("\r", "").strip()

if "BEGIN" not in text:
    # Maybe base64 of the whole .p8 file, or of the key itself (DER).
    compact = re.sub(r"\s", "", text)
    try:
        decoded = base64.b64decode(compact + "=" * (-len(compact) % 4))
    except Exception:
        decoded = b""
    if b"BEGIN" in decoded:
        text = decoded.decode("utf-8", "replace").replace("\r", "").strip()
    else:
        text = f"-----BEGIN PRIVATE KEY-----\n{compact}\n-----END PRIVATE KEY-----"

m = re.search(r"-----BEGIN ([A-Z ]+)-----(.*?)-----END ([A-Z ]+)-----", text, re.S)
if not m:
    print(f"::error title=API key::Couldn't find the key in it ({len(raw)} characters, "
          f"{raw.count(chr(10)) + 1} lines, BEGIN line: {'yes' if 'BEGIN' in raw else 'no'}, "
          f"END line: {'yes' if 'END' in raw else 'no'}).")
    sys.exit(1)
body = re.sub(r"[^A-Za-z0-9+/=]", "", m.group(2))
lines = "\n".join(body[i:i + 64] for i in range(0, len(body), 64))
with open(out, "w") as f:
    f.write(f"-----BEGIN {m.group(1)}-----\n{lines}\n-----END {m.group(1)}-----\n")
print(f"Key text: {len(raw)} characters, {raw.count(chr(10)) + 1} lines, "
      f"escaped line breaks: {'yes' if chr(92) + 'n' in raw else 'no'}, "
      f"key body: {len(body)} characters (an Apple .p8 has 184).")
