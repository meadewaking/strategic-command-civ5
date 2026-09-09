"""Replay native-preview facts through the deployed Lua scorer, not a Python copy.

This validates scoring reproduction and reports immediate forecast error. It does
not simulate native pathfinding, combat events, enemy turns, or prove victory.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import subprocess
from collections import Counter

FIELDS = re.compile(r"([\w_]+)=([^\s]+)")
FACT_FIELDS = set("hp maxHP targetHP targetMaxHP damage retaliation uncertainty authorized legal city capture consumable targetValue selfValue threat protected capturerNear focusBonus key assaultSupported scriptValue".split())


def audit_execution(lines: list[str]) -> dict:
    choices, attacks, outcomes, deaths = {}, {}, {}, {}
    owners, modules, mismatches, labels = set(), Counter(), [], {}
    for line in lines:
        row = dict(FIELDS.findall(line))
        turn = re.search(r"\[T(\d+)\]", line)
        if "unitAudit begin " in line and row.get("player", "").startswith("P"):
            owners.add(row["player"][1:])
        label = re.search(r"unit=(UNIT_\w+)#(\d+)", line)
        if label:
            labels[label[2]] = label[1]
        if "decision5 candidate " in line:
            choices.setdefault(row.get("decision"), []).append(row)
        elif "decision5 attack " in line:
            owners.add(row.get("owner", "-999"))
            related = [c for c in choices.get(row.get("decision"), []) if c.get("key") == row.get("key")]
            matching = [c for c in related if math.isclose(float(c["score"]), float(row.get("choiceScore", 0)), abs_tol=0.01)]
            if matching:
                chosen = matching[0]
                differences = [k for k in ("damage", "retaliation", "targetHP", "targetValue", "enemyID", "enemyOwner", "cityID", "cityOwner")
                               if k in chosen and chosen.get(k) != row.get(k)
                               and not (k in row and chosen[k].replace(".", "", 1).isdigit()
                                        and row[k].replace(".", "", 1).isdigit()
                                        and math.isclose(float(chosen[k]), float(row[k]), abs_tol=0.001))]
                if differences:
                    mismatches.append(dict(decision=row.get("decision"), key=row.get("key"), fields=differences))
            elif row.get("decision") not in ("0", None):
                mismatches.append(dict(decision=row.get("decision"), key=row.get("key"), fields=["selected-candidate-missing"]))
            attacks[(row.get("owner"), row.get("unitID"))] = dict(row, turn=turn[1] if turn else None)
        elif "decision5 outcome " in line:
            outcomes[row.get("seq")] = row
        elif "module error name=" in line and "StrategicCommand" in line:
            modules[row.get("name", "unknown")] += 1
        elif "event=UnitPrekill " in line:
            key = (row.get("a1"), row.get("a2"))
            if key not in deaths:
                attack = attacks.get(key, {})
                result = outcomes.get(attack.get("seq"), {})
                deaths[key] = dict(owner=key[0], unitID=key[1], killer=row.get("a7"),
                                   turn=turn[1] if turn else None, unit=labels.get(key[1], "unknown"),
                                   last_attack_turn=attack.get("turn"), last_attack_hp=attack.get("hp"),
                                   moves_after_fire=result.get("movesAfter"),
                                   last_target=attack.get("key"))
    own = [d for d in deaths.values() if d["owner"] in owners]
    hostile = [d for d in own if d["killer"] not in ("-1", None, d["owner"])]
    return dict(module_errors=dict(modules), module_error_count=sum(modules.values()),
                target_inconsistency_count=len(mismatches), target_inconsistency_samples=mismatches[:12],
                own_death_events=len(own), own_hostile_death_events=len(hostile),
                own_death_types=dict(Counter(d["unit"] for d in own)),
                deaths_after_firing=sum(d["last_attack_turn"] == d["turn"] for d in hostile),
                death_samples=hostile[:12],
                scope="Whole log death events, deduplicated by owner/unit ID. Missiles and civilians included; deaths are not automatically classified as tactical losses. Prediction agreement is not target or next-turn survival agreement.")


def run_lua(root: Path, lua: str, rows: list[dict]) -> list[float | None]:
    payload = "\n".join(" ".join(f"{k}={str(v).lower() if isinstance(v, bool) else v}"
                                  for k, v in r.items() if k in FACT_FIELDS) for r in rows)
    if not rows:
        return []
    run = subprocess.run([lua, str(root / "Tools/DecisionReplay.lua"), str(root)],
                         input=payload + "\n", text=True, capture_output=True, check=True)
    results = [None if line.split("\t")[0] == "reject" else float(line.split("\t")[0])
               for line in run.stdout.splitlines()]
    if len(results) != len(rows):
        raise RuntimeError("Lua scorer returned an incomplete replay")
    return results


def analyze(path: Path, root: Path, lua: str) -> dict:
    candidates, outcomes, versions = [], [], []
    lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    integrity = audit_execution(lines)
    for line in lines:
        version = re.search(r"Strategic Command v([\d.]+) loaded", line)
        if version:
            versions.append(version[1])
        if "decision5 candidate " in line:
            candidates.append(dict(FIELDS.findall(line)))
        elif "decision5 outcome " in line:
            outcomes.append(dict(FIELDS.findall(line)))
    scores = run_lua(root, lua, candidates)
    mismatches = []
    for index, (row, score) in enumerate(zip(candidates, scores)):
        expected = float(row["score"])
        if score is None or not math.isclose(score, expected, abs_tol=0.001, rel_tol=1e-5):
            mismatches.append({"candidate": index, "decision": row.get("decision"), "logged": expected, "replayed": score})
    confirmed = [r for r in outcomes if r.get("confirmed") == "true" and r.get("observation") != "delayed"]
    errors = [abs(float(r["predictionError"])) for r in confirmed]
    return {
        "status": "FAIL" if (mismatches or integrity["module_error_count"] or integrity["target_inconsistency_count"])
                  else "INSUFFICIENT_DATA" if not candidates else "SCORING_REPRODUCED",
        "observed_versions": versions, "candidate_facts": len(candidates), "mismatches": mismatches,
        "immediate_outcomes": len(outcomes), "confirmed_outcomes": len(confirmed),
        "mean_absolute_damage_error": sum(errors) / len(errors) if errors else None,
        "unconfirmed_outcomes": sum(r.get("confirmed") != "true" for r in outcomes),
        "execution_integrity": integrity,
        "scope": "Top candidate scores only; outcome attribution is immediate, not a native-engine simulator. No facts means no new-strategy effectiveness claim.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--lua", default=r"C:\Program Files (x86)\Lua\5.1\lua.exe")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.self_test:
        rows = [dict(hp=100, damage=10, targetHP=1, city=True, capture=True, authorized=True),
                dict(hp=100, damage=10, targetHP=1, city=True, capture=False, authorized=True),
                dict(hp=100, damage=100, targetHP=100, authorized=False)]
        result = run_lua(root, args.lua, rows)
        assert result[0] is not None and result[1:] == [None, None], result
        print("PASS actual Lua replay transport and capture/peace branches")
        audited = audit_execution([
            "StrategicCommand [T217] decision5 candidate decision=1 rank=1 score=900 key=ranged:68:43 damage=27 targetHP=1",
            "StrategicCommand [T217] decision5 attack decision=1 seq=2 choiceScore=900 key=ranged:68:43 damage=1 targetHP=90 owner=0 unitID=10",
            "StrategicCommand [T217] decision5 outcome seq=2 movesAfter=0",
            "StrategicCommand [T217] DEMO event=UnitPrekill a1=0 a2=10 a7=9",
            "StrategicCommand [T217] DEMO event=UnitPrekill a1=0 a2=10 a7=9",
            "StrategicCommand module error name=v3.executionMilitary.move1 err=nil",
        ])
        assert audited["target_inconsistency_count"] == 1 and audited["module_error_count"] == 1
        assert audited["own_hostile_death_events"] == 1 and audited["deaths_after_firing"] == 1
        print("PASS replay detects wrong stacked defender, military module failure, and enemy-turn deaths")
    if args.log:
        result = analyze(args.log, root, args.lua)
        encoded = json.dumps(result, indent=2, ensure_ascii=False)
        print(encoded)
        if args.output:
            args.output.write_text(encoded + "\n", encoding="utf-8")
        return int(result["status"] == "FAIL")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
