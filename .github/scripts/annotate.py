"""Turns an xcodebuild log into GitHub annotations: every compiler error (with file and line),
the first warnings, and a one-line summary. Annotations show on the run page and the API."""
import os, re, sys

log_path, title = sys.argv[1], sys.argv[2]
text = open(log_path, errors="replace").read() if os.path.exists(log_path) else ""
root = os.environ.get("GITHUB_WORKSPACE", "")
pat = re.compile(r"^(/[^:\n]+\.swift):(\d+):(\d+): (error|warning): (.+)$", re.M)

def esc(s):
    return s.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")

seen, errors, warnings = set(), [], []
for path, line, col, kind, msg in pat.findall(text):
    key = (path, line, kind, msg)
    if key in seen:
        continue
    seen.add(key)
    rel = os.path.relpath(path, root) if root and path.startswith(root) else path
    (errors if kind == "error" else warnings).append((rel, line, col, msg))

for rel, line, col, msg in errors[:50]:
    print(f"::error file={rel},line={line},col={col},title={esc(title)}::{esc(msg)}")
for rel, line, col, msg in warnings[:20]:
    print(f"::warning file={rel},line={line},col={col},title={esc(title)}::{esc(msg)}")

# Errors that aren't in a Swift file (project, Info.plist, asset catalog, linking, signing...),
# and the list of commands that failed, so a failed build always says why.
if "BUILD SUCCEEDED" not in text and "ARCHIVE SUCCEEDED" not in text:
    other = []
    for line in text.splitlines():
        stripped = line.strip()
        if ("error:" in stripped or stripped.startswith("error ")) and not pat.match(stripped) and stripped not in other:
            other.append(stripped)
    failed = re.search(r"The following build commands failed:\n((?:.+\n){1,12})", text)
    if failed:
        other.append("Failed commands: " + " | ".join(l.strip() for l in failed.group(1).splitlines() if l.strip()))
    for line in other[:25]:
        print(f"::error title={esc(title)}::{esc(line[:900])}")

compiled = len(set(re.findall(r"(?:SwiftCompile|CompileSwift) \S+ \S+ (\S+\.swift)", text)))
result = ("SUCCEEDED" if ("BUILD SUCCEEDED" in text or "ARCHIVE SUCCEEDED" in text)
          else ("FAILED" if ("BUILD FAILED" in text or "ARCHIVE FAILED" in text) else "UNKNOWN"))
print(f"::notice title={esc(title)}::BUILD {result} · {len(errors)} errors · {len(warnings)} warnings · {compiled} Swift files compiled")
