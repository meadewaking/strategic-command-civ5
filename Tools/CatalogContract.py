"""Validate every installed unit with the actual Lua capability classifier."""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile


def literal(value):
    if value is None:
        return "nil"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootstrap", required=True, type=Path)
    parser.add_argument("--db", type=Path, default=Path.home() / "Documents/My Games/Sid Meier's Civilization 5/cache/Civ5DebugDatabase.db")
    parser.add_argument("--lua", default=r"C:\Program Files (x86)\Lua\5.1\lua.exe")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    bootstrap = args.bootstrap.resolve()
    fixture = ["return {"]
    with sqlite3.connect(args.db.resolve().as_uri() + "?mode=ro", uri=True) as db:
        db.row_factory = sqlite3.Row
        for name in ("Units", "UnitPromotions", "Unit_FreePromotions", "UnitClasses", "Technologies", "Eras"):
            fixture.append(name + "={")
            for row in db.execute('SELECT * FROM "' + name + '"'):
                fixture.append("{" + ",".join("[" + literal(k) + "]=" + literal(row[k]) for k in row.keys()) + "},")
            fixture.append("},")
    fixture.append("}")
    with tempfile.TemporaryDirectory(prefix="sc5-catalog-") as temporary:
        path = Path(temporary) / "catalog.lua"
        path.write_text("\n".join(fixture), encoding="utf-8")
        run = subprocess.run([args.lua, str(root / "Tools/CatalogContract.lua"), str(root), bootstrap.name, str(path)],
                             cwd=bootstrap.parent, capture_output=True, text=True, errors="replace")
    profiles = {}
    for line in run.stdout.splitlines():
        if line.startswith("CATALOG|"):
            _, unit, role, attack_range, capture = line.split("|")
            profiles[unit] = {"class": role, "range": float(attack_range), "capture": capture == "true"}
        else:
            print(line)
    if run.stderr:
        print(run.stderr)
    from StrategySimulator import UnitCatalog
    legacy = UnitCatalog(args.db)
    differences = [{"unit": unit, "lua": p["class"], "python": legacy.profile(unit)["class"]}
                   for unit, p in profiles.items() if p["class"] != legacy.profile(unit)["class"]]
    if differences:
        print("FAIL legacy simulator classification drift:", differences)
    else:
        print("PASS legacy simulator class labels match deployed Lua")
    status = run.returncode or int(bool(differences))
    if args.output:
        args.output.write_text(json.dumps({"status": "PASS" if status == 0 else "FAIL",
                                          "units": len(profiles), "profiles": profiles,
                                          "legacy_differences": differences}, indent=2), encoding="utf-8")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
