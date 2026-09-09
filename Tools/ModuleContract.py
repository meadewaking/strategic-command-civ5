"""Reject cross-file calls to helpers that exist only in main's local scope."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
main = (root / "Lua/StrategicCommand.lua").read_text(encoding="utf-8-sig")
private = set(re.findall(r"local function (SC_\w+)", main))
errors = []
for path in (root / "Lua").glob("*.lua"):
    if path.name == "StrategicCommand.lua":
        continue
    source = path.read_text(encoding="utf-8-sig")
    local_definitions = set(re.findall(r"(?:local )?function (SC_\w+)", source))
    for match in re.finditer(r"\b(SC_\w+)\s*\(", source):
        if match[1] in private and match[1] not in local_definitions:
            errors.append(f"{path.name}:{source[:match.start()].count(chr(10))+1}: private main helper {match[1]}")
if errors:
    raise SystemExit("\n".join(errors))
print("PASS cross-module private helper contract")
