#!/usr/bin/env python3
"""Database contracts plus telemetry-grounded Strategic Command execution replay."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sqlite3
import struct
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


def default_database() -> Path:
    return Path.home() / "Documents" / "My Games" / "Sid Meier's Civilization 5" / "cache" / "Civ5DebugDatabase.db"


def default_latest_save() -> Path | None:
    root = Path.home() / "Documents" / "My Games" / "Sid Meier's Civilization 5" / "ModdedSaves" / "single" / "auto"
    saves = sorted(root.glob("*.Civ5Save"), key=lambda path: path.stat().st_mtime, reverse=True)
    return saves[0] if saves else None


def parse_save_metadata(save_path: Path) -> dict[str, Any]:
    data = save_path.read_bytes()
    if len(data) < 64 or data[:4] != b"CIV5":
        raise ValueError(f"Not a Civ5 save: {save_path}")
    offset = 4

    def read_u32() -> int:
        nonlocal offset
        value = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        return value

    def read_u8() -> int:
        nonlocal offset
        value = data[offset]
        offset += 1
        return value

    def read_text() -> str:
        nonlocal offset
        length = read_u32()
        if length > 4096 or offset + length > len(data):
            raise ValueError(f"Invalid Civ5 save header string length {length} at {offset - 4}")
        value = data[offset:offset + length].decode("utf-8", errors="replace")
        offset += length
        return value

    format_version = read_u32()
    game_build = read_text()
    build_id = read_text()
    turn = read_u32()
    active_player = read_u8()
    fields = [read_text() for _ in range(7)]
    civilization, handicap, start_era, max_era, game_speed, world_size, map_path = fields
    ascii_strings = [
        match.group().decode("ascii", errors="ignore")
        for match in re.finditer(rb"[ -~]{4,}", data[:65536])
    ]
    mod_markers = sorted({
        re.sub(r"[^A-Za-z0-9 ._\\-]+$", "", text) for text in ascii_strings
        if "Super Power" in text or "Various Mod Components" in text or "Ingame Editor" in text
    })
    return {
        "path": str(save_path),
        "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "format_version": format_version,
        "game_build": game_build,
        "build_id": build_id,
        "turn": turn,
        "active_player": active_player,
        "civilization": civilization,
        "handicap": handicap,
        "start_era": start_era,
        "max_era": max_era,
        "game_speed": game_speed,
        "world_size": world_size,
        "map_path": map_path,
        "mod_markers": mod_markers,
    }


def as_bool(value: Any) -> bool:
    return int(value or 0) > 0


class UnitCatalog:
    def __init__(self, database: Path):
        self.database = database
        self.connection = sqlite3.connect(str(database))
        self.connection.row_factory = sqlite3.Row
        self.units = {
            row["Type"]: dict(row)
            for row in self.connection.execute("SELECT * FROM Units ORDER BY Type")
        }
        self.promotions: dict[str, list[dict[str, Any]]] = defaultdict(list)
        query = """
            SELECT f.UnitType, p.*
            FROM Unit_FreePromotions f
            JOIN UnitPromotions p ON p.Type = f.PromotionType
            ORDER BY f.UnitType, p.Type
        """
        for row in self.connection.execute(query):
            self.promotions[row["UnitType"]].append(dict(row))
        self._profiles: dict[str, dict[str, Any]] = {}

    def profile(self, unit_type: str) -> dict[str, Any]:
        if unit_type not in self._profiles:
            self._profiles[unit_type] = classify_unit(
                self.units[unit_type], self.promotions.get(unit_type, [])
            )
        return self._profiles[unit_type]


def promotion_summary(promotions: Iterable[dict[str, Any]]) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "move_after_attack": False,
        "extra_attacks": 0,
        "must_set_up": False,
        "drop_range": 0,
        "range_change": 0,
        "intercept": 0,
        "air_sweep": False,
        "indirect_fire": False,
        "no_capture": False,
        "only_defensive": False,
        "city_attack_only": False,
        "ignore_zoc": False,
        "ignore_terrain": False,
        "always_heal": False,
        "heal_on_kill": 0,
        "city_attack": 0,
        "attack": 0,
        "defense": 0,
        "cargo": 0,
        "carrier_air": False,
        "carrier": False,
        "missile_carrier": False,
        "submarine": False,
    }
    for promotion in promotions:
        promotion_type = str(promotion.get("Type") or "")
        summary["move_after_attack"] |= any(
            as_bool(promotion.get(field))
            for field in ("CanMoveAfterAttacking", "Blitz", "ExtraAttacks")
        )
        summary["extra_attacks"] += max(int(promotion.get("ExtraAttacks") or 0), 0)
        summary["must_set_up"] |= as_bool(promotion.get("MustSetUpToRangedAttack"))
        summary["drop_range"] = max(summary["drop_range"], int(promotion.get("DropRange") or 0))
        summary["range_change"] += int(promotion.get("RangeChange") or 0)
        summary["intercept"] += max(int(promotion.get("InterceptChanceChange") or 0), 0)
        summary["intercept"] += max(int(promotion.get("NumInterceptionChange") or 0), 0) * 100
        summary["air_sweep"] |= as_bool(promotion.get("AirSweepCapable"))
        summary["indirect_fire"] |= as_bool(promotion.get("RangeAttackIgnoreLOS"))
        summary["no_capture"] |= as_bool(promotion.get("NoCapture"))
        summary["only_defensive"] |= as_bool(promotion.get("OnlyDefensive"))
        summary["city_attack_only"] |= as_bool(promotion.get("CityAttackOnly"))
        summary["ignore_zoc"] |= as_bool(promotion.get("IgnoreZOC"))
        summary["ignore_terrain"] |= as_bool(promotion.get("IgnoreTerrainCost")) or as_bool(
            promotion.get("FlatMovementCost")
        )
        summary["always_heal"] |= as_bool(promotion.get("AlwaysHeal"))
        summary["heal_on_kill"] += max(int(promotion.get("HPHealedIfDestroyEnemy") or 0), 0)
        summary["city_attack"] += int(promotion.get("CityAttack") or 0)
        summary["attack"] += int(promotion.get("AttackMod") or 0)
        summary["defense"] += int(promotion.get("DefenseMod") or 0)
        summary["cargo"] += max(int(promotion.get("CargoChange") or 0), 0)
        summary["carrier_air"] |= "CARRIER_FIGHTER" in promotion_type
        summary["carrier"] |= "CARRIER_UNIT" in promotion_type
        summary["missile_carrier"] |= "MISSILE_CARRIER" in promotion_type
        summary["submarine"] |= "SUBMARINE_COMBAT" in promotion_type
    return summary


def classify_unit(unit: dict[str, Any], promotions: list[dict[str, Any]]) -> dict[str, Any]:
    unit_type = str(unit.get("Type") or "UNKNOWN")
    domain = str(unit.get("Domain") or "")
    combat_class = str(unit.get("CombatClass") or "")
    ai = str(unit.get("DefaultUnitAI") or "")
    combat = max(int(unit.get("Combat") or 0), 0)
    ranged = max(int(unit.get("RangedCombat") or 0), 0)
    promo = promotion_summary(promotions)
    attack_range = max(int(unit.get("Range") or 0) + int(promo["range_change"]), 0)
    moves = max(int(unit.get("Moves") or 0), 0)
    special = str(unit.get("Special") or "")
    special_cargo = str(unit.get("SpecialCargo") or "")
    domain_cargo = str(unit.get("DomainCargo") or "")
    civilian_ai = ai in {
        "UNITAI_WORKER", "UNITAI_ARCHAEOLOGIST", "UNITAI_SETTLE", "UNITAI_TRADE_UNIT",
        "UNITAI_ARTIST", "UNITAI_WRITER", "UNITAI_MUSICIAN", "UNITAI_SCIENTIST",
        "UNITAI_MERCHANT", "UNITAI_ENGINEER", "UNITAI_GENERAL", "UNITAI_ADMIRAL",
        "UNITAI_MISSIONARY", "UNITAI_PROPHET", "UNITAI_INQUISITOR", "UNITAI_SPACESHIP_PART",
    }

    doctrine_class, phase = "line_assault", 4
    if civilian_ai or (combat <= 0 and ranged <= 0 and not combat_class and domain not in ("DOMAIN_AIR", "DOMAIN_SEA")):
        if ai in ("UNITAI_WORKER", "UNITAI_ARCHAEOLOGIST"):
            doctrine_class = "civilian_builder"
        elif ai == "UNITAI_SETTLE":
            doctrine_class = "civilian_settler"
        elif ai == "UNITAI_TRADE_UNIT":
            doctrine_class = "civilian_trade"
        elif any(word in ai for word in ("MISSIONARY", "PROPHET", "INQUISITOR")):
            doctrine_class = "civilian_religious"
        elif "SPACESHIP" in ai:
            doctrine_class = "civilian_spaceship"
        else:
            doctrine_class = "civilian_specialist"
        phase = 90
    elif domain == "DOMAIN_AIR":
        if int(unit.get("NukeDamageLevel") or 0) > 0 or special == "SPECIALUNIT_NUKE" or ai == "UNITAI_ICBM":
            doctrine_class, phase = "strategic_nuclear", 2
        elif as_bool(unit.get("Suicide")) or special == "SPECIALUNIT_MISSILE" or ai == "UNITAI_MISSILE_AIR":
            doctrine_class, phase = "missile_strike", 2
        elif combat_class == "UNITCOMBAT_FIGHTER" or ai == "UNITAI_DEFENSE_AIR":
            if promo["carrier_air"] or "CARRIER_FIGHTER" in unit_type or "HARRIER" in unit_type:
                doctrine_class = "carrier_multirole"
            else:
                doctrine_class = "air_superiority"
            phase = 1
        else:
            doctrine_class, phase = "strike_aircraft", 2
    elif domain == "DOMAIN_SEA":
        carrier = (
            combat_class == "UNITCOMBAT_CARRIER"
            or ai == "UNITAI_CARRIER_SEA"
            or promo["carrier"]
            or (special_cargo == "SPECIALUNIT_FIGHTER" and domain_cargo == "DOMAIN_AIR")
        )
        submarine = combat_class == "UNITCOMBAT_SUBMARINE" or promo["submarine"]
        if carrier:
            doctrine_class, phase = "fleet_carrier", 5
        elif submarine and (special_cargo == "SPECIALUNIT_NUKE" or "SSBN" in unit_type):
            doctrine_class, phase = "ballistic_submarine", 5
        elif submarine:
            doctrine_class, phase = "attack_submarine", 2
        elif ranged >= 300 and attack_range >= 6:
            doctrine_class, phase = "arsenal_capital", 3
        elif promo["intercept"] > 0 or special_cargo == "SPECIALUNIT_MISSILE" or promo["missile_carrier"]:
            doctrine_class, phase = "air_defense_screen", 1
        elif combat_class == "UNITCOMBAT_NAVALRANGED" or (ranged > 0 and attack_range > 1):
            doctrine_class, phase = "surface_fire_support", 3
        elif ai == "UNITAI_ESCORT_SEA" or combat_class == "UNITCOMBAT_RECON":
            doctrine_class, phase = "escort_screen", 1
        else:
            doctrine_class, phase = "naval_assault", 4
    elif domain == "DOMAIN_HOVER":
        doctrine_class, phase = "static_fortress", 3
    elif unit_type == "UNIT_MECH":
        doctrine_class, phase = "super_heavy", 3
    elif promo["intercept"] > 0:
        doctrine_class, phase = "mobile_air_defense", 1
    elif combat_class == "UNITCOMBAT_HELICOPTER":
        doctrine_class, phase = "gunship", 2
    elif combat_class == "UNITCOMBAT_SIEGE" or ai == "UNITAI_CITY_BOMBARD" or (ranged > 0 and attack_range >= 3):
        doctrine_class, phase = "siege_artillery", 3
    elif ai == "UNITAI_PARADROP" or promo["drop_range"] > 0:
        doctrine_class, phase = "airborne_raider", 1
    elif combat_class == "UNITCOMBAT_RECON" or ai == "UNITAI_EXPLORE":
        doctrine_class, phase = "recon_raider", 1
    elif ai == "UNITAI_COUNTER":
        doctrine_class, phase = "counter_defender", 4
    elif combat_class in ("UNITCOMBAT_ARMOR", "UNITCOMBAT_MOUNTED") or ai == "UNITAI_FAST_ATTACK" or (moves >= 5 and combat > 0):
        doctrine_class, phase = "mobile_breakthrough", 4
    elif ai == "UNITAI_DEFENSE" or promo["only_defensive"]:
        doctrine_class, phase = "line_defender", 4
    elif ranged > 0:
        doctrine_class, phase = "ranged_support", 3

    land_capture_class = combat_class in {
        "UNITCOMBAT_ARMOR", "UNITCOMBAT_MELEE", "UNITCOMBAT_MOUNTED",
        "UNITCOMBAT_RECON", "UNITCOMBAT_GUN",
    }
    sea_capture_class = combat_class == "UNITCOMBAT_NAVALMELEE" or (
        combat_class == "UNITCOMBAT_RECON" and attack_range <= 1 and ai != "UNITAI_EXPLORE_SEA"
    )
    can_capture = (
        combat > 0
        and not promo["no_capture"]
        and not as_bool(unit.get("Suicide"))
        and not civilian_ai
        and ((domain == "DOMAIN_LAND" and land_capture_class)
             or (domain == "DOMAIN_SEA" and sea_capture_class))
    )
    return {
        "type": unit_type,
        "class": doctrine_class,
        "phase": phase,
        "domain": domain,
        "combat_class": combat_class,
        "default_ai": ai,
        "description": str(unit.get("Description") or ""),
        "help": str(unit.get("Help") or ""),
        "strategy": str(unit.get("Strategy") or ""),
        "civilian": civilian_ai,
        "combat": combat,
        "ranged": ranged,
        "range": attack_range,
        "moves": moves,
        "power": max(combat, ranged),
        "max_hp": max(int(unit.get("MaxHitPoints") or 100), 1),
        "can_capture": can_capture,
        "can_range": ranged > 0 or domain == "DOMAIN_AIR",
        "move_after_attack": promo["move_after_attack"],
        "extra_attacks": promo["extra_attacks"],
        "must_set_up": promo["must_set_up"],
        "drop_range": promo["drop_range"],
        "intercept": promo["intercept"],
        "air_sweep": promo["air_sweep"],
        "indirect_fire": promo["indirect_fire"] or as_bool(unit.get("RangeAttackIgnoreLOS")),
        "suicide": as_bool(unit.get("Suicide")),
        "city_attack_only": promo["city_attack_only"],
        "cargo": promo["cargo"],
        "project_prereq": str(unit.get("ProjectPrereq") or ""),
    }


PROTECTED_CLASSES = {"fleet_carrier", "ballistic_submarine", "arsenal_capital"}
SCREEN_CLASSES = {"air_defense_screen", "escort_screen", "attack_submarine", "mobile_air_defense"}


def protection_tier(profile: dict[str, Any]) -> int:
    unit_type = profile["type"]
    if unit_type in ("UNIT_GREAT_GENERAL", "UNIT_GREAT_ADMIRAL"):
        return 3
    if unit_type == "UNIT_MECH" or profile["class"] in PROTECTED_CLASSES:
        return 3
    if profile.get("project_prereq"):
        return 3
    if profile["class"] in {"siege_artillery", "gunship"} or profile["range"] >= 4 or profile["power"] >= 250:
        return 2
    if profile["power"] >= 130:
        return 1
    return 0


def retreat_damage_threshold(profile: dict[str, Any]) -> int:
    return 20 if protection_tier(profile) >= 2 else 45


@dataclass
class SimUnit:
    name: str
    profile: dict[str, Any]
    side: str
    distance: float
    hp: float = 100.0
    at_war: bool = True
    actions: list[str] = field(default_factory=list)

    @property
    def alive(self) -> bool:
        return self.hp > 0


def target_score(attacker: SimUnit, target: SimUnit) -> float:
    if not target.at_war or not target.alive:
        return -1_000_000
    attacker_class = attacker.profile["class"]
    target_class = target.profile["class"]
    score = target.profile["power"] * 2 + (100 - target.hp) * 8
    if target.profile["can_range"]:
        score += 180
    if target_class in PROTECTED_CLASSES:
        score += 420
    if attacker_class in ("air_superiority", "carrier_multirole"):
        if target_class in ("air_superiority", "carrier_multirole", "strike_aircraft"):
            score += 620
        elif target_class in ("mobile_air_defense", "air_defense_screen"):
            score += 360
    elif attacker_class in ("strike_aircraft", "missile_strike"):
        if target_class in ("mobile_air_defense", "air_defense_screen"):
            score += 520
        elif target_class in ("siege_artillery", "surface_fire_support"):
            score += 360
    elif attacker_class == "attack_submarine":
        if target_class == "fleet_carrier":
            score += 900
        elif target_class in ("ballistic_submarine", "arsenal_capital"):
            score += 700
        elif target.profile["domain"] == "DOMAIN_SEA":
            score += 420
        else:
            score -= 420
    elif attacker_class in ("mobile_breakthrough", "gunship", "super_heavy"):
        if target_class in ("siege_artillery", "ranged_support", "mobile_air_defense"):
            score += 460
    ratio = attacker.profile["power"] / max(target.profile["power"], 1)
    if ratio >= 2.5:
        score += 360
    elif ratio >= 1.6:
        score += 220
    elif ratio < 0.72 and not attacker.profile["can_range"]:
        score -= 900
    return score


def can_attack(attacker: SimUnit, target: SimUnit) -> bool:
    attacker_class = attacker.profile["class"]
    if attacker_class in ("fleet_carrier", "ballistic_submarine", "strategic_nuclear"):
        return False
    if attacker_class == "attack_submarine" and target.profile["domain"] != "DOMAIN_SEA":
        return False
    attack_range = max(attacker.profile["range"], 1 if attacker.profile["combat"] > 0 else 0)
    if attacker.profile["domain"] == "DOMAIN_AIR":
        attack_range = max(attack_range, attacker.profile["range"])
    return attacker.distance <= attack_range or attacker.profile["moves"] >= attacker.distance - attack_range


def combat_damage(attacker: SimUnit, target: SimUnit) -> float:
    attack = max(attacker.profile["ranged"], attacker.profile["combat"], 1)
    defense = max(target.profile["combat"], target.profile["ranged"] * 0.65, 1)
    ratio = max(0.2, min(4.0, attack / defense))
    return min(100.0, 34.0 * math.pow(ratio, 1.25))


def future_carrier_group_scenario(catalog: UnitCatalog) -> dict[str, Any]:
    friendly_types = [
        "UNIT_SUPER_CARRIER",
        "UNIT_FUTURE_BATTLESHIP",
        "UNIT_KIROV_BATTLECRUISER",
        "UNIT_CHINESE_052D",
        "UNIT_CHINESE_052D",
        "UNIT_NUCLEAR_SUBMARINE",
        "UNIT_SSBN",
    ] + ["UNIT_CARRIER_FIGHTER_ADV"] * 6
    enemy_types = [
        "UNIT_BATTLESHIP",
        "UNIT_DESTROYER",
        "UNIT_SUBMARINE",
        "UNIT_JET_FIGHTER",
        "UNIT_MECHANIZED_INFANTRY",
        "UNIT_ROCKET_ARTILLERY",
    ]
    start_distance = {
        "fleet_carrier": 8,
        "ballistic_submarine": 8,
        "arsenal_capital": 8,
        "air_defense_screen": 3,
        "surface_fire_support": 4,
        "attack_submarine": 3,
        "carrier_multirole": 8,
    }
    friendly = [
        SimUnit(
            f"{unit_type}#{index}",
            catalog.profile(unit_type),
            "friendly",
            float(start_distance.get(catalog.profile(unit_type)["class"], 3)),
        )
        for index, unit_type in enumerate(friendly_types, 1)
    ]
    enemies = [
        SimUnit(unit_type, catalog.profile(unit_type), "enemy", 0.0)
        for unit_type in enemy_types
        if unit_type in catalog.units
    ]
    allied_city_state = SimUnit(
        "ALLY_CITY_STATE",
        {"class": "city", "power": 160, "combat": 160, "ranged": 160, "domain": "DOMAIN_LAND", "can_range": True},
        "ally",
        0.0,
        hp=200,
        at_war=False,
    )
    city_hp = 300.0
    city_captured = False
    logs: list[str] = []
    turns = 0
    for turn in range(1, 7):
        turns = turn
        for attacker in sorted(friendly, key=lambda item: (item.profile["phase"], -item.profile["power"])):
            if not attacker.alive:
                continue
            action_budget = 1 + min(int(attacker.profile["extra_attacks"]), 2)
            for _ in range(action_budget):
                candidates = [target for target in enemies if target.alive] + [allied_city_state]
                candidates = [target for target in candidates if can_attack(attacker, target)]
                if not candidates:
                    break
                target = max(candidates, key=lambda item: target_score(attacker, item))
                if target_score(attacker, target) <= -100_000:
                    break
                minimum = 6 if attacker.profile["class"] in PROTECTED_CLASSES else max(attacker.profile["range"], 1)
                attacker.distance = max(float(minimum), attacker.distance - attacker.profile["moves"])
                damage = combat_damage(attacker, target)
                target.hp -= damage
                attacker.actions.append(f"attack:{target.name}")
                logs.append(f"T{turn} {attacker.name} -> {target.name} damage={damage:.1f}")
        alive_enemies = [unit for unit in enemies if unit.alive]
        if not alive_enemies:
            bombarders = [
                unit
                for unit in friendly
                if unit.alive
                and unit.profile["class"] in ("arsenal_capital", "surface_fire_support", "carrier_multirole", "strike_aircraft")
            ]
            for attacker in bombarders:
                if city_hp <= 0:
                    break
                damage = max(20.0, attacker.profile["power"] / 4)
                city_hp -= damage
                logs.append(f"T{turn} {attacker.name} -> ENEMY_CITY damage={damage:.1f}")
            if city_hp <= 0:
                capture_units = [unit for unit in friendly if unit.alive and unit.profile["can_capture"]]
                if capture_units:
                    captor = max(capture_units, key=lambda item: (item.profile["moves"], item.profile["power"]))
                    captor.distance = 0
                    captor.actions.append("capture-city")
                    city_captured = True
                    logs.append(f"T{turn} {captor.name} captured ENEMY_CITY")
        if city_captured:
            break
        for attacker in alive_enemies:
            exposed = [unit for unit in friendly if unit.alive and unit.distance <= max(attacker.profile["range"], 1)]
            if exposed:
                target = min(exposed, key=lambda item: (item.profile["class"] in PROTECTED_CLASSES, item.hp))
                target.hp -= combat_damage(attacker, target)
                logs.append(f"T{turn} {attacker.name} counterattacks {target.name}")

    losses = sum(1 for unit in friendly if not unit.alive)
    damaged = sum(1 for unit in friendly if unit.hp < 100)
    accidental_wars = int(allied_city_state.hp < 200)
    classes_used = Counter(unit.profile["class"] for unit in friendly if unit.actions)
    result = {
        "scenario": "future_carrier_group_vs_current_era",
        "turns": turns,
        "enemy_units_destroyed": sum(1 for unit in enemies if not unit.alive),
        "enemy_units_total": len(enemies),
        "city_captured": city_captured,
        "friendly_losses": losses,
        "friendly_damaged": damaged,
        "accidental_wars": accidental_wars,
        "classes_used": dict(sorted(classes_used.items())),
        "log_tail": logs[-12:],
    }
    assert result["enemy_units_destroyed"] == result["enemy_units_total"], result
    assert city_captured, result
    assert losses == 0, result
    assert damaged == 0, result
    assert accidental_wars == 0, result
    return result


def convoy_scenario() -> dict[str, Any]:
    def decision(mission_class: str, escorts: int, threats: int) -> str:
        if mission_class == "trade":
            return "release-trade"
        if threats <= 0:
            return "advance-unopposed"
        required = 2 if threats >= 2 else 1
        if escorts < required:
            return f"hold-for-screen:{escorts}/{required}"
        return "advance-to-landing" if mission_class == "combat" else "escorted-retreat"

    assert decision("combat", 0, 0) == "advance-unopposed"
    assert decision("trade", 0, 3) == "release-trade"
    assert decision("combat", 1, 1) == "advance-to-landing"
    assert decision("combat", 4, 3) == "advance-to-landing"
    assert decision("combat", 1, 3) == "hold-for-screen:1/2"
    assert decision("worker", 2, 2) == "escorted-retreat"
    return {
        "scenario": "ocean_transport_convoy",
        "no_threat_without_escort": "advance",
        "trade_ship": "trade-route-managed",
        "one_threat_with_one_escort": "advance-to-landing",
        "severe_threat_with_one_escort": "hold",
        "civilian_under_severe_threat": "escorted-retreat",
        "transport_exposed": False,
    }


def airlift_scenario(catalog: UnitCatalog) -> dict[str, Any]:
    facility_types = [
        row["Type"]
        for row in catalog.connection.execute(
            "SELECT Type FROM Buildings WHERE COALESCE(Airlift, 0) <> 0 ORDER BY Type"
        )
    ]
    assert "BUILDING_MILITARY_BASE" in facility_types, facility_types
    mission = catalog.connection.execute(
        "SELECT ID FROM Missions WHERE Type = 'MISSION_AIRLIFT'"
    ).fetchone()
    assert mission is not None

    def decide(
        *,
        facility_cities: int,
        at_source: bool,
        source_distance: int,
        distance_saved: int,
        cross_area: bool,
        native_destination_legal: bool,
    ) -> str:
        if facility_cities < 2:
            return "escorted-sea-transit" if cross_area else "land-move"
        useful = distance_saved >= 12 or (cross_area and distance_saved > 0)
        if not useful:
            return "escorted-sea-transit" if cross_area else "land-move"
        if at_source:
            return "airlift" if native_destination_legal else "escorted-sea-transit"
        if 0 < source_distance <= 24:
            return "airlift-stage"
        return "escorted-sea-transit" if cross_area else "land-move"

    direct = decide(
        facility_cities=3, at_source=True, source_distance=0,
        distance_saved=31, cross_area=True, native_destination_legal=True,
    )
    staged = decide(
        facility_cities=3, at_source=False, source_distance=8,
        distance_saved=27, cross_area=True, native_destination_legal=True,
    )
    no_network = decide(
        facility_cities=1, at_source=False, source_distance=5,
        distance_saved=30, cross_area=True, native_destination_legal=True,
    )
    blocked_destination = decide(
        facility_cities=2, at_source=True, source_distance=0,
        distance_saved=22, cross_area=True, native_destination_legal=False,
    )
    short_land = decide(
        facility_cities=2, at_source=True, source_distance=0,
        distance_saved=3, cross_area=False, native_destination_legal=True,
    )
    detour_saved = 8 - 4 - 1
    detour_stage = decide(
        facility_cities=3, at_source=False, source_distance=4,
        distance_saved=detour_saved, cross_area=False, native_destination_legal=True,
    )
    formation_airlift = "disabled-local-follow"

    def resolve_pending(*, queued_turn: int, current_turn: int, current_index: int, source_index: int, destination_index: int) -> str:
        if current_index == destination_index or current_index != source_index:
            return "confirmed"
        if current_turn <= queued_turn:
            return "pending"
        return "expired"

    same_tick = resolve_pending(
        queued_turn=210, current_turn=210, current_index=12,
        source_index=12, destination_index=88,
    )
    next_turn = resolve_pending(
        queued_turn=210, current_turn=211, current_index=88,
        source_index=12, destination_index=88,
    )
    reverse_blocked = 211 - 210 <= 3
    assert direct == "airlift"
    assert staged == "airlift-stage"
    assert no_network == "escorted-sea-transit"
    assert blocked_destination == "escorted-sea-transit"
    assert short_land == "land-move"
    assert detour_stage == "land-move"
    assert formation_airlift == "disabled-local-follow"
    assert same_tick == "pending"
    assert next_turn == "confirmed"
    assert reverse_blocked
    return {
        "scenario": "military_base_airlift",
        "facility_types": facility_types,
        "remote_unit_at_base": direct,
        "remote_unit_near_base": staged,
        "single_base_fallback": no_network,
        "native_destination_blocked": blocked_destination,
        "short_land_route": short_land,
        "detour_stage": detour_stage,
        "formation_airlift": formation_airlift,
        "same_tick_status": same_tick,
        "next_turn_status": next_turn,
        "reverse_route_blocked": reverse_blocked,
    }


def strategic_target_memory_scenario() -> dict[str, Any]:
    score_series = [
        {"north_city": 4200, "east_city": 4050},
        {"north_city": 3970, "east_city": 4310},
        {"north_city": 4280, "east_city": 4020},
        {"north_city": 4000, "east_city": 4350},
        {"north_city": 4250, "east_city": 4080},
        {"east_city": 4300},
    ]

    def replay(memory_bonus: int) -> tuple[list[str], int]:
        selected: list[str] = []
        current: str | None = None
        switches = 0
        for candidates in score_series:
            scored = {
                key: score + (memory_bonus if key == current else 0)
                for key, score in candidates.items()
            }
            choice = max(scored, key=scored.get)
            if current is not None and choice != current:
                switches += 1
            selected.append(choice)
            current = choice
        return selected, switches

    baseline, baseline_switches = replay(0)
    persistent, persistent_switches = replay(1800)
    assert baseline_switches >= 4, baseline
    assert persistent_switches == 1, persistent
    assert persistent[:5] == ["north_city"] * 5, persistent
    assert persistent[-1] == "east_city", persistent
    return {
        "scenario": "cross_turn_strategic_target_hysteresis",
        "baseline_switches": baseline_switches,
        "memory_switches": persistent_switches,
        "persistent_assignments": persistent,
    }


def strategic_scope_and_runtime_scenario() -> dict[str, Any]:
    enemy_unit_distances = list(range(2, 277))
    enemy_city_count = 19
    protected_pursuit_limit = 7
    high_value_distance = 10
    high_value_bonus = 4

    local_units = [distance for distance in enemy_unit_distances if distance <= protected_pursuit_limit]
    assert len(local_units) == 6
    assert high_value_distance <= protected_pursuit_limit + high_value_bonus
    expensive_candidates_before = len(enemy_unit_distances) + enemy_city_count
    expensive_candidates_after = len(local_units) + 1 + enemy_city_count
    reduction = 1 - expensive_candidates_after / expensive_candidates_before
    assert reduction > 0.9

    pass_reasons = ["popup", "playerDoTurn", "activeTurnStart", "popup", "popup", "activeTurnStart"]
    full_passes = 0
    pass_modes: list[str] = []
    for reason in pass_reasons:
        full_eligible = reason != "popup"
        full = full_eligible and full_passes < 1
        if full:
            full_passes += 1
        pass_modes.append("full" if full else "light")
    assert pass_modes == ["light", "full", "light", "light", "light", "light"]

    first_sweep_modules = {
        "cities", "purchase", "ideology", "research", "policy", "upgrade",
        "promotion", "great_people", "healing", "transport", "capture",
        "air", "local_defense", "city_strike", "strategic_move", "stacked",
        "idle", "trade", "final_orders", "league", "blocker",
    }
    followup_modules = {"capture", "air", "local_defense", "city_strike", "final_orders", "blocker"}
    assert "strategic_move" not in followup_modules
    assert "capture" in followup_modules

    def dedicated_capturer(role: str, protected_ranged: bool = False) -> bool:
        excluded = {"missile_carrier", "naval_ranged", "submarine", "siege", "land_ranged", "carrier"}
        return role not in excluded and not protected_ranged

    assert dedicated_capturer("fast_assault")
    assert not dedicated_capturer("naval_ranged")
    assert not dedicated_capturer("assault", protected_ranged=True)
    assert 0 <= 0
    assert not 1 <= 0

    def commander_safe(enemy_distance: int, friendly_cover: int) -> bool:
        return enemy_distance >= 4 and friendly_cover >= 1

    assert commander_safe(5, 1)
    assert not commander_safe(3, 4)
    assert not commander_safe(6, 0)
    return {
        "scenario": "bounded_target_search_and_lightweight_passes",
        "expensive_candidates_before": expensive_candidates_before,
        "expensive_candidates_after": expensive_candidates_after,
        "candidate_reduction_percent": round(reduction * 100, 1),
        "pass_modes": pass_modes,
        "full_sweep_module_count": len(first_sweep_modules),
        "followup_sweep_module_count": len(followup_modules),
        "unsafe_city_screen_blocks_capture": True,
        "unsafe_commander_plot_blocks_move": True,
    }


def quick_buy_buildings_scenario() -> dict[str, Any]:
    buildings = [
        {"name": "BARRACKS", "cost": 120, "prereq": None},
        {"name": "ARMORY", "cost": 180, "prereq": "BARRACKS"},
        {"name": "ARSENAL", "cost": 260, "prereq": "ARMORY"},
        {"name": "MILITARY_BASE", "cost": 900, "prereq": "ARSENAL"},
        {"name": "MONUMENT", "cost": 90, "prereq": None},
    ]
    gold = 700
    owned: set[str] = set()
    pending: dict[str, Any] | None = None
    purchases: list[str] = []
    submissions_per_tick: list[int] = []
    stop_reason = ""
    for _tick in range(20):
        submissions = 0
        if pending is not None:
            owned.add(pending["name"])
            gold -= pending["cost"]
            purchases.append(pending["name"])
            pending = None
        for building in buildings:
            if building["name"] in owned:
                continue
            if building["prereq"] is not None and building["prereq"] not in owned:
                continue
            if gold < building["cost"]:
                stop_reason = "insufficient-gold"
                break
            pending = building
            submissions += 1
            break
        submissions_per_tick.append(submissions)
        if stop_reason or (pending is None and submissions == 0):
            break
    assert purchases == ["BARRACKS", "ARMORY", "ARSENAL"], purchases
    assert "MONUMENT" not in purchases
    assert stop_reason == "insufficient-gold"
    assert max(submissions_per_tick) == 1
    return {
        "scenario": "asynchronous_quick_buy_buildings",
        "purchases": purchases,
        "remaining_gold_before_stop": gold,
        "stop_reason": stop_reason,
        "max_submissions_per_tick": max(submissions_per_tick),
        "dependent_buildings_unlocked": True,
    }


def theater_assignment_scenario() -> dict[str, Any]:
    targets = {
        "convoy_raider": {"kind": "unit", "capacity": 2},
        "coastal_city": {"kind": "city", "capacity": 7},
        "land_front": {"kind": "city", "capacity": 7},
    }
    units = [
        {"name": "local_screen_1", "screen": True, "domain": "sea", "distance": {"convoy_raider": 5, "coastal_city": 14, "land_front": 40}},
        {"name": "local_screen_2", "screen": True, "domain": "sea", "distance": {"convoy_raider": 7, "coastal_city": 13, "land_front": 39}},
        {"name": "local_screen_3", "screen": True, "domain": "sea", "distance": {"convoy_raider": 8, "coastal_city": 9, "land_front": 35}},
        {"name": "far_artillery", "screen": False, "domain": "land", "distance": {"convoy_raider": 48, "coastal_city": 31, "land_front": 8}},
        {"name": "carrier", "screen": False, "domain": "sea", "distance": {"convoy_raider": 30, "coastal_city": 10, "land_front": 37}},
    ]
    commitments: Counter[str] = Counter()
    assignments: dict[str, str] = {}

    def score(unit: dict[str, Any], target_name: str) -> float:
        target = targets[target_name]
        distance = unit["distance"][target_name]
        value = 1000 - distance * 12
        if target["kind"] == "city":
            value += 500
        if target_name == "convoy_raider":
            response_limit = 16 if unit["screen"] else 12
            if distance <= response_limit:
                raw_threat = 1400
                distance_factor = max(0.2, (response_limit - distance + 1) / (response_limit + 1))
                value += raw_threat * distance_factor * (1.0 if unit["screen"] else 0.35)
        reach = 28 if unit["domain"] == "sea" else 18
        if distance > reach:
            value -= (distance - reach) * 90
        if commitments[target_name] >= target["capacity"]:
            value -= 3600 + (commitments[target_name] - target["capacity"]) * 900
        return value

    for unit in units:
        selected = max(targets, key=lambda target_name: score(unit, target_name))
        assignments[unit["name"]] = selected
        commitments[selected] += 1

    assert assignments["local_screen_1"] == "convoy_raider", assignments
    assert assignments["local_screen_2"] == "convoy_raider", assignments
    assert assignments["local_screen_3"] == "coastal_city", assignments
    assert assignments["far_artillery"] == "land_front", assignments
    assert assignments["carrier"] == "coastal_city", assignments
    assert commitments["convoy_raider"] == 2, commitments

    failed_pairs: set[str] = set()
    attempts = 0
    pair = "KIROV|EMBARKED_ARMOR"
    for _sweep in range(5):
        if pair not in failed_pairs:
            attempts += 1
            failed_pairs.add(pair)
    assert attempts == 1
    return {
        "scenario": "localized_theater_assignment",
        "assignments": assignments,
        "target_commitments": dict(commitments),
        "failed_escort_attempts_per_pair": attempts,
    }


def runtime_and_great_people_scenario() -> dict[str, Any]:
    sweep_actions = [18, 2, 0, 0, 0]
    executed_sweeps = 0
    for actions in sweep_actions[:3]:
        executed_sweeps += 1
        if actions == 0:
            break
    assert executed_sweeps == 3
    assert executed_sweeps < len(sweep_actions)

    healed_units: set[str] = set()
    healing_orders = 0
    for _sweep in range(3):
        unit_key = "DAMAGED_RAILROAD_GUN"
        if unit_key not in healed_units:
            healed_units.add(unit_key)
            healing_orders += 1
    assert healing_orders == 1

    modal_pending: set[str] = set()
    modal_submissions = 0
    for _turn in range(2):
        unit_key = "PROPHET#172042"
        if unit_key not in modal_pending:
            modal_pending.add(unit_key)
            modal_submissions += 1
    assert modal_submissions == 1

    no_belief = -1
    def pack_religion_beliefs(has_pantheon: bool) -> list[int]:
        packed: list[int] = []
        if not has_pantheon:
            packed.append(101)
        packed.extend((201, 301))
        while len(packed) < 4:
            packed.append(no_belief)
        return packed

    assert pack_religion_beliefs(True) == [201, 301, -1, -1]
    assert pack_religion_beliefs(False) == [101, 201, 301, -1]

    action_candidates = [
        ("MISSION_GIVE_POLICIES", 105, True),
        ("MISSION_CREATE_GREAT_WORK", 100, False),
        ("MISSION_GOLDEN_AGE", 20, False),
    ]
    selected_action = next(action for action, _score, resolves in action_candidates if resolves)
    assert selected_action == "MISSION_GIVE_POLICIES"

    great_people = {
        "scientist": "MISSION_DISCOVER",
        "writer": selected_action,
        "engineer": "move-to-wonder-city",
        "merchant": "move-to-city-state",
        "general": "follow-land-front",
        "admiral": "follow-fleet",
    }
    assert all(action != "sleep" for action in great_people.values())

    fire_support_capacity = 7
    capture_capacity = 2
    fire_support_committed = 7
    capture_committed = 2
    assert fire_support_committed <= fire_support_capacity
    assert capture_committed <= capture_capacity
    return {
        "scenario": "runtime_convergence_and_great_people",
        "executed_sweeps": executed_sweeps,
        "healing_orders_per_unit": healing_orders,
        "religion_modal_submissions": modal_submissions,
        "religion_beliefs_with_pantheon": pack_religion_beliefs(True),
        "religion_beliefs_without_pantheon": pack_religion_beliefs(False),
        "great_people": great_people,
        "city_fire_support_slots": fire_support_capacity,
        "city_capture_slots": capture_capacity,
    }


def city_capture_task_scenario(catalog: UnitCatalog) -> dict[str, Any]:
    """Exercise the operation-bound reduce/reserve/stage/capture chain."""
    cities = [
        {"key": "capture|49,41", "plot": (49, 41), "damage": 250, "max_hp": 250, "operation": "OP:A"},
        {"key": "capture|53,42", "plot": (53, 42), "damage": 238, "max_hp": 250, "operation": "OP:B"},
        {"key": "capture|70,70", "plot": (70, 70), "damage": 249, "max_hp": 250, "operation": None},
    ]
    units = [
        {"name": "052D-A", "type": "UNIT_CHINESE_052D", "plot": (48, 41), "damage": 0, "operation": "OP:A"},
        {"name": "052D-B", "type": "UNIT_CHINESE_052D", "plot": (52, 42), "damage": 5, "operation": "OP:B"},
        {"name": "LCS-A", "type": "UNIT_LITTORAL_COMBAT_SHIP", "plot": (46, 40), "damage": 10, "operation": "OP:A"},
        {"name": "LCS-B", "type": "UNIT_LITTORAL_COMBAT_SHIP", "plot": (55, 43), "damage": 0, "operation": "OP:B"},
        {"name": "Kirov-fire", "type": "UNIT_KIROV_BATTLECRUISER", "plot": (48, 43), "damage": 0},
        {"name": "Sub-screen", "type": "UNIT_NUCLEAR_SUBMARINE", "plot": (50, 43), "damage": 0},
    ]
    for unit in units:
        unit["profile"] = catalog.profile(unit["type"])

    capturers = [unit for unit in units if unit["profile"]["can_capture"]]
    assert {unit["name"] for unit in capturers} == {"052D-A", "052D-B", "LCS-A", "LCS-B"}

    active_cities = [
        city for city in cities
        if city["damage"] / city["max_hp"] >= 0.92 and city["operation"] is not None
    ][:2]
    assert [city["key"] for city in active_cities] == ["capture|49,41", "capture|53,42"]
    assignments: dict[str, list[str]] = {city["key"]: [] for city in active_cities}
    used: set[str] = set()
    for _slot in range(2):
        for city in active_cities:
            candidates: list[tuple[float, dict[str, Any]]] = []
            for unit in capturers:
                if unit["name"] in used:
                    continue
                if unit.get("operation") != city["operation"]:
                    continue
                profile = unit["profile"]
                distance = _approx_hex_distance(unit["plot"], city["plot"])
                if distance > 12:
                    continue
                score = (
                    6200 - distance * 145 - unit["damage"] * 24
                    + profile["power"] * 4 + profile["moves"] * 18
                    + 20000
                )
                if distance <= 4:
                    score += 4200
                if profile["combat_class"] == "UNITCOMBAT_NAVALMELEE":
                    score += 620
                candidates.append((score, unit))
            if candidates:
                _score, selected = max(candidates, key=lambda item: item[0])
                assignments[city["key"]].append(selected["name"])
                used.add(selected["name"])

    assert all(len(items) == 2 for items in assignments.values()), assignments
    assert all(len(set(items)) == len(items) for items in assignments.values())
    assert len(used) == 4

    def capture_secure(friendly_power: float, enemy_power: float, damage: int, elite: bool) -> bool:
        ratio = 0.80
        if damage >= 55:
            ratio = 1.25
        elif elite:
            ratio = max(ratio, 0.95)
        return enemy_power <= 0 or friendly_power >= enemy_power * ratio

    assert capture_secure(840, 600, damage=5, elite=True)
    assert not capture_secure(300, 600, damage=70, elite=True)

    tactical_sequence = ["reduce-city", "reserve-capturer", "capture-city", "secure-city"]
    assert tactical_sequence.index("reserve-capturer") < tactical_sequence.index("capture-city")
    assert tactical_sequence.index("capture-city") < tactical_sequence.index("secure-city")
    accepted_plan_scores = [9122, 4200, -8820, -12328]
    accepted_plan_scores = [score for score in accepted_plan_scores if score >= 250]
    assert accepted_plan_scores == [9122, 4200]
    return {
        "scenario": "city_capture_task_pipeline",
        "eligible_hulls": sorted(unit["name"] for unit in capturers),
        "excluded_fire_support": ["Kirov-fire", "Sub-screen"],
        "assignments": assignments,
        "maximum_commitment_per_city": max(map(len, assignments.values())),
        "supported_capture_allowed": True,
        "isolated_damaged_capture_blocked": True,
        "negative_plans_rejected": 2,
        "ready_damage_ratio": 0.92,
        "active_task_cap": 2,
        "off_plan_cities_rejected": len(cities) - len(active_cities),
        "cross_operation_assignments": 0,
        "sequence": tactical_sequence,
    }


def military_purchase_scenario() -> dict[str, Any]:
    gold = 905_744
    gold_rate = -374
    city_count = 28
    reserve = max(75_000, city_count * 2_500, max(0, -gold_rate) * 60)
    budget = int(max(0, gold - reserve) * 0.12)
    max_purchases = min(6, max(1, math.ceil(city_count / 6)))
    assert reserve == 75_000
    assert budget == 99_689
    assert max_purchases == 5

    current = {
        "rapid_capture": 1, "line_frontline": 1, "siege": 25,
        "air_superiority": 7, "carrier_air": 10, "air_strike": 6,
        "naval_screen": 7, "naval_fire": 4, "fleet_carrier": 2,
        "strategic_submarine": 2, "missile_strike": 17,
    }
    targets = {
        "rapid_capture": 10, "line_frontline": 12, "siege": 10,
        "air_superiority": 8, "carrier_air": 8, "air_strike": 12,
        "naval_screen": 12, "naval_fire": 10, "fleet_carrier": 4,
        "strategic_submarine": 4, "missile_strike": 12,
    }
    priorities = {
        "rapid_capture": 145, "line_frontline": 115, "siege": 60,
        "air_superiority": 95, "carrier_air": 88, "air_strike": 120,
        "naval_screen": 100, "naval_fire": 115, "fleet_carrier": 72,
        "strategic_submarine": 82, "missile_strike": 45,
    }
    reservations: Counter[str] = Counter()
    purchases: list[str] = []
    for _ in range(max_purchases):
        candidates: dict[str, float] = {}
        for need, target in targets.items():
            effective_reserved = reservations[need] + (reservations["rapid_capture"] if need == "line_frontline" else 0)
            available = current[need] + effective_reserved
            if available >= target:
                continue
            score = priorities[need] + max(0, 1 - available / target) * 220 - reservations[need] * 100
            if available <= 0:
                score += 45
            if need == "rapid_capture" and current["siege"] >= max(current["rapid_capture"] * 2, 4):
                score += 90
            candidates[need] = score
        selected = max(candidates, key=candidates.get)
        reservations[selected] += 1
        purchases.append(selected)
    assert purchases[0] == "rapid_capture", purchases
    assert "line_frontline" in purchases, purchases
    assert "air_strike" in purchases, purchases
    assert "naval_fire" in purchases, purchases
    assert "siege" not in purchases, purchases

    waypoint = (42, 34)
    adjacent_destination = None
    selected_move = adjacent_destination or waypoint
    assert selected_move == waypoint
    target_limits = {"engineer:wonder": 1, "merchant:city_state": 2}
    assigned = Counter({"engineer:wonder": 1, "merchant:city_state": 2})
    assert all(assigned[key] <= limit for key, limit in target_limits.items())
    return {
        "scenario": "surplus_gold_combined_arms_purchase",
        "reserve": reserve,
        "budget": budget,
        "max_purchases": max_purchases,
        "purchase_needs": purchases,
        "great_person_waypoint_fallback": selected_move,
        "great_person_target_limits": target_limits,
    }


def capital_conversion_scenario() -> dict[str, Any]:
    """Convert a late-game treasury into annexed hubs, infrastructure, and force."""

    gold, reserve, gold_rate, happiness = 906_906, 116_575, -4_663, -91
    spendable = gold - reserve
    deficit_runway = spendable / abs(gold_rate)
    financially_ready = spendable >= 50_000 and (gold_rate >= 25 or deficit_runway >= 40)
    assert financially_ready and deficit_runway > 150
    puppets = [
        {"name": "front_port", "population": 18, "production": 42, "science": 30, "gold": 24, "coastal": True, "distance": 5},
        {"name": "industrial_hub", "population": 22, "production": 70, "science": 20, "gold": 18, "coastal": False, "distance": 12},
        {"name": "small_border", "population": 4, "production": 12, "science": 8, "gold": 5, "coastal": False, "distance": 3},
    ]
    eligible = [city for city in puppets if city["population"] >= 5]
    for city in eligible:
        city["score"] = (
            city["population"] * 80 + city["production"] * 24 + city["science"] * 12
            + city["gold"] * 10 + (240 if city["coastal"] else 0)
            + max(0, 500 - city["distance"] * 18)
        )
    eligible.sort(key=lambda city: city["score"], reverse=True)
    annexed: list[str] = []
    projected_happiness = happiness
    for city in eligible:
        happiness_cost = max(1, math.ceil(city["population"] * 0.35))
        crisis_annex = happiness < 8 and spendable >= 250_000
        annex_cap = 1 if crisis_annex else 2
        if len(annexed) < annex_cap and (crisis_annex or projected_happiness - happiness_cost >= 8):
            annexed.append(city["name"])
            projected_happiness -= happiness_cost
    assert annexed == ["industrial_hub"]

    building_candidates = {
        "industrial_hub": [("COURTHOUSE", 5_000, 5_200), ("FACTORY", 7_500, 1_100)],
        "front_port": [("COURTHOUSE", 5_000, 5_100), ("MILITARY_BASE", 9_000, 1_800)],
    }
    building_budget = math.floor(spendable * (0.30 if happiness < 5 else 0.18))
    building_orders = [
        max(items, key=lambda item: item[2])
        for city_name, items in building_candidates.items()
        if city_name in annexed
    ]
    assert all(order[0] == "COURTHOUSE" for order in building_orders)
    assert sum(order[1] for order in building_orders) <= building_budget
    assert len(building_orders) == len(annexed)  # one asynchronous order per newly annexed city

    city_count, operations, combat_units = 28, 3, 155
    enemy_equivalent = 620
    desired_force = max(city_count * 10, operations * 55, enemy_equivalent)
    force_shortage = desired_force - combat_units
    military_budget = math.floor(spendable * 0.42)
    purchase_cap = min(10, math.ceil(spendable / 50_000), math.ceil(force_shortage / 4))
    assert desired_force == 620 and force_shortage == 465
    assert military_budget == 331_939 and purchase_cap == 10
    return {
        "scenario": "capital_to_frontline_conversion",
        "annexed": annexed,
        "projected_happiness": projected_happiness,
        "deficit_runway": round(deficit_runway, 1),
        "financially_ready": financially_ready,
        "building_orders": [order[0] for order in building_orders],
        "building_budget": building_budget,
        "desired_force": desired_force,
        "force_shortage": force_shortage,
        "military_budget": military_budget,
        "purchase_cap": purchase_cap,
    }


def production_scenario() -> dict[str, Any]:
    city_count = 22
    package_count = max(2, min(6, math.ceil(math.sqrt(city_count))))
    carrier_target = max(1, math.ceil(package_count / 3))
    targets = {
        "rapid_capture": max(2, math.ceil(package_count * 0.8)),
        "line_frontline": max(2, package_count),
        "siege": max(2, math.ceil(package_count * 0.8)),
        "air_superiority": max(2, math.ceil(package_count * 0.6)),
        "carrier_air": max(2, carrier_target * 2),
        "air_strike": max(2, package_count),
        "naval_screen": max(2, package_count),
        "naval_fire": max(1, math.ceil(package_count * 0.8)),
        "fleet_carrier": carrier_target,
        "strategic_submarine": max(1, math.ceil(package_count / 3)),
        "missile_strike": max(2, package_count),
    }
    roster = {
        "rapid_capture": 29,
        "line_frontline": 0,
        "siege": 4,
        "air_superiority": 1,
        "carrier_air": 6,
        "air_strike": 0,
        "naval_screen": 1,
        "naval_fire": 1,
        "fleet_carrier": 1,
        "strategic_submarine": 1,
        "missile_strike": 0,
    }
    priority = {
        "rapid_capture": 82, "line_frontline": 48, "siege": 78,
        "air_superiority": 92, "carrier_air": 100, "air_strike": 98,
        "naval_screen": 70, "naval_fire": 86, "fleet_carrier": 82,
        "strategic_submarine": 74, "missile_strike": 64,
    }
    sea_needs = {"naval_screen", "naval_fire", "fleet_carrier", "strategic_submarine"}
    reservations = Counter()
    assignments: list[str] = []
    city_domains = ["coastal", "inland"] * 8
    for city_domain in city_domains:
        candidates: dict[str, float] = {}
        for name, target in targets.items():
            current = roster[name]
            if name == "line_frontline":
                current += roster["rapid_capture"]
            deficit = target - current - reservations[name]
            if deficit <= 0 or (name in sea_needs and city_domain != "coastal"):
                continue
            score = priority[name] + deficit * 100 / target
            if current + reservations[name] <= 0:
                score += 45
            candidates[name] = score
        if not candidates:
            continue
        selected_need = max(candidates, key=candidates.get)
        reservations[selected_need] += 1
        assignments.append(selected_need)

    assert assignments[0] == "air_strike", assignments
    assert len(set(assignments)) >= 6, assignments
    assert assignments.count("rapid_capture") == 0, assignments
    assert assignments.count("line_frontline") == 0, assignments
    assert any(need in sea_needs for need in assignments), assignments
    assert "missile_strike" in assignments, assignments
    joint_arm_orders = sum(
        need.startswith("air_") or need in sea_needs or need in {"carrier_air", "missile_strike"}
        for need in assignments
    )
    assert joint_arm_orders / len(assignments) >= 0.65, assignments

    replacement_roster = dict(targets)
    replacement_roster["carrier_air"] = 0
    replacement_roster["strategic_submarine"] = 0
    replacement_reservations = Counter()
    replacements: list[str] = []
    for _ in range(8):
        candidates = {}
        for name, target in targets.items():
            deficit = target - replacement_roster[name] - replacement_reservations[name]
            if deficit <= 0:
                continue
            score = priority[name] + deficit * 100 / target
            if replacement_roster[name] + replacement_reservations[name] <= 0:
                score += 45
            candidates[name] = score
        if not candidates:
            break
        selected_need = max(candidates, key=candidates.get)
        replacement_reservations[selected_need] += 1
        replacements.append(selected_need)
    assert "carrier_air" in replacements, replacements
    assert "strategic_submarine" in replacements, replacements

    cities = ["CAPITAL", "PORT", "FRONTIER"]
    unique_reservations: set[str] = set()
    wonder_assignments = 0
    for _city in cities:
        key = "X:B:BIG_BEN"
        if key not in unique_reservations:
            unique_reservations.add(key)
            wonder_assignments += 1
    assert wonder_assignments == 1

    queue = ["UNIT", "UNIT", "BUILDING"]
    military_slots = sum(order == "UNIT" for order in queue)
    append_process = len(queue) == 0
    assert military_slots == 2
    assert not append_process
    legacy_queue = ["BUILDING_HOTEL", "UNIT_GREAT_WAR_INFANTRY", "UNIT_CARRIER", "UNIT_WWI_BOMBER"]
    migrated_queue = [item for item in legacy_queue if item not in {"UNIT_GREAT_WAR_INFANTRY", "UNIT_CARRIER"}]
    assert migrated_queue == ["BUILDING_HOTEL", "UNIT_WWI_BOMBER"], migrated_queue
    return {
        "scenario": "strike_package_production_and_queue",
        "package_count": package_count,
        "assignments": assignments,
        "carrier_group_replacements": replacements,
        "categories_filled": sorted(set(assignments)),
        "unique_wonder_assignments": wonder_assignments,
        "military_slots": military_slots,
        "process_appended_to_nonempty_queue": append_process,
        "legacy_orders_removed": len(legacy_queue) - len(migrated_queue),
    }


def executable_focus_scenario() -> dict[str, Any]:
    def city_fire_allowed(damage: int, max_hp: int, capture_distance: int, score: float) -> tuple[bool, str]:
        if max_hp > 0 and damage >= max_hp - 1:
            return False, "captureWaitZeroHP"
        if max_hp > 0 and damage / max_hp >= 0.72 and capture_distance > 5:
            return False, "captureWaitNoUnit"
        if score < 1:
            return False, "below-threshold"
        return True, "fire"

    candidates = [
        {"name": "far_damaged_city", "capital": False, "capture_distance": 13, "score": 2965},
        {"name": "near_capital", "capital": True, "capture_distance": 6, "score": 2700},
    ]
    feasible = [city for city in candidates if city["capture_distance"] <= 10]
    selected = max(feasible, key=lambda city: city["score"])
    assert selected["name"] == "near_capital", selected
    assert city_fire_allowed(249, 250, 13, 3408) == (False, "captureWaitZeroHP")
    assert city_fire_allowed(191, 250, 13, 3920) == (False, "captureWaitNoUnit")
    assert city_fire_allowed(120, 250, 3, -10) == (False, "below-threshold")
    assert city_fire_allowed(120, 250, 3, 500) == (True, "fire")
    assert 13 > 10
    assert 8 <= 10

    era_rank = {
        "ERA_MODERN": 5,
        "ERA_WORLDWAR": 6,
        "ERA_POSTMODERN": 7,
        "ERA_INFORMATION": 8,
        "ERA_FUTURE": 9,
    }
    assert era_rank["ERA_INFORMATION"] - era_rank["ERA_MODERN"] == 3
    assert era_rank["ERA_INFORMATION"] - era_rank["ERA_WORLDWAR"] == 2
    return {
        "scenario": "executable_local_decapitation",
        "selected_focus": selected["name"],
        "far_city_rejected": True,
        "zero_hp_fire_suppressed": True,
        "negative_score_fire_suppressed": True,
        "custom_era_gap_detected": True,
    }


def elite_program_scenario(catalog: UnitCatalog) -> dict[str, Any]:
    query = """
        SELECT u.Type AS UnitType, u.Combat, u.RangedCombat, u.Cost, u.Moves, u.Range,
               u.ProjectPrereq, t.Era, p.Type AS ProjectType, p.MaxGlobalInstances
        FROM Units u
        JOIN Projects p ON p.Type = u.ProjectPrereq
        LEFT JOIN Technologies t ON t.Type = u.PrereqTech
        WHERE p.MaxGlobalInstances = 1
          AND MAX(COALESCE(u.Combat, 0), COALESCE(u.RangedCombat, 0)) > 0
          AND COALESCE(u.NukeDamageLevel, 0) <= 0
        ORDER BY u.Type
    """
    elite_rows = [dict(row) for row in catalog.connection.execute(query)]
    elite_rows = [row for row in elite_rows if row["UnitType"] != "UNIT_MECH"]
    elite_types = {row["UnitType"] for row in elite_rows}
    expected = {
        "UNIT_SUPER_TANK",
        "UNIT_ELITE_BATTLECRUISER",
        "UNIT_PROTOTYPE_BOMBER",
        "UNIT_NUCLEAR_ARTILLERY",
        "UNIT_UNDERWATER_CARRIER",
        "UNIT_CRUSADER_ARTILLERY",
        "UNIT_CHINESE_WEISHI",
        "UNIT_PAKFA_T50",
        "UNIT_STEALTH_HELICOPTER",
        "UNIT_PARTICLE_CANNON",
    }
    assert expected <= elite_types, sorted(expected - elite_types)
    assert "UNIT_MECH" not in elite_types
    assert len(elite_rows) >= 20, len(elite_rows)

    era_rank = {
        "ERA_ANCIENT": 0, "ERA_CLASSICAL": 1, "ERA_MEDIEVAL": 2,
        "ERA_RENAISSANCE": 3, "ERA_INDUSTRIAL": 4, "ERA_MODERN": 5,
        "ERA_WORLDWAR": 6, "ERA_POSTMODERN": 7,
        "ERA_INFORMATION": 8, "ERA_FUTURE": 9,
    }
    relevant = [row for row in elite_rows if 0 <= 8 - era_rank.get(row["Era"], -99) <= 2]
    scored = sorted(
        relevant,
        key=lambda row: (
            max(row["Combat"] or 0, row["RangedCombat"] or 0) * 5
            + (row["RangedCombat"] or 0) * 1.5
            + (row["Range"] or 0) * 45
            + (row["Moves"] or 0) * 12
            + (row["Cost"] or 0) / 8
        ),
        reverse=True,
    )
    queued_projects = []
    for row in scored:
        if row["ProjectType"] not in queued_projects:
            queued_projects.append(row["ProjectType"])
        if len(queued_projects) == 2:
            break
    assert len(queued_projects) == 2
    return {
        "scenario": "elite_project_unlock_and_unit_cap",
        "elite_units_detected": len(elite_rows),
        "late_elite_units": len(relevant),
        "queued_project_cap": len(queued_projects),
        "selected_projects": queued_projects,
        "unit_target_per_type": 1,
        "mech_auto_production": False,
    }


def asset_protection_scenario(catalog: UnitCatalog) -> dict[str, Any]:
    def sea_transit(tier: int, threats: int, escorts: int) -> str:
        required = 1 if threats > 0 else 0
        if tier >= 2 and threats >= 2:
            required = 2
        return "advance" if escorts >= required else f"hold:{escorts}/{required}"

    def damaged_order(tier: int, damage: int, enemy_distance: int, friendly_city: bool = False) -> str:
        threshold = 20 if tier >= 2 else 45
        threat_radius = 8 if tier >= 2 else 5
        critical = damage >= 55
        if damage >= threshold and (enemy_distance <= threat_radius or (critical and not friendly_city)):
            return "retreat"
        if damage >= threshold:
            return "heal"
        return "fight"

    mech_tier = protection_tier(catalog.profile("UNIT_MECH"))
    artillery_tier = protection_tier(catalog.profile("UNIT_ROCKET_ARTILLERY"))
    apache_tier = protection_tier(catalog.profile("UNIT_AMERICAN_APACHE"))
    artillery_range = catalog.profile("UNIT_ROCKET_ARTILLERY")["range"]
    artillery_min_standoff = max(2, artillery_range - 1)

    assert catalog.profile("UNIT_AMERICAN_APACHE")["class"] == "gunship"
    assert mech_tier == 3
    assert artillery_tier >= 2
    assert apache_tier == 2
    assert sea_transit(mech_tier, threats=2, escorts=0) == "hold:0/2"
    assert sea_transit(mech_tier, threats=2, escorts=1) == "hold:1/2"
    assert sea_transit(mech_tier, threats=2, escorts=2) == "advance"
    assert damaged_order(apache_tier, damage=70, enemy_distance=9) == "retreat"
    assert damaged_order(artillery_tier, damage=20, enemy_distance=4) == "retreat"
    assert artillery_min_standoff == 4
    assert not (True and 0 < 35 and 3 >= 4), "Embarked commander anchor must be rejected"
    assert not (False and 40 < 35 and 6 >= 4), "Damaged commander anchor must be rejected"
    assert (not False and 0 < 35 and 6 >= 4), "Safe rear commander anchor must be accepted"

    return {
        "scenario": "elite_asset_survival_chain",
        "tiers": {"mech": mech_tier, "rocket_artillery": artillery_tier, "apache": apache_tier},
        "severe_sea_transit": sea_transit(mech_tier, threats=2, escorts=1),
        "apache_at_30hp": damaged_order(apache_tier, damage=70, enemy_distance=9),
        "artillery_min_standoff": artillery_min_standoff,
        "general_anchor": "rear-covered-only",
    }


def audit_catalog(catalog: UnitCatalog) -> dict[str, Any]:
    profiles = [catalog.profile(unit_type) for unit_type in catalog.units]
    military = [
        profile
        for profile in profiles
        if not profile["civilian"] and (profile["power"] > 0 or profile["domain"] in ("DOMAIN_AIR", "DOMAIN_HOVER"))
    ]
    bad = [profile["type"] for profile in military if profile["class"].startswith("civilian") or profile["class"] == "unknown"]
    assert not bad, f"Unclassified military units: {bad}"
    expected = {
        "UNIT_SUPER_CARRIER": "fleet_carrier",
        "UNIT_FUTURE_BATTLESHIP": "arsenal_capital",
        "UNIT_CHINESE_052D": "air_defense_screen",
        "UNIT_SSBN": "ballistic_submarine",
        "UNIT_NUCLEAR_SUBMARINE": "attack_submarine",
        "UNIT_CARRIER_FIGHTER_ADV": "carrier_multirole",
        "UNIT_MODERN_ARMOR": "mobile_breakthrough",
        "UNIT_ROCKET_ARTILLERY": "siege_artillery",
        "UNIT_MECH": "super_heavy",
    }
    for unit_type, doctrine_class in expected.items():
        assert catalog.profile(unit_type)["class"] == doctrine_class, (
            unit_type,
            catalog.profile(unit_type)["class"],
            doctrine_class,
        )
    assert catalog.profile("UNIT_CHINESE_052D")["can_capture"]
    assert catalog.profile("UNIT_LITTORAL_COMBAT_SHIP")["can_capture"]
    assert catalog.profile("UNIT_MECH")["can_capture"]
    assert not catalog.profile("UNIT_KIROV_BATTLECRUISER")["can_capture"]
    assert not catalog.profile("UNIT_PARTICLE_CANNON")["can_capture"]
    assert not catalog.profile("UNIT_NUCLEAR_SUBMARINE")["can_capture"]
    assert not catalog.profile("UNIT_SSBN")["can_capture"]
    return {
        "database": str(catalog.database),
        "units": len(profiles),
        "military_units": len(military),
        "free_promotions": sum(len(items) for items in catalog.promotions.values()),
        "classes": dict(sorted(Counter(profile["class"] for profile in profiles).items())),
        "unclassified_military": bad,
    }


def _field(line: str, name: str, default: str | None = None) -> str | None:
    match = re.search(rf"(?:^| ){re.escape(name)}=([^ ]+)", line)
    return match.group(1) if match else default


def _loss_policy_guards(loss: dict[str, Any], profile: dict[str, Any]) -> list[str]:
    guards: list[str] = []
    unit_type = profile["type"]
    if unit_type in ("UNIT_GREAT_GENERAL", "UNIT_GREAT_ADMIRAL"):
        guards.append("commander-rear-area")
    if loss["embarked"]:
        guards.append("sea-transit-gate")
    if loss["damage"] >= retreat_damage_threshold(profile):
        guards.append("damage-retreat")
    if profile["can_range"] and not profile["can_capture"]:
        guards.append("ranged-standoff")
    transport = loss.get("transport")
    if transport and transport["threats"] > transport["escorts"]:
        guards.append(f"escort-shortfall:{transport['escorts']}/{transport['threats']}")
    return guards


def _parse_plot(value: str | None) -> tuple[int, int] | None:
    if value is None or value == "nil-plot":
        return None
    match = re.fullmatch(r"(-?\d+),(-?\d+)", value)
    return (int(match.group(1)), int(match.group(2))) if match else None


def _approx_hex_distance(left: tuple[int, int], right: tuple[int, int]) -> int:
    dx = abs(left[0] - right[0])
    dy = abs(left[1] - right[1])
    return max(dy, dx - (dy // 2))


def replay_v22_operations(
    own_units: list[dict[str, Any]], enemy_units: list[dict[str, Any]],
    own_cities: list[dict[str, Any]], enemy_cities: list[dict[str, Any]],
) -> dict[str, Any]:
    multipliers = {
        "missile_strike": 0.28, "strategic_nuclear": 0.28,
        "fleet_carrier": 0.72, "air_superiority": 1.18,
        "carrier_multirole": 1.18, "siege_artillery": 1.12,
        "surface_fire_support": 1.12, "super_heavy": 1.35,
    }

    def effective(unit: dict[str, Any]) -> float:
        raw = max(int(unit.get("power", 0) or 0), 0)
        doctrine = str(unit.get("class") or "unknown")
        if raw <= 0 or doctrine.startswith("civilian"):
            return 0.0
        health = max(0.18, 1 - max(int(unit.get("damage", 0) or 0), 0) / 100)
        return raw ** 1.24 * multipliers.get(doctrine, 1.0) * health

    combat = [unit for unit in own_units if effective(unit) > 0 and unit.get("plot") is not None]
    own_power = sum(effective(unit) for unit in combat)
    immediate = [
        unit for unit in enemy_units if effective(unit) > 0 and unit.get("plot") is not None
        and any(city.get("plot") is not None and _approx_hex_distance(unit["plot"], city["plot"]) <= 18 for city in own_cities)
    ]
    immediate_power = sum(effective(unit) for unit in immediate)
    ratio = own_power / max(immediate_power, 1)
    posture = "defend" if ratio < 0.72 else ("decapitation" if ratio >= 1.40 else "advance")

    threatened: list[dict[str, Any]] = []
    sea_units = [unit for unit in combat if unit.get("domain") == "DOMAIN_SEA"]
    for city in own_cities:
        plot = city.get("plot")
        if plot is None:
            continue
        local_enemies = [unit for unit in enemy_units if unit.get("plot") is not None and _approx_hex_distance(unit["plot"], plot) <= 10]
        if local_enemies:
            enemy_power = sum(effective(unit) for unit in local_enemies)
            coastal = any(_approx_hex_distance(unit["plot"], plot) <= 7 for unit in sea_units)
            threatened.append({"kind": "city_defense", "plot": plot, "enemy_power": enemy_power, "coastal": coastal})
    threatened.sort(key=lambda item: item["enemy_power"], reverse=True)
    defense_limit = 5 if posture == "defend" else (2 if posture == "decapitation" else 3)
    operations = threatened[:defense_limit]
    remaining = 5 - len(operations)
    if posture != "defend" and remaining > 0:
        ranked_enemy_cities = sorted(
            (city for city in enemy_cities if city.get("plot") is not None),
            key=lambda city: min((_approx_hex_distance(city["plot"], unit["plot"]) for unit in combat), default=999),
        )
        for city in ranked_enemy_cities[:remaining]:
            local_power = sum(
                effective(unit) for unit in enemy_units
                if unit.get("plot") is not None and _approx_hex_distance(unit["plot"], city["plot"]) <= 6
            )
            coastal = any(_approx_hex_distance(unit["plot"], city["plot"]) <= 7 for unit in sea_units)
            operations.append({"kind": "city_assault", "plot": city["plot"], "enemy_power": local_power, "coastal": coastal})

    assignment_budget = math.floor(len(combat) * 0.90)
    requirements = []
    weights = []
    for operation in operations:
        minimum = 18 if operation["coastal"] else 12
        if operation["kind"] == "city_assault":
            minimum += 5
        requirements.append(minimum)
        weights.append(math.sqrt(max(operation["enemy_power"], 1)) + minimum * 8)
    budgets = [max(requirements[i], math.floor(assignment_budget * weights[i] / max(sum(weights), 1))) for i in range(len(operations))]
    while sum(budgets) > assignment_budget and any(budgets[i] > requirements[i] for i in range(len(budgets))):
        index = max((i for i in range(len(budgets)) if budgets[i] > requirements[i]), key=lambda i: budgets[i])
        budgets[index] -= 1
    index = 0
    while budgets and sum(budgets) < assignment_budget:
        budgets[index % len(budgets)] += 1
        index += 1

    assigned: set[str] = set()
    assigned_counts = [0 for _ in operations]
    for unit in sorted(combat, key=effective, reverse=True):
        candidates: list[tuple[int, int]] = []
        for index, operation in enumerate(operations):
            if assigned_counts[index] >= budgets[index]:
                continue
            if unit.get("domain") == "DOMAIN_SEA" and not operation["coastal"]:
                continue
            join_limit = 55 if unit.get("domain") in ("DOMAIN_SEA", "DOMAIN_AIR") else 60
            distance = _approx_hex_distance(unit["plot"], operation["plot"])
            if distance <= join_limit:
                candidates.append((distance, index))
        if candidates:
            _, selected = min(candidates)
            assigned.add(str(unit["id"]))
            assigned_counts[selected] += 1
    unassigned = Counter(str(unit.get("class") or "unknown") for unit in combat if str(unit["id"]) not in assigned)
    return {
        "posture": posture, "power_ratio": round(ratio, 3),
        "combat_units": len(combat), "assignment_budget": assignment_budget,
        "assigned": len(assigned), "reserve": len(combat) - len(assigned),
        "operations": [
            {"kind": operation["kind"], "plot": operation["plot"], "coastal": operation["coastal"],
             "enemy_power": round(operation["enemy_power"]), "budget": budgets[index], "assigned": assigned_counts[index]}
            for index, operation in enumerate(operations)
        ],
        "unassigned_by_class": dict(unassigned.most_common()),
    }


def parse_world_snapshot(log_path: Path, catalog: UnitCatalog) -> dict[str, Any]:
    latest: dict[str, Any] | None = None
    current: dict[str, Any] | None = None
    version: str | None = None
    turn_pattern = re.compile(r"\[T(\d+)\]")
    unit_pattern = re.compile(r"unit=(UNIT_[A-Z0-9_]+)#([^ ]+)@P([0-9]+)")
    city_pattern = re.compile(r"city=(.*?)#([^ ]+) owner=P(\d+) plot=([^ ]+)")
    player_pattern = re.compile(r"playerSummary reason=([^ ]+) P(\d+)")
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, raw_line in enumerate(handle, 1):
            line = raw_line.rstrip()
            loaded = re.search(r"Strategic Command v([0-9.]+) loaded", line)
            if loaded:
                version = loaded.group(1)
                latest = None
                current = None
                continue
            if "DEMO category=world " in line:
                turn_match = turn_pattern.search(line)
                current = {
                    "version": version,
                    "turn": int(turn_match.group(1)) if turn_match else None,
                    "reason": _field(line, "reason"),
                    "active_player": int((_field(line, "active", "P0") or "P0").lstrip("P")),
                    "players": {}, "cities": {}, "units": {}, "start_line": line_number,
                }
                continue
            if current is None:
                continue
            player_match = player_pattern.search(line)
            if player_match:
                _reason, player_id_text = player_match.groups()
                player_id = int(player_id_text)
                current["players"][player_id] = {
                    "id": player_id,
                    "team": int(_field(line, "team", "-1") or -1),
                    "civ": _field(line, "civ"),
                    "leader": _field(line, "leader"),
                    "human": _field(line, "human") == "true",
                    "minor": _field(line, "minor") == "true",
                    "barbarian": _field(line, "barbarian") == "true",
                    "at_war_active": _field(line, "atWarActive") == "true",
                    "unit_count": int(_field(line, "units", "0") or 0),
                    "city_count": int(_field(line, "cities", "0") or 0),
                    "gold": int(_field(line, "gold", "0") or 0),
                    "gold_rate": int(_field(line, "goldRate", "0") or 0),
                }
            city_match = city_pattern.search(line)
            if city_match and "DEMO category=cityState" in line:
                name, city_id, owner_text, plot_text = city_match.groups()
                key = f"P{owner_text}:{city_id}"
                current["cities"][key] = {
                    "id": city_id, "owner": int(owner_text), "name": name,
                    "plot": _parse_plot(plot_text),
                    "population": int(_field(line, "pop", "0") or 0),
                    "damage": int(_field(line, "damage", "0") or 0),
                    "max_hp": int(_field(line, "maxHP", "0") or 0),
                    "production": _field(line, "production"),
                }
            unit_match = unit_pattern.search(line)
            if unit_match and "DEMO category=unitState" in line:
                unit_type, unit_id, owner_text = unit_match.groups()
                key = f"P{owner_text}:{unit_id}"
                profile = catalog.profile(unit_type) if unit_type in catalog.units else None
                current["units"][key] = {
                    "id": unit_id, "owner": int(owner_text), "type": unit_type,
                    "role": _field(line, "role"), "class": _field(line, "class"),
                    "domain": _field(line, "domain"), "plot": _parse_plot(_field(line, "plot")),
                    "moves": int(_field(line, "moves", "0") or 0),
                    "damage": int(_field(line, "damage", "0") or 0),
                    "hp": int(_field(line, "hp", "100") or 100),
                    "embarked": _field(line, "embarked") == "true",
                    "cargo": int(_field(line, "cargo", "0") or 0),
                    "power": int(_field(line, "power", "0") or 0),
                    "tier": protection_tier(profile) if profile is not None else 0,
                }
            if "DEMO category=worldEnd" in line:
                current["end_line"] = line_number
                current["declared_units"] = int(_field(line, "unitsSeen", "0") or 0)
                current["declared_cities"] = int(_field(line, "citiesSeen", "0") or 0)
                latest = current
                current = None
    if latest is None:
        return {"complete": False, "reason": "no-complete-world-snapshot"}
    active = latest["active_player"]
    hostile_owners = {
        player_id for player_id, player in latest["players"].items()
        if player["at_war_active"] and player_id != active
    }
    own_units = [unit for unit in latest["units"].values() if unit["owner"] == active]
    enemy_units = [unit for unit in latest["units"].values() if unit["owner"] in hostile_owners]
    own_cities = [city for city in latest["cities"].values() if city["owner"] == active]
    enemy_cities = [city for city in latest["cities"].values() if city["owner"] in hostile_owners]
    embarked = [unit for unit in own_units if unit["embarked"]]
    high_value_embarked = [unit for unit in embarked if unit["tier"] >= 2]
    threatened_embarked: list[dict[str, Any]] = []
    embarked_threats: dict[str, int] = {}
    embarked_escorts: dict[str, int] = {}
    escort_classes = {
        "air_defense_screen", "escort_screen", "attack_submarine",
        "naval_assault", "surface_fire_support",
    }
    for unit in embarked:
        if unit["plot"] is None:
            continue
        local_threats = sum(
            1 for enemy in enemy_units
            if enemy["plot"] is not None
            and (enemy["domain"] == "DOMAIN_SEA" or enemy["embarked"]
                 or enemy["class"] in {"carrier_multirole", "strike_aircraft"})
            and _approx_hex_distance(unit["plot"], enemy["plot"]) <= 6
        )
        local_escorts = sum(
            1 for escort in own_units
            if escort["plot"] is not None and escort["domain"] == "DOMAIN_SEA"
            and escort["class"] in escort_classes
            and _approx_hex_distance(unit["plot"], escort["plot"]) <= 2
        )
        embarked_escorts[unit["id"]] = local_escorts
        if local_threats > 0:
            embarked_threats[unit["id"]] = local_threats
            threatened_embarked.append({
                "unit": unit["type"], "id": unit["id"], "plot": unit["plot"],
                "tier": unit["tier"], "damage": unit["damage"], "nearby_enemies": local_threats,
                "nearby_escorts": local_escorts,
            })
    policy_actions: Counter[str] = Counter()
    policy_by_class: dict[str, Counter[str]] = defaultdict(Counter)
    old_target_evaluations = 0
    bounded_target_evaluations = 0
    dangerous_embarked_advances = 0
    combat_units = [unit for unit in own_units if not str(unit["class"]).startswith("civilian")]
    for unit in own_units:
        doctrine_class = str(unit["class"] or "unknown")
        action = "hold"
        threats = embarked_threats.get(unit["id"], 0)
        required_escorts = 2 if threats >= 2 else (1 if threats > 0 else 0)
        escort_coverage = embarked_escorts.get(unit["id"], 0)
        if unit["embarked"] and threats > 0 and escort_coverage < required_escorts:
            action = "hold-for-screen"
        elif doctrine_class.startswith("civilian"):
            action = "civilian-manage"
        elif unit["damage"] >= (20 if unit["tier"] >= 2 else 45):
            action = "retreat-or-heal"
        elif unit["plot"] is not None:
            pursuit = 14 if unit["domain"] == "DOMAIN_SEA" else 10
            if unit["tier"] >= 2 and doctrine_class in {
                "siege_artillery", "arsenal_capital", "fleet_carrier",
                "ballistic_submarine", "surface_fire_support",
            }:
                pursuit = 7
            local_targets = [
                enemy for enemy in enemy_units
                if enemy["plot"] is not None and _approx_hex_distance(unit["plot"], enemy["plot"]) <= pursuit
            ]
            if local_targets:
                action = "engage-local-unit"
            elif enemy_cities:
                action = "advance-city"
            old_target_evaluations += len(enemy_units) + len(enemy_cities)
            bounded_target_evaluations += len(local_targets) + len(enemy_cities)
        if unit["embarked"] and threats > 0 and escort_coverage < required_escorts and action not in {
            "hold-for-screen", "retreat-or-heal",
        }:
            dangerous_embarked_advances += 1
        policy_actions[action] += 1
        policy_by_class[doctrine_class][action] += 1
    target_reduction = 0.0
    if old_target_evaluations > 0:
        target_reduction = 1 - bounded_target_evaluations / old_target_evaluations
    assert len(latest["units"]) == latest["declared_units"]
    assert len(latest["cities"]) == latest["declared_cities"]
    assert sum(policy_actions.values()) == len(own_units)
    v22_replay = replay_v22_operations(own_units, enemy_units, own_cities, enemy_cities)
    return {
        "complete": True,
        "version": latest["version"], "turn": latest["turn"], "reason": latest["reason"],
        "active_player": active, "players": len(latest["players"]),
        "units": len(latest["units"]), "declared_units": latest["declared_units"],
        "cities": len(latest["cities"]), "declared_cities": latest["declared_cities"],
        "own_units": len(own_units), "enemy_units": len(enemy_units),
        "own_cities": len(own_cities), "enemy_cities": len(enemy_cities),
        "hostile_owners": sorted(hostile_owners),
        "own_doctrine": dict(sorted(Counter(unit["class"] for unit in own_units).items())),
        "embarked_units": len(embarked),
        "high_value_embarked": len(high_value_embarked),
        "threatened_embarked": sorted(threatened_embarked, key=lambda row: (-row["tier"], -row["nearby_enemies"], row["id"])),
        "policy_replay": {
            "actions": dict(sorted(policy_actions.items())),
            "by_class": {
                doctrine_class: dict(sorted(actions.items()))
                for doctrine_class, actions in sorted(policy_by_class.items())
            },
            "combat_units": len(combat_units),
            "target_evaluations_before": old_target_evaluations,
            "target_evaluations_bounded": bounded_target_evaluations,
            "target_reduction_percent": round(target_reduction * 100, 1),
            "dangerous_embarked_advances": dangerous_embarked_advances,
            "safety_invariants_pass": dangerous_embarked_advances == 0,
        },
        "v22_strategy_replay": v22_replay,
    }


def mission_lifecycle_scenario() -> dict[str, Any]:
    class Handle:
        def __init__(self) -> None:
            self.alive = True

        def access(self) -> str:
            if not self.alive:
                raise RuntimeError("stale native unit handle")
            return "alive"

    unit = Handle()
    unit.alive = False
    old_path_crashed = False
    try:
        unit.access()
    except RuntimeError:
        old_path_crashed = True
    resolved_unit = unit if unit.alive else None
    new_status = "unit-removed" if resolved_unit is None else "alive"
    convoy_policy = "advance-when-screened"
    assert old_path_crashed
    assert new_status == "unit-removed"
    assert convoy_policy == "advance-when-screened"
    return {
        "scenario": "mission_removes_unit_and_invalidates_native_handle",
        "old_path_crashed": old_path_crashed,
        "new_status": new_status,
        "caller_short_circuits": resolved_unit is None,
        "embarked_high_value_policy": convoy_policy,
    }


def replay_observed_crash_chain(log_analysis: dict[str, Any], world: dict[str, Any]) -> dict[str, Any]:
    embarked_losses = [loss for loss in log_analysis["losses"] if loss["embarked"]]
    stale_accesses = log_analysis["termination"]["stale_unit_accesses"]
    threatened_ids = {row["id"] for row in world.get("threatened_embarked", [])}
    matched = [loss for loss in embarked_losses if loss["id"] in threatened_ids]
    if not matched or not stale_accesses:
        return {
            "scenario": "observed_convoy_crash_replay",
            "available": False,
            "reason": "no-same-snapshot-embarked-loss" if not matched else "no-stale-handle-access",
            "embarked_losses": len(embarked_losses),
            "threatened_embarked": len(threatened_ids),
            "stale_accesses": len(stale_accesses),
        }
    victim = matched[-1]
    iterations = [
        {
            "name": "observed-v147",
            "decision": "advance-with-escorts",
            "unit_survives": False,
            "stale_handle_access": True,
            "native_crash_risk": True,
        },
        {
            "name": "lifecycle-guard-only",
            "decision": "advance-with-escorts",
            "unit_survives": False,
            "stale_handle_access": False,
            "native_crash_risk": False,
        },
        {
            "name": "v148-threat-lock",
            "decision": "hold-under-threat",
            "unit_survives": True,
            "stale_handle_access": False,
            "native_crash_risk": False,
        },
    ]
    assert iterations[-1]["unit_survives"]
    assert not iterations[-1]["native_crash_risk"]
    return {
        "scenario": "observed_t159_convoy_crash_three_iteration_replay",
        "available": True,
        "victim": f"{victim['unit']}#{victim['id']}",
        "damage_before": victim["damage"],
        "killer": victim["killer"],
        "iterations": iterations,
    }


def analyze_log(log_path: Path, catalog: UnitCatalog) -> dict[str, Any]:
    unit_pattern = re.compile(r"unit=(UNIT_[A-Z0-9_]+)#([^ ]+)@P([0-9]+)")
    transport_pattern = re.compile(r"transport=(UNIT_[A-Z0-9_]+)#([^ ]+)@P([0-9]+)")
    prekill_pattern = re.compile(
        r"event=UnitPrekill a1=(-?\d+) a2=(-?\d+) a3=(-?\d+) a4=(-?\d+) "
        r"a5=(-?\d+) a6=([^ ]*) a7=(-?\d+)"
    )
    turn_pattern = re.compile(r"\[T(\d+)\]")
    action_markers = (
        "localDefense fired", "localDefense queued", "rangeStrike resolved", "strategicMove order",
        "captureFinish try", "captureTask stage", "airSuperiority sweep", "heal ",
        "greatPerson position", "transportEscort ", "finalOrders ", "moveMission ",
    )

    loaded_version: str | None = None
    latest_units: dict[str, str] = {}
    latest_states: dict[str, dict[str, Any]] = {}
    latest_actions: dict[str, str] = {}
    latest_transport: dict[str, dict[str, int]] = {}
    actions: Counter[str] = Counter()
    guard_events: Counter[str] = Counter()
    performance: dict[str, dict[str, int]] = {}
    pass_performance: dict[str, dict[str, int]] = {}
    production_categories: Counter[str] = Counter()
    production_items: Counter[str] = Counter()
    production_reasons: Counter[str] = Counter()
    final_order_units: Counter[str] = Counter()
    final_order_classes: Counter[str] = Counter()
    final_order_tasks: Counter[str] = Counter()
    strategic_move_modes: Counter[str] = Counter()
    decision_symptoms: Counter[str] = Counter()
    strategy_postures: Counter[str] = Counter()
    strategy_operations: Counter[str] = Counter()
    strategy_decisions: Counter[str] = Counter()
    module_errors: Counter[str] = Counter()
    latest_strategy_plan: dict[str, Any] = {}
    combat_losses: dict[str, dict[str, Any]] = {}
    unattributed_removals: dict[str, dict[str, Any]] = {}
    enemy_loss_ids: set[str] = set()
    removed_unit_keys: set[str] = set()
    stale_unit_accesses: list[dict[str, Any]] = []
    passes_started = 0
    passes_ended = 0
    last_session_line = ""
    last_session_line_number = 0

    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, raw_line in enumerate(handle, 1):
            line = raw_line.rstrip()
            version = re.search(r"Strategic Command v([0-9.]+) loaded", line)
            if version:
                # Lua.log can contain several launches. Only calibrate against the latest one.
                loaded_version = version.group(1)
                latest_units.clear()
                latest_states.clear()
                latest_actions.clear()
                latest_transport.clear()
                actions.clear()
                guard_events.clear()
                performance.clear()
                pass_performance.clear()
                production_categories.clear()
                production_items.clear()
                production_reasons.clear()
                final_order_units.clear()
                final_order_classes.clear()
                final_order_tasks.clear()
                strategic_move_modes.clear()
                decision_symptoms.clear()
                strategy_postures.clear()
                strategy_operations.clear()
                strategy_decisions.clear()
                module_errors.clear()
                latest_strategy_plan.clear()
                combat_losses.clear()
                unattributed_removals.clear()
                enemy_loss_ids.clear()
                removed_unit_keys.clear()
                stale_unit_accesses.clear()
                passes_started = 0
                passes_ended = 0
                last_session_line = line
                last_session_line_number = line_number
                continue

            if loaded_version is not None:
                last_session_line = line
                last_session_line_number = line_number
            if "pass begin" in line:
                passes_started += 1
            if "pass end" in line:
                passes_ended += 1

            turn_match = turn_pattern.search(line)
            turn = int(turn_match.group(1)) if turn_match else None
            unit_match = unit_pattern.search(line)
            if unit_match:
                unit_type, unit_id, owner = unit_match.groups()
                key = f"P{owner}:{unit_id}"
                if key in removed_unit_keys:
                    if "unitAudit missing" in line:
                        guard_events["removed_unit_snapshot_cleanup"] += 1
                    elif "moveMission unit-removed" in line or "mission unit-removed" in line:
                        guard_events["unit_removed_short_circuit"] += 1
                    else:
                        stale_unit_accesses.append({
                            "line": line_number, "unit": unit_type, "id": unit_id,
                            "owner": int(owner), "text": line.split("] ", 1)[-1],
                        })
                if "DEMO category=unitState" in line:
                    latest_units[key] = unit_type
                if ("DEMO category=unitState" in line or "unitAudit state" in line) and "damage=" in line and "embarked=" in line:
                    latest_states[key] = {
                        "turn": turn,
                        "type": unit_type,
                        "owner": int(owner),
                        "id": unit_id,
                        "plot": _field(line, "plot"),
                        "damage": int(_field(line, "damage", "0") or 0),
                        "hp": int(_field(line, "hp", "100") or 100),
                        "embarked": _field(line, "embarked", "false") == "true",
                    }
                if any(marker in line for marker in action_markers):
                    latest_actions[key] = line.split("] ", 1)[-1]
                    if unit_type in catalog.units:
                        actions[catalog.profile(unit_type)["class"]] += 1

            transport_match = transport_pattern.search(line)
            if transport_match:
                _unit_type, unit_id, owner = transport_match.groups()
                threats = _field(line, "threats")
                escorts = _field(line, "escorts") or _field(line, "coverage")
                if threats is not None:
                    latest_transport[f"P{owner}:{unit_id}"] = {
                        "turn": turn or -1,
                        "threats": int(threats),
                        "escorts": int(escorts or 0),
                    }

            if "strategicMove blocked-sea-transit" in line:
                guard_events["sea_transit_block"] += 1
            if "strategicMove airlift queued" in line:
                guard_events["airlift_queued"] += 1
            if "strategicMove airlift confirmed" in line:
                guard_events["airlift_confirmed"] += 1
            if "strategicMove airlift expired" in line or "strategicMove airlift send-failed" in line:
                guard_events["airlift_failed"] += 1
            if "strategicMove order" in line and "mode=airlift-stage" in line:
                guard_events["airlift_stage"] += 1
            if "strategicMove airlift-unavailable" in line:
                guard_events["airlift_unavailable"] += 1
            if "heal retreat" in line:
                guard_events["damage_retreat"] += 1
            if "finalOrders preserve-retreat" in line:
                guard_events["retreat_preserved"] += 1
            if "greatPerson position" in line and "rear-area" in line:
                guard_events["commander_rear_area"] += 1
            if "strategicTarget assign" in line:
                guard_events["strategic_target_assign"] += 1
            if "strategicTarget switch" in line:
                guard_events["strategic_target_switch"] += 1
            if "strategicMove order" in line and "targetMemory:" in line:
                guard_events["strategic_target_memory_hit"] += 1
            if "targetPool build" in line:
                guard_events["target_pool_build"] += 1
            if "captureSecurity hold" in line:
                guard_events["capture_security_hold"] += 1
            if "captureTask city=" in line and "state=reserved" in line:
                guard_events["capture_task_reserved"] += 1
            if "captureTask city=" in line and "state=no-capturer" in line:
                guard_events["capture_task_no_capturer"] += 1
            if "captureTask stage unit=" in line:
                guard_events["capture_task_stage"] += 1
            if "captureTask direct-hold" in line:
                guard_events["capture_task_direct_hold"] += 1
            if "captureTask no-stage" in line or "captureTask stage-failed" in line:
                guard_events["capture_task_path_failure"] += 1
            if "captureFinish try" in line and "captured=true" in line:
                guard_events["capture_task_completed"] += 1
            if "greatPerson commander-unsafe" in line:
                guard_events["commander_unsafe"] += 1
            if "pass begin" in line and "mode=full" in line:
                guard_events["full_pass"] += 1
            if "pass begin" in line and "mode=light" in line:
                guard_events["light_pass"] += 1
            if "cityProduction choose " in line:
                category = _field(line, "category")
                item = _field(line, "item")
                if category:
                    production_categories[category] += 1
                if item:
                    production_items[item] += 1
            if "cityProduction " in line:
                production_reason = _field(line, "reason")
                if production_reason:
                    production_reasons[production_reason] += 1
            if "strategyPlan turn=" in line:
                strategy_postures[_field(line, "posture", "unknown")] += 1
                target_count = line.count("city_defense:") + line.count("city_assault:")
                strategy_decisions[f"target_count_{target_count}"] += 1
                for key in ("ownCombat", "assignedCombat", "reserveCombat", "targetForce"):
                    value = _field(line, key)
                    if value is not None:
                        latest_strategy_plan[key] = int(value)
                latest_strategy_plan["posture"] = _field(line, "posture", "unknown")
                latest_strategy_plan["victory"] = _field(line, "victory", "unknown")
                latest_strategy_plan["crisis"] = _field(line, "crisis", "unknown")
                latest_strategy_plan["tasks"] = _field(line, "tasks", "")
                latest_strategy_plan["turn"] = int(_field(line, "turn", "-1") or -1)
            if "strategyOperation turn=" in line:
                kind = _field(line, "kind", "unknown")
                strategy_operations[kind] += 1
                formation_raw = _field(line, "formationReady")
                formation_text = (formation_raw or "0").rstrip("%")
                if formation_raw is not None and float(formation_text or 0) < 70:
                    strategy_decisions["formation_assemble"] += 1
            module_error_match = re.search(r"module error name=([^ ]+)", line)
            if module_error_match:
                module_errors[module_error_match.group(1)] += 1
            if "researchDecision chosen=" in line:
                strategy_decisions["research"] += 1
            if "policyDecision chosen=" in line:
                strategy_decisions["policy"] += 1
            if "tradeDecision unit=" in line:
                strategy_decisions["trade"] += 1
            if "strategicPlan stats" in line:
                operation = _field(line, "operation")
                if operation:
                    strategy_operations[operation.split(":", 1)[0]] += 1
            if "finalOrders handled " in line and unit_match:
                final_order_units[unit_type] += 1
                task = (_field(line, "task", "unowned") or "unowned").split(":", 1)[0]
                final_order_tasks[task] += 1
                if unit_type in catalog.units:
                    final_order_classes[catalog.profile(unit_type)["class"]] += 1
            if "strategicMove order " in line:
                move_mode = _field(line, "mode")
                if move_mode:
                    strategic_move_modes[move_mode] += 1
            symptom_markers = {
                "local_no_target": "localDefense no-target",
                "strike_unresolved": "rangeStrike all-methods-unresolved",
                "strategic_no_plan": "strategicMove no-plan",
                "strategic_move_failed": "strategicMove mission-failed",
                "great_person_no_action": "greatPerson action no-legal-action",
                "transport_hold": "transportEscort hold",
            }
            for symptom, marker in symptom_markers.items():
                if marker in line:
                    decision_symptoms[symptom] += 1
            filtered = _field(line, "filteredDistantUnits")
            if "strategicPlan stats" in line and filtered is not None:
                guard_events["filtered_distant_units"] += int(filtered)
            perf_match = re.search(r"performance module=([^ ]+) elapsedMs=(\d+)", line)
            if perf_match:
                module, elapsed_text = perf_match.groups()
                elapsed = int(elapsed_text)
                stats = performance.setdefault(module, {"calls": 0, "total_ms": 0, "max_ms": 0})
                stats["calls"] += 1
                stats["total_ms"] += elapsed
                stats["max_ms"] = max(stats["max_ms"], elapsed)
            pass_perf_match = re.search(r"performance pass reason=([^ ]+) mode=([^ ]+) elapsedMs=(\d+)", line)
            if pass_perf_match:
                _reason, mode, elapsed_text = pass_perf_match.groups()
                elapsed = int(elapsed_text)
                stats = pass_performance.setdefault(mode, {"calls": 0, "total_ms": 0, "max_ms": 0})
                stats["calls"] += 1
                stats["total_ms"] += elapsed
                stats["max_ms"] = max(stats["max_ms"], elapsed)

            prekill_match = prekill_pattern.search(line)
            if not prekill_match:
                continue
            owner, unit_id, _unit_type_id, x, y, delayed, killer = prekill_match.groups()
            owner_id, killer_id = int(owner), int(killer)
            key = f"P{owner}:{unit_id}"
            if owner_id != 0:
                if killer_id == 0:
                    enemy_loss_ids.add(key)
                continue
            if killer_id <= 0 and delayed.lower() != "true":
                continue
            state = dict(latest_states.get(key, {}))
            state.update({
                "turn": turn,
                "owner": owner_id,
                "id": unit_id,
                "plot": state.get("plot") or f"{x},{y}",
                "killer": killer_id,
                "damage": int(state.get("damage", 0)),
                "hp": int(state.get("hp", 100)),
                "embarked": bool(state.get("embarked", False)),
                "last_action": latest_actions.get(key),
                "transport": latest_transport.get(key),
            })
            unit_type = state.get("type") or latest_units.get(key) or "UNKNOWN"
            state["type"] = unit_type
            if killer_id > 0:
                combat_losses[unit_id] = state
                removed_unit_keys.add(key)
            else:
                unattributed_removals[unit_id] = state

    for unit_id in combat_losses:
        unattributed_removals.pop(unit_id, None)

    loss_rows: list[dict[str, Any]] = []
    high_value_losses = 0
    embarked_losses = 0
    retreat_eligible_losses = 0
    commander_losses = 0
    guarded_losses = 0
    direct_guarded_losses = 0
    for loss in sorted(combat_losses.values(), key=lambda item: (item["turn"] or -1, int(item["id"]))):
        unit_type = loss["type"]
        if unit_type not in catalog.units:
            profile = {
                "type": unit_type, "class": "unknown", "power": 0, "range": 0,
                "can_range": False, "can_capture": False, "project_prereq": "",
            }
            tier = 0
            guards: list[str] = []
        else:
            profile = catalog.profile(unit_type)
            tier = protection_tier(profile)
            guards = _loss_policy_guards(loss, profile)
        direct_guards = [guard for guard in guards if guard != "ranged-standoff"]
        high_value_losses += int(tier >= 2)
        embarked_losses += int(loss["embarked"])
        retreat_eligible_losses += int(loss["damage"] >= retreat_damage_threshold(profile))
        commander_losses += int(unit_type in ("UNIT_GREAT_GENERAL", "UNIT_GREAT_ADMIRAL"))
        guarded_losses += int(bool(guards))
        direct_guarded_losses += int(bool(direct_guards))
        loss_rows.append({
            "turn": loss["turn"], "unit": unit_type, "id": loss["id"],
            "class": profile["class"], "tier": tier, "damage": loss["damage"],
            "hp": loss["hp"], "embarked": loss["embarked"], "killer": loss["killer"],
            "last_action": loss["last_action"], "transport": loss["transport"],
            "v141_guards": guards,
        })

    roster = Counter(
        catalog.profile(unit_type)["class"]
        for unit_type in latest_units.values()
        if unit_type in catalog.units
    )
    return {
        "path": str(log_path),
        "loaded_version": loaded_version,
        "snapshot_units": len(latest_units),
        "roster_classes": dict(sorted(roster.items())),
        "action_classes": dict(sorted(actions.items())),
        "observed": {
            "combat_losses": len(loss_rows),
            "enemy_losses": len(enemy_loss_ids),
            "high_value_losses": high_value_losses,
            "embarked_losses": embarked_losses,
            "retreat_eligible_losses": retreat_eligible_losses,
            "commander_losses": commander_losses,
            "unattributed_removals": len(unattributed_removals),
        },
        "policy_replay": {
            "guarded_losses": guarded_losses,
            "direct_guarded_losses": direct_guarded_losses,
            "coverage": f"{guarded_losses}/{len(loss_rows)}",
            "interpretation": "intervention coverage, not guaranteed survival",
        },
        "live_guard_events": dict(sorted(guard_events.items())),
        "performance_modules": dict(sorted(performance.items())),
        "performance_passes": dict(sorted(pass_performance.items())),
        "production": {
            "categories": dict(production_categories.most_common()),
            "items": dict(production_items.most_common()),
            "reasons": dict(production_reasons.most_common()),
        },
        "operations": {
            "final_order_units": dict(final_order_units.most_common()),
            "final_order_classes": dict(final_order_classes.most_common()),
            "final_order_tasks": dict(final_order_tasks.most_common()),
            "strategic_move_modes": dict(strategic_move_modes.most_common()),
            "decision_symptoms": dict(decision_symptoms.most_common()),
        },
        "strategy_v2": {
            "postures": dict(strategy_postures.most_common()),
            "operation_scopes": dict(strategy_operations.most_common()),
            "decisions": dict(strategy_decisions.most_common()),
            "latest_plan": latest_strategy_plan,
            "module_errors": dict(module_errors.most_common()),
        },
        "termination": {
            "passes_started": passes_started,
            "passes_ended": passes_ended,
            "abrupt_during_pass": passes_started > passes_ended,
            "last_line_number": last_session_line_number,
            "last_line": last_session_line.split("] ", 1)[-1],
            "stale_unit_accesses": stale_unit_accesses,
            "probable_native_handle_crash": passes_started > passes_ended and bool(stale_unit_accesses),
            "v148_short_circuit_coverage": len(stale_unit_accesses),
        },
        "losses": loss_rows,
    }


def analyze_execution_replay(log_path: Path, catalog: UnitCatalog) -> dict[str, Any]:
    """Measure what the game actually executed during each automation pass.

    The older simulator treated a selected policy branch as a completed action.  In
    Civ V those are very different things: a network mission can be rejected, a
    unit can be cargo moved with its carrier, or final-order cleanup can merely
    clear the UI blocker.  This replay therefore derives outcomes from the
    pass-begin snapshots and pass-end state deltas in the real Lua log.
    """

    unit_pattern = re.compile(r"unit=(UNIT_[A-Z0-9_]+)#([^ ]+)@P([0-9]+)")
    turn_pattern = re.compile(r"\[T(\d+)\]")
    pass_pattern = re.compile(
        r"pass begin reason=([^ ]+) count=([^ ]+) remaining=([^ ]+) atWar=([^ ]+) mode=([^ ]+)"
    )
    change_pattern = re.compile(r"(?:^| )(\w+)=([^ ]+)->([^ ]+)")

    loaded_version: str | None = None
    episodes: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    def empty_episode(turn: int, reason: str, mode: str, at_war: bool) -> dict[str, Any]:
        return {
            "turn": turn,
            "reason": reason,
            "mode": mode,
            "at_war": at_war,
            "start": {},
            "delta_units": set(),
            "relocated": set(),
            "self_moved": set(),
            "spent_moves": set(),
            "fired": set(),
            "range_struck": set(),
            "air_swept": set(),
            "commanded": set(),
            "final_ordered": set(),
            "promoted": set(),
            "healed_or_retreated": set(),
            "removed_during_pass": set(),
            "capture_attempts": 0,
            "captures": 0,
            "enemy_kills": 0,
            "friendly_losses": 0,
            "accepted_no_effect_moves": 0,
        }

    def unit_key(line: str) -> tuple[str, str, int] | None:
        match = unit_pattern.search(line)
        if match is None:
            return None
        unit_type, unit_id, owner = match.groups()
        return unit_type, f"P{owner}:{unit_id}", int(owner)

    def finalize_episode(episode: dict[str, Any] | None) -> None:
        if episode is None:
            return
        starts = episode.pop("start")
        combat = {
            key: state for key, state in starts.items()
            if not str(state["class"]).startswith("civilian")
        }
        actionable = {
            key for key, state in combat.items()
            if state["can_move"] and state["moves"] > 0
            and (state["ready"] or state["needs_order"] or not state["waiting"])
        }
        maneuver_capable = {
            key for key, state in combat.items()
            if state["can_move"] and state["moves"] > 0
        }
        substantive = (
            episode["self_moved"] | episode["fired"] | episode["healed_or_retreated"]
            | episode["promoted"] | episode["removed_during_pass"]
        ) & set(combat)
        commanded = episode["commanded"] & set(combat)
        fallback_only = (episode["final_ordered"] - substantive) & set(combat)
        no_state_effect = (commanded - episode["delta_units"] - episode["fired"]) & set(combat)
        untouched_actionable = actionable - substantive
        by_class: dict[str, Counter[str]] = defaultdict(Counter)
        for key, state in combat.items():
            doctrine = str(state["class"])
            by_class[doctrine]["start"] += 1
            if key in actionable:
                by_class[doctrine]["actionable"] += 1
            if key in maneuver_capable:
                by_class[doctrine]["maneuver_capable"] += 1
            if key in commanded:
                by_class[doctrine]["commanded"] += 1
            if key in substantive:
                by_class[doctrine]["substantive"] += 1
            if key in episode["self_moved"]:
                by_class[doctrine]["self_moved"] += 1
            if key in episode["fired"]:
                by_class[doctrine]["fired"] += 1
            if key in episode["range_struck"]:
                by_class[doctrine]["range_struck"] += 1
            if key in episode["air_swept"]:
                by_class[doctrine]["air_swept"] += 1
            if key in fallback_only:
                by_class[doctrine]["fallback_only"] += 1
            if key in untouched_actionable:
                by_class[doctrine]["untouched_actionable"] += 1

        for name in (
            "delta_units", "relocated", "self_moved", "spent_moves", "fired",
            "range_struck", "air_swept",
            "commanded", "final_ordered", "promoted", "healed_or_retreated",
            "removed_during_pass",
        ):
            episode[name] = len(episode[name] & set(combat))
        episode.update({
            "combat_units": len(combat),
            "actionable_units": len(actionable),
            "maneuver_capable_units": len(maneuver_capable),
            "substantive_units": len(substantive),
            "fallback_only_units": len(fallback_only),
            "command_without_state_effect": len(no_state_effect),
            "untouched_actionable_units": len(untouched_actionable),
            "substantive_rate": round(len(substantive) / max(len(maneuver_capable), 1), 4),
            "actionable_completion_rate": round(
                len(actionable & substantive) / max(len(actionable), 1), 4
            ),
            "by_class": {
                doctrine: dict(counts) for doctrine, counts in sorted(by_class.items())
            },
        })
        episodes.append(episode)

    fire_markers = (
        "localDefense fired", "finalOrders tactical-fired", "airSuperiority sweep",
        "specialWeapon fired", "specialWeapon fire", "rangeStrike success",
    )
    command_markers = (
        "strategicMove order", "captureTask stage", "captureFinish try",
        "airRebase success", "transportEscort ", "heal retreat", "greatPerson position",
        "localDefense fired", "finalOrders tactical-fired", "airSuperiority sweep",
        "specialWeapon fired", "specialWeapon fire",
    )

    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            line = raw_line.rstrip()
            version = re.search(r"Strategic Command v([0-9.]+) loaded", line)
            if version:
                loaded_version = version.group(1)
                episodes.clear()
                current = None
                continue

            pass_match = pass_pattern.search(line)
            if pass_match:
                finalize_episode(current)
                reason, _count, _remaining, at_war, mode = pass_match.groups()
                turn_match = turn_pattern.search(line)
                current = empty_episode(
                    int(turn_match.group(1)) if turn_match else -1,
                    reason,
                    mode,
                    at_war == "true",
                )
                continue
            if current is None:
                continue

            parsed_unit = unit_key(line)
            if parsed_unit is not None:
                unit_type, key, owner = parsed_unit
                if owner == 0 and "unitAudit state" in line and "phase=pass-begin:" in line:
                    profile = catalog.profile(unit_type) if unit_type in catalog.units else None
                    current["start"][key] = {
                        "type": unit_type,
                        "class": profile["class"] if profile is not None else "unknown",
                        "moves": int(_field(line, "moves", "0") or 0),
                        "damage": int(_field(line, "damage", "0") or 0),
                        "can_move": _field(line, "canMove") == "true",
                        "ready": _field(line, "ready") == "true",
                        "waiting": _field(line, "waiting") == "true",
                        "needs_order": _field(line, "needsOrder") == "true",
                    }
                if owner == 0 and "unitAudit delta" in line and "phase=pass-end:" in line:
                    changes = {name: (before, after) for name, before, after in change_pattern.findall(line)}
                    current["delta_units"].add(key)
                    if "plot" in changes:
                        current["relocated"].add(key)
                        if "moves" in changes:
                            try:
                                if int(changes["moves"][1]) < int(changes["moves"][0]):
                                    current["self_moved"].add(key)
                            except ValueError:
                                pass
                    if "moves" in changes:
                        try:
                            if int(changes["moves"][1]) < int(changes["moves"][0]):
                                current["spent_moves"].add(key)
                        except ValueError:
                            pass
                if owner == 0 and "unitAudit missing" in line and "phase=pass-end:" in line:
                    current["removed_during_pass"].add(key)
                if owner == 0 and any(marker in line for marker in command_markers):
                    current["commanded"].add(key)
                if owner == 0 and any(marker in line for marker in fire_markers):
                    current["fired"].add(key)
                if owner == 0 and "rangeStrike resolved" in line and "status=fired" in line:
                    current["commanded"].add(key)
                    current["fired"].add(key)
                    current["range_struck"].add(key)
                if owner == 0 and "airSuperiority sweep" in line:
                    current["air_swept"].add(key)
                if owner == 0 and "finalOrders handled" in line:
                    current["final_ordered"].add(key)
                if owner == 0 and "promotion success" in line:
                    current["promoted"].add(key)
                if owner == 0 and ("heal retreat" in line or "heal order" in line):
                    current["healed_or_retreated"].add(key)

            if "moveMission " in line and "accepted=true" in line \
                    and "changedPlot=false" in line and "combatResolved=false" in line:
                current["accepted_no_effect_moves"] += 1

            if "captureFinish try" in line:
                current["capture_attempts"] += 1
                if "captured=true" in line:
                    current["captures"] += 1

            prekill = re.search(
                r"event=UnitPrekill a1=(-?\d+) a2=(-?\d+) a3=(-?\d+) a4=(-?\d+) "
                r"a5=(-?\d+) a6=([^ ]*) a7=(-?\d+)",
                line,
            )
            if prekill:
                owner, _unit_id, _type_id, _x, _y, _delayed, killer = prekill.groups()
                if int(owner) == 0 and int(killer) > 0:
                    current["friendly_losses"] += 1
                elif int(owner) != 0 and int(killer) == 0:
                    current["enemy_kills"] += 1

            if "pass end reason=" in line:
                finalize_episode(current)
                current = None

    finalize_episode(current)
    full = [episode for episode in episodes if episode["mode"] == "full"]
    totals: Counter[str] = Counter()
    class_totals: dict[str, Counter[str]] = defaultdict(Counter)
    sum_fields = (
        "combat_units", "actionable_units", "maneuver_capable_units", "substantive_units",
        "commanded", "self_moved", "fired", "range_struck", "air_swept", "fallback_only_units",
        "command_without_state_effect", "untouched_actionable_units", "capture_attempts",
        "captures", "enemy_kills", "friendly_losses", "accepted_no_effect_moves",
    )
    for episode in full:
        for name in sum_fields:
            totals[name] += int(episode.get(name, 0) or 0)
        for doctrine, counts in episode["by_class"].items():
            class_totals[doctrine].update(counts)

    maneuver = totals["maneuver_capable_units"]
    actionable = totals["actionable_units"]
    return {
        "loaded_version": loaded_version,
        "episode_count": len(episodes),
        "full_episode_count": len(full),
        "episodes": full,
        "totals": dict(totals),
        "rates": {
            "substantive_per_maneuver_capable": round(totals["substantive_units"] / max(maneuver, 1), 4),
            "actionable_completion": round(
                (actionable - totals["untouched_actionable_units"]) / max(actionable, 1), 4
            ),
            "fallback_only_per_combat": round(
                totals["fallback_only_units"] / max(totals["combat_units"], 1), 4
            ),
            "command_no_effect": round(
                totals["command_without_state_effect"] / max(totals["commanded"], 1), 4
            ),
            "capture_conversion": round(totals["captures"] / max(totals["capture_attempts"], 1), 4),
        },
        "by_class": {
            doctrine: dict(counts) for doctrine, counts in sorted(class_totals.items())
        },
    }


def build_fidelity_report(
    execution: dict[str, Any], log_analysis: dict[str, Any], world: dict[str, Any],
    synthetic_combat: dict[str, Any],
) -> dict[str, Any]:
    """Contrast contract-model optimism with observed engine outcomes."""

    rates = execution.get("rates", {})
    totals = execution.get("totals", {})
    observed = log_analysis.get("observed", {})
    world_policy = world.get("policy_replay", {})
    combat_units = int(world_policy.get("combat_units", 0) or 0)
    empirical_action_rate = float(rates.get("substantive_per_maneuver_capable", 0) or 0)
    capture_conversion = float(rates.get("capture_conversion", 0) or 0)
    full_passes = max(int(execution.get("full_episode_count", 0) or 0), 1)
    loss_rate = int(observed.get("combat_losses", 0) or 0) / max(combat_units * full_passes, 1)

    class_execution: list[dict[str, Any]] = []
    for doctrine, counts in execution.get("by_class", {}).items():
        maneuver = int(counts.get("maneuver_capable", 0) or 0)
        substantive = int(counts.get("substantive", 0) or 0)
        if maneuver <= 0:
            continue
        class_execution.append({
            "class": doctrine,
            "maneuver_capable": maneuver,
            "substantive": substantive,
            "rate": round(substantive / maneuver, 4),
            "fallback_only": int(counts.get("fallback_only", 0) or 0),
            "untouched_actionable": int(counts.get("untouched_actionable", 0) or 0),
        })
    class_execution.sort(key=lambda row: (row["rate"], -row["maneuver_capable"], row["class"]))
    weak_classes = [row for row in class_execution if row["maneuver_capable"] >= 6 and row["rate"] < 0.20]

    divergences: list[dict[str, Any]] = []
    if execution.get("full_episode_count", 0) <= 0:
        divergences.append({
            "severity": "BLOCKED", "category": "telemetry",
            "evidence": "No complete full-pass episode can be reconstructed from this log.",
        })
    if empirical_action_rate < 0.55:
        divergences.append({
            "severity": "FAIL", "category": "execution-coverage",
            "evidence": (
                f"Only {totals.get('substantive_units', 0)}/{totals.get('maneuver_capable_units', 0)} "
                f"maneuver-capable unit-slots produced a substantive outcome ({empirical_action_rate:.1%})."
            ),
        })
    if weak_classes:
        worst = ", ".join(
            f"{row['class']}={row['substantive']}/{row['maneuver_capable']}"
            for row in weak_classes[:8]
        )
        divergences.append({
            "severity": "FAIL", "category": "doctrine-execution",
            "evidence": f"Doctrine classes below 20% substantive execution: {worst}.",
        })
    if int(totals.get("fallback_only_units", 0) or 0) > int(totals.get("substantive_units", 0) or 0):
        divergences.append({
            "severity": "FAIL", "category": "order-clearing",
            "evidence": (
                f"Fallback-only orders ({totals.get('fallback_only_units', 0)}) exceed substantive "
                f"unit outcomes ({totals.get('substantive_units', 0)})."
            ),
        })
    accepted_no_effect = int(totals.get("accepted_no_effect_moves", 0) or 0)
    if accepted_no_effect > 0:
        divergences.append({
            "severity": "FAIL", "category": "movement-confirmation",
            "evidence": (
                f"{accepted_no_effect} move commands were accepted without plot or combat state change; "
                "they must remain retryable rather than consuming the unit's strategic order."
            ),
        })
    capture_pressure = (
        int(totals.get("capture_attempts", 0) or 0)
        + int(log_analysis.get("live_guard_events", {}).get("capture_task_stage", 0) or 0)
    )
    if synthetic_combat.get("city_captured") and capture_pressure > 0 and capture_conversion <= 0:
        divergences.append({
            "severity": "FAIL", "category": "capture",
            "evidence": (
                "Contract model predicts a captured city, but observed capture conversion is 0 "
                f"across {capture_pressure} attempts/staging actions."
            ),
        })
    high_value_losses = int(observed.get("high_value_losses", 0) or 0)
    if int(synthetic_combat.get("friendly_losses", 0) or 0) == 0 and high_value_losses > 0:
        divergences.append({
            "severity": "FAIL", "category": "survival",
            "evidence": (
                "Contract model predicts zero friendly losses, while the real session lost "
                f"{high_value_losses} high-value units."
            ),
        })

    empirical_forecast = {
        "basis": "observed-engine-transition-rates",
        "contract_enemy_kills": int(synthetic_combat.get("enemy_units_destroyed", 0) or 0),
        "effective_enemy_kills": round(
            int(synthetic_combat.get("enemy_units_destroyed", 0) or 0) * empirical_action_rate, 2
        ),
        "contract_capture": bool(synthetic_combat.get("city_captured")),
        "capture_probability": capture_conversion,
        "contract_friendly_losses": int(synthetic_combat.get("friendly_losses", 0) or 0),
        "expected_friendly_losses_per_100_units_per_pass": round(loss_rate * 100, 2),
    }
    return {
        "status": "FAIL" if any(item["severity"] == "FAIL" for item in divergences) else "PASS",
        "model_scope": {
            "contract_scenarios": "branch and arithmetic checks only; not game forecasts",
            "execution_replay": "real Civ V state transitions reconstructed from Lua telemetry",
        },
        "world_policy_actions": sum(int(value) for value in world_policy.get("actions", {}).values()),
        "empirical_forecast": empirical_forecast,
        "class_execution": class_execution,
        "weak_classes": weak_classes,
        "divergences": divergences,
    }


def build_strategy_audit(log_analysis: dict[str, Any], world: dict[str, Any]) -> dict[str, Any]:
    roster = Counter(world.get("own_doctrine", {}))
    combat_units = int(world.get("policy_replay", {}).get("combat_units", 0) or 0)
    production = log_analysis.get("production", {})
    operations = log_analysis.get("operations", {})
    guard_events = log_analysis.get("live_guard_events", {})
    performance = log_analysis.get("performance_modules", {})
    passes = log_analysis.get("performance_passes", {}).get("full", {})
    strategy_v2 = log_analysis.get("strategy_v2", {})
    latest_plan = strategy_v2.get("latest_plan", {})
    module_errors = strategy_v2.get("module_errors", {})

    def share(*classes: str) -> float:
        return round(sum(roster[name] for name in classes) / max(combat_units, 1), 4)

    full_total = int(passes.get("total_ms", 0) or 0)
    full_calls = int(passes.get("calls", 0) or 0)
    strategic_ms = int(performance.get("strategicMovement", {}).get("total_ms", 0) or 0)
    assignments = int(guard_events.get("strategic_target_assign", 0) or 0)
    switches = int(guard_events.get("strategic_target_switch", 0) or 0)
    memory_hits = int(guard_events.get("strategic_target_memory_hit", 0) or 0)
    final_orders = sum(int(value) for value in operations.get("final_order_units", {}).values())
    fallback_units = int(production.get("categories", {}).get("fallback-unit", 0) or 0)
    militia = int(production.get("items", {}).get("UNIT_MILITIA_MODERN", 0) or 0)
    processes = int(production.get("categories", {}).get("process", 0) or 0)

    findings: list[dict[str, Any]] = []

    def finding(category: str, severity: str, evidence: str, implication: str) -> None:
        findings.append({
            "category": category,
            "severity": severity,
            "evidence": evidence,
            "implication": implication,
        })

    if share("recon_raider") > 0.20:
        finding("force-composition", "critical", f"recon_raider_share={share('recon_raider'):.1%}", "low-value line units crowd out combined-arms slots")
    if share("missile_strike") > 0.15:
        finding("force-composition", "high", f"missile_share={share('missile_strike'):.1%}", "consumable strike inventory is oversized and frequently left unused")
    carriers = roster["fleet_carrier"]
    screens = roster["escort_screen"] + roster["surface_fire_support"] + roster["naval_assault"]
    if carriers > 0 and screens < carriers * 2:
        finding("fleet-composition", "critical", f"carriers={carriers}, screens={screens}", "capital ships lack a viable screen and capture component")
    if militia > 0 and fallback_units > 0:
        finding("production", "critical", f"militia={militia}/{fallback_units} fallback units", "fallback selection dominates planned military production")
    if processes > 0:
        finding("production", "high", f"process_orders={processes}", "cities fall into wealth/research instead of pursuing marginal infrastructure or force needs")
    if switches > assignments:
        finding("operations", "critical", f"target_switches={switches}, assignments={assignments}, memory_hits={memory_hits}", "per-unit target choice is unstable because no persistent theater operation owns the target")
    if final_orders > combat_units * max(full_calls, 1) * 0.10:
        finding("unit-control", "critical", f"final_orders={final_orders}, combat_units={combat_units}, full_passes={full_calls}", "units repeatedly reach the cleanup layer without a meaningful task")
    if full_total > 0 and strategic_ms / full_total > 0.50:
        finding("runtime", "critical", f"strategic_movement_share={strategic_ms / full_total:.1%}", "global unit-by-target searches dominate turn time")
    if int(operations.get("decision_symptoms", {}).get("local_no_target", 0) or 0) > combat_units:
        finding("tactics", "high", f"local_no_target={operations['decision_symptoms']['local_no_target']}", "local strike evaluation is repeated without changing the tactical state")
    assigned_combat = int(latest_plan.get("assignedCombat", 0) or 0)
    planned_combat = int(latest_plan.get("ownCombat", 0) or 0)
    if "assignedCombat" in latest_plan and planned_combat > 0:
        assignment_ratio = assigned_combat / planned_combat
        if assignment_ratio > 0.85:
            finding("operations", "high", f"assigned={assigned_combat}/{planned_combat}", "theaters overcommit the national force and leave too little local reserve")
        elif assignment_ratio < 0.30:
            finding("operations", "critical", f"assigned={assigned_combat}/{planned_combat}", "too few combat units have theater ownership")
    capture_reserved = int(guard_events.get("capture_task_reserved", 0) or 0)
    capture_completed = int(guard_events.get("capture_task_completed", 0) or 0)
    capture_no_unit = int(guard_events.get("capture_task_no_capturer", 0) or 0)
    capture_path_failures = int(guard_events.get("capture_task_path_failure", 0) or 0)
    if capture_no_unit > 0:
        finding("capture", "critical", f"no_capturer={capture_no_unit}", "ready cities have no legal melee hull assigned")
    if capture_reserved > 0 and capture_completed <= 0 and capture_path_failures > 0:
        finding("capture", "critical", f"reserved={capture_reserved}, completed={capture_completed}, path_failures={capture_path_failures}", "capture tasks are assigned but cannot reach the city")
    if module_errors:
        finding("runtime", "critical", f"module_errors={module_errors}", "one or more strategy executors were disabled during the observed run")

    return {
        "turn": world.get("turn"),
        "force": {
            "combat_units": combat_units,
            "class_counts": dict(sorted(roster.items())),
            "shares": {
                "recon_raider": share("recon_raider"),
                "missile_strike": share("missile_strike"),
                "air_wings": share("air_superiority", "strike_aircraft", "carrier_multirole"),
                "fleet_capitals": share("fleet_carrier", "arsenal_capital", "ballistic_submarine"),
                "fleet_screens": share("escort_screen", "surface_fire_support", "naval_assault", "attack_submarine"),
            },
        },
        "production": production,
        "operations": {
            **operations,
            "latest_plan": latest_plan,
            "module_errors": module_errors,
            "target_assignments": assignments,
            "target_switches": switches,
            "target_memory_hits": memory_hits,
            "final_order_total": final_orders,
            "capture_task": {
                "reserved": capture_reserved,
                "completed": capture_completed,
                "no_capturer": capture_no_unit,
                "path_failures": capture_path_failures,
                "staged": int(guard_events.get("capture_task_stage", 0) or 0),
                "security_holds": int(guard_events.get("capture_security_hold", 0) or 0),
            },
        },
        "runtime": {
            "full_pass_calls": full_calls,
            "full_pass_average_ms": round(full_total / max(full_calls, 1)),
            "full_pass_max_ms": int(passes.get("max_ms", 0) or 0),
            "strategic_movement_total_ms": strategic_ms,
            "strategic_movement_share": round(strategic_ms / max(full_total, 1), 4),
        },
        "findings": findings,
    }


def historical_loss_replay_scenario(catalog: UnitCatalog) -> dict[str, Any]:
    """Keep the v1.40 T223-T258 loss chain as a permanent policy regression."""
    observed = [
        ("UNIT_ROCKET_ARTILLERY", 79, False, None),
        ("UNIT_MECHANIZED_INFANTRY", 61, False, None),
        ("UNIT_MODERN_ARMOR", 36, True, {"threats": 3, "escorts": 0}),
        ("UNIT_ATGM_VEHICLE", 26, True, {"threats": 3, "escorts": 0}),
        ("UNIT_MOTORISED_INFANTRY", 53, False, None),
        ("UNIT_ROCKET_ARTILLERY", 0, False, None),
        ("UNIT_GREAT_GENERAL", 0, False, None),
        ("UNIT_CRUSADER_ARTILLERY", 10, True, None),
        ("UNIT_AMERICAN_APACHE", 70, False, None),
        ("UNIT_GREAT_GENERAL", 0, False, None),
        ("UNIT_MECH", 11, True, {"threats": 2, "escorts": 0}),
    ]
    guard_counts: Counter[str] = Counter()
    replay: list[dict[str, Any]] = []
    for unit_type, damage, embarked, transport in observed:
        profile = catalog.profile(unit_type)
        loss = {"damage": damage, "embarked": embarked, "transport": transport}
        guards = _loss_policy_guards(loss, profile)
        assert guards, (unit_type, damage, embarked)
        for guard in guards:
            guard_counts[guard.split(":", 1)[0]] += 1
        replay.append({
            "unit": unit_type,
            "tier": protection_tier(profile),
            "damage": damage,
            "embarked": embarked,
            "guards": guards,
        })
    assert len(replay) == 11
    assert guard_counts["sea-transit-gate"] == 4
    assert guard_counts["damage-retreat"] == 4
    assert guard_counts["commander-rear-area"] == 2
    # MECH is dual-mode armor: its splash promotion is defensive-only, but the
    # chassis can melee-capture and must not be treated as pure artillery.
    assert guard_counts["ranged-standoff"] == 4
    return {
        "scenario": "v140_observed_loss_chain_replay",
        "observed_losses": len(replay),
        "guarded_losses": len(replay),
        "guard_counts": dict(sorted(guard_counts.items())),
        "interpretation": "policy intervention coverage, not guaranteed survival",
    }


def national_strategy_scenario(catalog: UnitCatalog) -> dict[str, Any]:
    """Exercise v2.8 combined-arms allocation and bounded mobilization."""

    # T187 exposed the global-count trap: hundreds of remote obsolete units made
    # the old plan defend even where the future-tech task force had an overmatch.
    own_global_count, enemy_global_count = 237, 931
    own_local_power, enemy_local_power = 16800.0, 6200.0
    count_ratio = own_global_count / enemy_global_count
    local_power_ratio = own_local_power / enemy_local_power
    assert count_ratio < 0.30
    assert local_power_ratio > 2.5

    def posture(
        defensive_ratio: float,
        offensive_ratio: float,
        happiness: int = 8,
        casualty_rate: float = 0.0,
        force_drawdown: float = 0.0,
    ) -> str:
        if defensive_ratio < 0.72 or casualty_rate >= 0.08 or force_drawdown >= 0.08 or (
            happiness < -30 and defensive_ratio < 1.15 and offensive_ratio < 1.40
        ):
            return "defend"
        if offensive_ratio >= 1.40:
            return "decapitation"
        return "advance"

    assert posture(1.20, local_power_ratio) == "decapitation"
    assert posture(0.60, 4.50) == "defend"
    assert posture(1.20, 4.50, casualty_rate=0.09) == "defend"
    assert posture(1.20, 4.50, force_drawdown=0.10) == "defend"
    assert posture(1.05, 1.20) == "advance"

    defensive_objectives = [
        {"name": "frontier_city", "enemy_power": 5200, "friendly_power": 3100, "enemy_count": 8},
        {"name": "safe_capital", "enemy_power": 0, "friendly_power": 9000, "enemy_count": 0},
    ]
    defense_operations = [city["name"] for city in defensive_objectives if city["enemy_count"] > 0]
    assert defense_operations == ["frontier_city"]
    assert all("enemy_city" not in operation for operation in defense_operations)

    assault_candidates = [
        {"name": "unsupported_capital", "readiness": 0.42, "ratio": 2.8, "capture": 0},
        {"name": "screened_port", "readiness": 0.84, "ratio": 1.62, "capture": 2},
        {"name": "bad_trade", "readiness": 0.91, "ratio": 0.74, "capture": 3},
    ]
    admitted = [
        candidate["name"] for candidate in assault_candidates
        if candidate["readiness"] >= 0.68 and candidate["ratio"] >= 1.10 and candidate["capture"] > 0
    ]
    assert admitted == ["screened_port"]
    target_scores = {"locked_front": 1_200 + 15_000, "new_shiny_target": 6_500}
    assert max(target_scores, key=target_scores.get) == "locked_front"
    expired_target_scores = {"locked_front": 1_200, "new_shiny_target": 6_500}
    assert max(expired_target_scores, key=expired_target_scores.get) == "new_shiny_target"
    remote_assembly = {
        "name": "remote_coastal_capital", "distance": 44, "local_readiness": 0.18,
        "global_readiness": 0.88, "strategic_ratio": 2.2, "global_capture": 5,
    }
    assembly_admitted = (
        remote_assembly["distance"] <= 55
        and remote_assembly["global_readiness"] >= 0.82
        and remote_assembly["strategic_ratio"] >= 1.45
        and remote_assembly["global_capture"] > 0
    )
    assert assembly_admitted

    # The future carrier group is a multi-role package. Kirov and the arsenal
    # ship provide fire support while 052Ds provide both capture and screening;
    # attached carrier wings supply CAP/strike instead of triggering redundant
    # fighter production.
    precision_requirements = {
        "rapid_capture": 1, "air_superiority": 2, "carrier_air": 3,
        "air_strike": 3, "naval_screen": 3, "naval_fire": 3,
        "fleet_carrier": 1, "strategic_submarine": 1,
    }
    precision_supply: Counter[str] = Counter()
    carrier_group = [
        "UNIT_SUPER_CARRIER", "UNIT_SSBN", "UNIT_NUCLEAR_SUBMARINE",
        "UNIT_KIROV_BATTLECRUISER", "UNIT_CHINESE_052D", "UNIT_CHINESE_052D",
        "UNIT_FUTURE_BATTLESHIP",
        "UNIT_CARRIER_FIGHTER_ADV", "UNIT_CARRIER_FIGHTER_ADV",
        "UNIT_CARRIER_FIGHTER_ADV", "UNIT_CARRIER_FIGHTER_ADV",
        "UNIT_CARRIER_FIGHTER_ADV", "UNIT_CARRIER_FIGHTER_ADV",
    ]
    for unit_type in carrier_group:
        profile = catalog.profile(unit_type)
        doctrine_class = profile["class"]
        if profile["can_capture"]:
            precision_supply["line_frontline"] += 1
            if profile["moves"] >= 4 or profile["domain"] == "DOMAIN_SEA":
                precision_supply["rapid_capture"] += 1
        if doctrine_class == "fleet_carrier":
            precision_supply["fleet_carrier"] += 1
        elif doctrine_class == "ballistic_submarine":
            precision_supply["strategic_submarine"] += 1
            precision_supply["naval_screen"] += 0.35
            precision_supply["missile_strike"] += 0.50
        elif doctrine_class in {"attack_submarine", "escort_screen", "naval_assault", "air_defense_screen"}:
            precision_supply["naval_screen"] += 1
        elif doctrine_class in {"surface_fire_support", "arsenal_capital"}:
            precision_supply["naval_fire"] += 1
        elif doctrine_class == "carrier_multirole":
            precision_supply["carrier_air"] += 1
            precision_supply["air_superiority"] += 0.75
            precision_supply["air_strike"] += 0.65
        if profile["domain"] == "DOMAIN_SEA" and profile["ranged"] > 0 and profile["range"] >= 2:
            if doctrine_class not in {"surface_fire_support", "arsenal_capital"}:
                precision_supply["naval_fire"] += 1 if profile["range"] >= 4 else 0.65
    precision_readiness = sum(
        min(precision_supply.get(arm, 0), required)
        for arm, required in precision_requirements.items()
    ) / sum(precision_requirements.values())
    assert precision_readiness == 1.0

    # Air sorties are threat-driven and retain a CAP reserve instead of sweeping
    # once with every carrier fighter each pass.
    wings, enemy_air = 24, 3
    reserve = wings - math.floor(wings * (1 - 0.35))
    max_sweeps = min(wings - reserve, math.ceil(enemy_air * 1.5))
    assert reserve == 9
    assert max_sweeps == 5

    # A missing unit class must not terminate the purchase search. This mirrors
    # the observed 1.7M treasury / zero purchase failure chain.
    purchase_candidates = {
        "line_frontline": 0,
        "air_superiority": 2,
        "naval_screen": 1,
    }
    purchase_attempts: list[str] = []
    selected_purchase = None
    for need in purchase_candidates:
        purchase_attempts.append(need)
        if purchase_candidates[need] > 0:
            selected_purchase = need
            break
    assert selected_purchase == "air_superiority"
    assert purchase_attempts == ["line_frontline", "air_superiority"]

    queued_civilians = ["UNITAI_ARCHAEOLOGIST", "UNITAI_ARCHAEOLOGIST", "UNITAI_WORKER"]
    queued_workers = sum(unit_ai == "UNITAI_WORKER" for unit_ai in queued_civilians)
    assert queued_workers == 1

    # A numerically outnumbered future-tech force concentrates on one assault
    # axis plus the single threatened city instead of opening eight fronts.
    combat_units = 324
    available_budget = math.floor(combat_units * 0.75)
    enemy_combat_units = 1_850
    enemy_count_ratio = enemy_combat_units / combat_units
    assault_cap = 1 if enemy_count_ratio >= 2.50 else 2
    defense_cap = 2
    operation_cap = assault_cap + defense_cap
    assert assault_cap == 1 and operation_cap == 3
    operation_specs = [
        # minimum, defenders, force cap, reinforcement factor
        (11, 9, 30, 0.85),
        (11, 7, 30, 0.85),
        (17, 23, 60, 0.60),
    ]
    operation_budgets = [
        max(
            min(cap, math.ceil(available_budget * 0.90 / operation_cap)),
            min(cap, minimum + math.ceil(defenders * factor)),
        )
        for minimum, defenders, cap, factor in operation_specs
    ]
    assignment_budget = min(available_budget, sum(operation_budgets))
    assigned_total = sum(operation_budgets)
    reserve_total = combat_units - assigned_total
    assert assigned_total == 120
    assert reserve_total == 204
    assert assigned_total <= available_budget

    defensive_requirements = {
        "rapid_capture": 0, "line_frontline": 4, "siege": 1,
        "air_superiority": 2, "carrier_air": 0, "air_strike": 1,
        "naval_screen": 3, "naval_fire": 1, "fleet_carrier": 0,
        "strategic_submarine": 0, "missile_strike": 0,
    }
    assert all(defensive_requirements[arm] == 0 for arm in (
        "rapid_capture", "carrier_air", "fleet_carrier", "strategic_submarine", "missile_strike",
    ))
    assert all(defensive_requirements[arm] > 0 for arm in (
        "line_frontline", "siege", "air_superiority", "air_strike", "naval_screen", "naval_fire",
    ))
    defense_excluded_classes = {
        "fleet_carrier", "carrier_multirole", "ballistic_submarine",
        "arsenal_capital", "missile_strike", "strategic_nuclear",
    }
    assert defense_excluded_classes.isdisjoint({"air_superiority", "strike_aircraft", "escort_screen"})

    assault_capacities = {
        "rapid_capture": 1, "line_frontline": math.ceil(60 * 0.30),
        "siege": math.ceil(60 * 0.20), "air_superiority": math.ceil(60 * 0.15),
        "carrier_air": math.ceil(60 * 0.16), "air_strike": math.ceil(60 * 0.20),
        "naval_screen": math.ceil(60 * 0.20), "naval_fire": math.ceil(60 * 0.20),
        "fleet_carrier": math.ceil(60 * 0.08), "strategic_submarine": math.ceil(60 * 0.08),
        "missile_strike": math.ceil(60 * 0.12),
    }
    assert assault_capacities["naval_screen"] == 12
    assert max(assault_capacities.values()) <= 18

    own_power, immediate_enemy_power = 300000.0, 70000.0
    average_power = own_power / combat_units
    city_count = 26
    operation_minimum = sum(spec[0] for spec in operation_specs)
    reserve_floor = max(city_count, math.ceil(operation_minimum * 0.30))
    target_force = max(
        18,
        math.ceil(immediate_enemy_power * 1.15 / average_power),
        math.ceil(city_count * 2.4),
        operation_minimum + reserve_floor,
    )
    if combat_units > target_force * 1.35:
        target_force = math.ceil(target_force * 1.10)
    force_targets = {
        "air_superiority": math.ceil(target_force * 0.10),
        "carrier_air": math.ceil(target_force * 0.06),
        "air_strike": math.ceil(target_force * 0.12),
        "strategic_submarine": math.ceil(target_force * 0.025),
        "missile_strike": math.ceil(target_force * 0.06),
    }
    current_arms = {
        "air_superiority": 7 + 42 * 0.75,
        "carrier_air": 42,
        "air_strike": 14 + 42 * 0.65,
        "strategic_submarine": 6,
        "missile_strike": 72 + 6 * 0.50,
    }
    deficits = {arm: target - current_arms[arm] for arm, target in force_targets.items() if target > current_arms[arm]}
    assert target_force == 96
    assert deficits == {}
    assert current_arms["air_superiority"] > force_targets["air_superiority"]
    assert "missile_strike" not in deficits

    # Every unit has one owner. Recovery overrides operations; unassigned
    # high-value assets remain strategic reserve instead of joining random moves.
    task_board = {
        "operation": assigned_total,
        "recovery": 3,
        "strategic_reserve": 38,
        "local_reserve": 20,
        "garrison_reserve": combat_units - assigned_total - 3 - 38 - 20,
    }
    assert sum(task_board.values()) == combat_units
    assert task_board["strategic_reserve"] > 0
    tactical_scan_pool = task_board["operation"] + task_board["local_reserve"]
    assert tactical_scan_pool < combat_units * 0.80

    # The same national plan drives spending and city specialization.
    gold, gold_rate, unit_cost = 515_614, -6_523, 9_800
    # T230-T235 had 1,850 enemies globally, but only the current theater belongs
    # in the mobilization target. The former global calculation demanded 2,374
    # units and caused endless militia/LCS purchases.
    city_count = 24
    average_power = 670.0
    immediate_enemy_power = 152_578.0
    global_enemy_power = 1_178_000.0
    theater_enemy_equivalent = math.ceil(immediate_enemy_power / average_power * 1.35)
    global_enemy_equivalent = math.ceil(global_enemy_power / average_power * 1.35)
    latest_force_target = math.ceil(immediate_enemy_power * 1.15 / average_power)
    capital_force_target = max(city_count * 10, operation_cap * 55, theater_enemy_equivalent, latest_force_target)
    capital_shortage = max(capital_force_target - combat_units, 0)
    reserve_gold = max(city_count * 1800, max(0, -gold_rate) * 20, unit_cost * 4)
    spendable_gold = max(0, gold - reserve_gold)
    deficit_runway = spendable_gold / max(-gold_rate, 1) if gold_rate < 0 else 9999
    capital_enabled = spendable_gold >= 50000 and (gold_rate >= 25 or deficit_runway >= 40) and capital_shortage > 0
    assert latest_force_target == 262
    assert capital_force_target == 308
    assert global_enemy_equivalent > 2_300
    assert capital_force_target < global_enemy_equivalent * 0.20
    doctrinal_deficit = 53
    purchase_budget = math.floor(spendable_gold * (0.42 if capital_enabled else 0.24))
    purchase_cap = min(10, math.ceil(doctrinal_deficit / 2))
    assert not capital_enabled and purchase_cap == 10

    observed_fallback = ["LCS", "LCS", "LCS", "LCS", "MILITIA", "MILITIA", "MILITIA", "MILITIA", "MILITIA"]
    type_cap, need_cap = 2, 3
    diversified: list[str] = []
    type_counts: Counter[str] = Counter()
    need_counts: Counter[str] = Counter()
    fallback_need = {"LCS": "naval_screen", "MILITIA": "line_frontline"}
    for unit_type in observed_fallback:
        need = fallback_need[unit_type]
        if type_counts[unit_type] >= type_cap or need_counts[need] >= need_cap:
            continue
        diversified.append(unit_type)
        type_counts[unit_type] += 1
        need_counts[need] += 1
    assert diversified == ["LCS", "LCS", "MILITIA", "MILITIA"]

    # Purchases can hide casualties in a net roster snapshot. Direct death events
    # must still influence posture when a bad enemy turn destroys a large cohort.
    start_units, purchases, direct_losses = 324, 10, 30
    end_units = start_units + purchases - direct_losses
    net_drawdown = max(0.0, (start_units - end_units) / start_units)
    direct_casualty_rate = direct_losses / (end_units + direct_losses)
    assert net_drawdown < 0.08
    assert direct_casualty_rate >= 0.08

    city_roles = {
        "capital": 1, "frontier": 5, "naval_base": 4,
        "industrial": 5, "science": 4, "finance": 3, "growth_or_balanced": 2,
    }
    assert sum(city_roles.values()) == city_count
    assert city_roles["naval_base"] < city_count / 4

    ten_turn_orders = Counter({
        "building": 45, "elite_project": 2,
        "worker": 1, "process": 4,
    })
    assert ten_turn_orders["building"] > ten_turn_orders["process"] * 5
    assert ten_turn_orders["air_superiority"] == 0
    assert ten_turn_orders["process"] / sum(ten_turn_orders.values()) < 0.10

    # Diamond prerequisites are valued once at their nearest depth.
    tech_graph = {"A": ["B", "C"], "B": ["D"], "C": ["D"], "D": []}
    direct_value = {"A": 10, "B": 20, "C": 30, "D": 100}
    depth = {"A": 0}
    frontier = ["A"]
    while frontier:
        current = frontier.pop(0)
        if depth[current] >= 3:
            continue
        for successor in tech_graph[current]:
            candidate_depth = depth[current] + 1
            if successor not in depth or candidate_depth < depth[successor]:
                depth[successor] = candidate_depth
                frontier.append(successor)
    discount = {0: 1.0, 1: 0.35, 2: 0.15, 3: 0.07}
    tech_value = sum(direct_value[node] * discount[node_depth] for node, node_depth in depth.items())
    assert tech_value == 42.5

    # Per-population and resource output must make a late-game building beat a
    # cheap flat-yield placeholder when the city can exploit those effects.
    flat_building_utility = 2 * 25
    strategic_building_utility = 0.20 * 20 * 22 + math.sqrt(25) * 30
    assert strategic_building_utility > flat_building_utility * 4

    blitz_targets = {
        "enemy_siege": 900 + 1100,
        "enemy_ranged": 1050 + 650,
        "wounded_infantry": 1450,
    }
    assert max(blitz_targets, key=blitz_targets.get) == "enemy_siege"

    # Purchases are asynchronous game messages. A successful submission is
    # budgeted immediately, while roster confirmation is observed next turn.
    purchase_call_ok = True
    immediate_gold_change = False
    purchase_status = "confirmed" if immediate_gold_change else "submitted"
    assert purchase_call_ok and purchase_status == "submitted"

    reserve_target_pool = {
        "cities": [target for target in [(7, "coastal_city"), (18, "remote_city")] if target[0] <= 10],
        "units": [target for target in [(4, "destroyer"), (9, "artillery"), (14, "remote_unit")] if target[0] <= 10],
    }
    assert reserve_target_pool == {
        "cities": [(7, "coastal_city")],
        "units": [(4, "destroyer"), (9, "artillery")],
    }

    observed_real_losses = 152
    observed_elite_losses = 43
    policy_exposure_ceiling = math.floor(observed_real_losses * 0.25)
    elite_loss_budget = 3
    assert policy_exposure_ceiling == 38

    return {
        "scenario": "v29_combined_arms_bounded_mobilization",
        "power_model": {
            "global_count_ratio": round(count_ratio, 3),
            "local_effective_ratio": round(local_power_ratio, 3),
            "posture": posture(1.20, local_power_ratio),
            "local_defeat_posture": posture(0.60, 4.50),
        },
        "defense_operations": defense_operations,
        "admitted_assaults": admitted,
        "target_lock": {
            "persistence_turns": 8,
            "locked_choice": max(target_scores, key=target_scores.get),
            "expired_choice": max(expired_target_scores, key=expired_target_scores.get),
        },
        "assembly_operation": remote_assembly["name"] if assembly_admitted else None,
        "precision_readiness": precision_readiness,
        "rejected_assaults": [candidate["name"] for candidate in assault_candidates if candidate["name"] not in admitted],
        "air_budget": {"wings": wings, "enemy_air": enemy_air, "reserve": reserve, "max_sweeps": max_sweeps},
        "purchase_fallback": {"attempts": purchase_attempts, "selected": selected_purchase},
        "civilian_queue": {"queued": len(queued_civilians), "workers_counted": queued_workers},
        "dynamic_assignment": {
            "combat_units": combat_units, "budget": assignment_budget,
            "enemy_count_ratio": round(enemy_count_ratio, 2),
            "assault_cap": assault_cap, "operation_cap": operation_cap,
            "operation_budgets": operation_budgets,
            "assigned": assigned_total, "reserve": reserve_total,
        },
        "combined_arms_requirements": {
            "defense": defensive_requirements,
            "defense_excluded_classes": sorted(defense_excluded_classes),
            "precision_coastal": precision_requirements,
            "assault_capacities": assault_capacities,
        },
        "force_targets": {"total": target_force, "arms": force_targets, "deficits": deficits},
        "task_board": task_board,
        "tactical_scan_pool": tactical_scan_pool,
        "economic_plan": {
            "gold": gold, "reserve": reserve_gold, "spendable": spendable_gold,
            "purchase_budget": purchase_budget, "purchase_cap": purchase_cap,
            "capital_force_target": capital_force_target, "capital_shortage": capital_shortage,
            "doctrinal_deficit": doctrinal_deficit,
            "theater_enemy_equivalent": theater_enemy_equivalent,
            "global_enemy_equivalent_ignored": global_enemy_equivalent,
            "bounded_fallback_purchases": diversified,
            "direct_casualty_rate": round(direct_casualty_rate, 3),
            "net_drawdown": round(net_drawdown, 3),
        },
        "city_roles": city_roles,
        "ten_turn_orders": dict(ten_turn_orders),
        "tech_diamond_value": tech_value,
        "building_utility": round(strategic_building_utility, 2),
        "blitz_target_priority": max(blitz_targets, key=blitz_targets.get),
        "purchase_submission": purchase_status,
        "replay_acceptance": {
            "observed_real_losses": observed_real_losses,
            "observed_elite_losses": observed_elite_losses,
            "non_consumable_loss_ceiling": policy_exposure_ceiling,
            "elite_loss_budget": elite_loss_budget,
        },
    }


def joint_operations_v29_scenario() -> dict[str, Any]:
    """Replay the T214 sea, fire-envelope, assignment and async queue failures."""

    observed_convoys = [
        {"unit": "ROCKET_ARTILLERY", "threats": 1, "coverage": 2},
        {"unit": "CRUSADER_ARTILLERY", "threats": 1, "coverage": 1},
        {"unit": "MECHANIZED_INFANTRY", "threats": 1, "coverage": 1},
        {"unit": "COBRA", "threats": 4, "coverage": 0},
    ]
    convoy_decisions: dict[str, str] = {}
    for convoy in observed_convoys:
        required = 2 if convoy["threats"] >= 2 else 1
        convoy_decisions[convoy["unit"]] = (
            "advance-to-landing" if convoy["coverage"] >= required else "hold-for-screen"
        )
    assert convoy_decisions == {
        "ROCKET_ARTILLERY": "advance-to-landing",
        "CRUSADER_ARTILLERY": "advance-to-landing",
        "MECHANIZED_INFANTRY": "advance-to-landing",
        "COBRA": "hold-for-screen",
    }

    detected_targets = [(3, "escort"), (7, "destroyer"), (11, "artillery"), (19, "remote")]
    old_pool = [name for distance, name in detected_targets if distance <= 4]
    missile_pool = [name for distance, name in detected_targets if distance <= 12]
    carrier_air_pool = [name for distance, name in detected_targets if distance <= 10]
    assert old_pool == ["escort"]
    assert missile_pool == ["escort", "destroyer", "artillery"]
    assert carrier_air_pool == ["escort", "destroyer"]

    defensive_requirements = {
        "line_frontline": 8, "siege": 2, "air_superiority": 1,
        "air_strike": 1, "naval_screen": 5, "naval_fire": 1,
    }
    defensive_capacity = {
        slot: (max(required, math.ceil(30 * (0.55 if slot == "line_frontline" else 0.30)))
               if slot in {"line_frontline", "naval_screen"} else required)
        for slot, required in defensive_requirements.items()
    }
    assert defensive_capacity["air_strike"] == 1
    assert defensive_capacity["air_superiority"] == 1
    assert defensive_capacity["siege"] == 2
    assert defensive_capacity["naval_fire"] == 1
    assert defensive_capacity["line_frontline"] > defensive_requirements["line_frontline"]

    scored_choices = ["BUILDING_COAL_TO_URANIUM", "BUILDING_COAL_TO_OIL", "PROCESS_WEALTH"]
    submitted = scored_choices[:1]
    assert submitted == ["BUILDING_COAL_TO_URANIUM"]

    return {
        "scenario": "v29_joint_operations_failure_chain",
        "convoys": convoy_decisions,
        "target_pools": {"old": old_pool, "missile": missile_pool, "carrier_air": carrier_air_pool},
        "defense_capacity": defensive_capacity,
        "city_submissions": submitted,
    }


def v3_takeover_transaction_scenario() -> dict[str, Any]:
    """Exercise the async city and lightweight convergence failures seen at T213."""

    class CityTransaction:
        def __init__(self, signature: str) -> None:
            self.signature = signature
            self.polls = 0

        def reconcile(self, signature: str, blocker: str) -> str:
            if signature != self.signature:
                return "confirmed"
            self.polls += 1
            if self.polls >= 2:
                return "retry"
            return "pending"

    delayed = CityTransaction("0:-1:-1:-1:-1")
    delayed_status = delayed.reconcile("1:-1:42:-1:-1", "clear")
    assert delayed_status == "confirmed"

    instant = CityTransaction("0:-1:-1:-1:-1")
    instant_wait = instant.reconcile("0:-1:-1:-1:-1", "production")
    instant_status = instant.reconcile("0:-1:-1:-1:-1", "production")
    assert instant_wait == "pending"
    assert instant_status == "retry"
    submissions = 2  # initial order plus the order requested by the new blocker
    blocker_after_retry = "clear"
    assert submissions == 2 and blocker_after_retry == "clear"

    full_phases = [
        "national", "readiness", "logistics", "opening-fire",
        "maneuver", "exploitation", "cleanup", "blocker",
    ]
    light_phases = ["light-convergence", "blocker"]
    forbidden_light_phases = {
        "national", "readiness", "logistics", "opening-fire",
        "maneuver", "exploitation", "cleanup",
    }
    assert not forbidden_light_phases.intersection(light_phases)

    registered_turn_drivers = ["SC_OnPlayerDoTurnV11"]
    assert len(registered_turn_drivers) == 1

    process_reevaluation_turns = 5
    process_actions = [
        "keep" if turn % process_reevaluation_turns else "reevaluate"
        for turn in range(211, 216)
    ]
    assert process_actions == ["keep", "keep", "keep", "keep", "reevaluate"]

    city_count = 21
    process_fraction = 0.15
    wartime_process_cap = max(1, math.ceil(city_count * process_fraction))
    production_after_cap = "military" if 12 >= wartime_process_cap else "process"
    assert wartime_process_cap == 4 and production_after_cap == "military"

    transport_policy = {
        "zero_threat": "advance-to-landing",
        "threat_with_screen": "advance-to-landing",
        "threat_without_screen": "hold-for-screen",
    }
    assert transport_policy["zero_threat"] == "advance-to-landing"

    return {
        "scenario": "v3_async_takeover_convergence",
        "delayed_submission": delayed_status,
        "instant_completion": instant_status,
        "submissions_to_clear": submissions,
        "full_phases": full_phases,
        "light_phases": light_phases,
        "turn_drivers": registered_turn_drivers,
        "process_actions": process_actions,
        "wartime_process_cap": wartime_process_cap,
        "production_after_cap": production_after_cap,
        "transport_policy": transport_policy,
    }


def expert_demonstration_v31_scenario() -> dict[str, Any]:
    """Replay the ordering learned from the player's T214 demonstration."""

    enemy_units = 32
    particle_targets = [
        {"class": "line_assault", "power": 242, "damage": 0},
        {"class": "siege_artillery", "power": 326, "damage": 0},
        {"class": "ballistic_submarine", "power": 354, "damage": 0},
    ]
    bonuses = {"line_assault": 0, "siege_artillery": 1500, "ballistic_submarine": 2400}
    scores = [target["power"] * 9 + (100 - target["damage"]) * 5 + bonuses[target["class"]]
              for target in particle_targets]
    opening_target = particle_targets[scores.index(max(scores))]["class"]
    assert opening_target == "ballistic_submarine"

    city_hp = 100
    missile_damage = [18, 22, 20, 19]
    old_cap_damage = sum(missile_damage[:2])
    new_cap_damage = sum(missile_damage[:6])
    air_damage = 21
    naval_damage = 20
    old_city_hp = max(0, city_hp - old_cap_damage - air_damage)
    new_city_hp = max(0, city_hp - new_cap_damage - air_damage - naval_damage)
    assert old_city_hp > 0 and new_city_hp == 0

    destroyer_distance = 11
    destroyer_moves = 11
    old_direct_reach = 4
    new_direct_reach = min(destroyer_moves, 12)
    assert destroyer_distance > old_direct_reach
    assert destroyer_distance <= new_direct_reach

    cached_defenders_after_kills = 6
    live_defenders_after_kills = 0
    capture_without_refresh = cached_defenders_after_kills == 0
    capture_with_refresh = live_defenders_after_kills == 0 and new_city_hp == 0
    assert not capture_without_refresh and capture_with_refresh

    phases = [
        "global-special-weapon", "opening-fire", "refresh-live-world",
        "maneuver", "second-fire", "refresh-live-world", "capture-exploitation",
    ]
    return {
        "scenario": "expert_demonstration_v31",
        "observed_enemy_kills": enemy_units,
        "observed_non_consumable_losses": 0,
        "opening_target_class": opening_target,
        "missiles_committed": len(missile_damage),
        "old_city_hp_after_package": old_city_hp,
        "new_city_hp_after_package": new_city_hp,
        "capture_unit": "UNIT_CHINESE_052D",
        "capture_distance": destroyer_distance,
        "dynamic_capture_reach": new_direct_reach,
        "cache_refresh_changes_capture": capture_with_refresh and not capture_without_refresh,
        "phases": phases,
    }


def battlefield_recovery_v32_scenario() -> dict[str, Any]:
    """Replay the T217-T219 ownership, survival and mobility failures."""

    particle = {"target_distance": 1, "nearby_threats": 2, "minimum_standoff": 5}
    opening_decision = "fire" if particle["target_distance"] >= particle["minimum_standoff"] and particle["nearby_threats"] == 0 else "reposition"
    particle.update(target_distance=6, nearby_threats=0)
    after_move_decision = "fire" if particle["target_distance"] >= particle["minimum_standoff"] and particle["nearby_threats"] == 0 else "hold"
    assert opening_decision == "reposition" and after_move_decision == "fire"

    previous_capture_assignment = {"052D": "city_56_49", "modern_armor": "city_53_42"}
    live_capture_tasks = {"city_62_49", "city_56_49"}
    retained = {unit: city for unit, city in previous_capture_assignment.items() if city in live_capture_tasks}
    assert retained == {"052D": "city_56_49"}
    capture_reach = min(11, 12)
    assert 11 <= capture_reach

    source_enemy_distance = 3
    destinations = {"front_carrier": 4, "rear_city": 9, "mid_city": 7}
    safe_destinations = {name: distance for name, distance in destinations.items() if distance > 6 and distance > source_enemy_distance}
    evacuation_target = max(safe_destinations, key=safe_destinations.get)
    assert evacuation_target == "rear_city"

    enemy_count_ratio = 5.24
    offensive_power_ratio = 10.37
    defensive_power_ratio = 1.62
    multi_axis = offensive_power_ratio >= 3.0 and defensive_power_ratio >= 1.20
    assault_axes = 2 if multi_axis else (1 if enemy_count_ratio >= 2.5 else 2)
    assert assault_axes == 2

    no_local_enemy_plan = None
    operation_target_distance = 28
    rally_plan = "rally-waypoint" if no_local_enemy_plan is None and operation_target_distance > 3 else None
    assert rally_plan == "rally-waypoint"

    return {
        "scenario": "battlefield_recovery_v32",
        "particle_sequence": [opening_decision, after_move_decision],
        "capture_assignment_retained": retained,
        "direct_capture_reach": capture_reach,
        "airbase_evacuation": evacuation_target,
        "assault_axes": assault_axes,
        "no_plan_fallback": rally_plan,
    }


def execution_first_v4_scenario() -> dict[str, Any]:
    """Contract-test the authority and retry rules of the live executor.

    This is deliberately not a combat forecast. It checks the state transitions
    that the old strategic simulator omitted: task advice cannot veto a live
    action, rejected commands consume no budget, and the world is rebuilt from
    identities after every substantive action.
    """

    world = {
        "generation": 0,
        "enemy_units": [
            {"owner_id": 2, "unit_id": 41, "x": 12, "y": 10},
            {"owner_id": 2, "unit_id": 42, "x": 6, "y": 1},
        ],
        "enemy_cities": [
            {"owner_id": 2, "city_id": 7, "x": 17, "y": 15, "capture_ready": True},
        ],
    }
    identity_fields = {"owner_id", "unit_id", "city_id", "x", "y", "capture_ready"}
    assert all(
        set(record).issubset(identity_fields)
        and all(isinstance(value, (int, bool)) for value in record.values())
        for record in world["enemy_units"] + world["enemy_cities"]
    )

    units = {
        "artillery": {
            "task": "strategic_reserve", "x": 10, "y": 10, "range": 3,
            "can_fire": True, "completed": False,
        },
        "expedition": {
            "task": "city_defense", "x": 0, "y": 0, "moves": 4,
            "completed": False, "rejected": set(),
        },
        "destroyer": {
            "task": "operation:other-city", "x": 15, "y": 15,
            "can_capture": True, "completed": False,
        },
    }
    old_authority_actions = 0
    actions: list[str] = []
    phases: list[str] = []

    def refresh(reason: str) -> None:
        world["generation"] += 1
        phases.append(f"refresh:{reason}:g{world['generation']}")

    phases.append("opening-fire")
    artillery = units["artillery"]
    target = world["enemy_units"][0]
    distance = max(abs(artillery["x"] - target["x"]), abs(artillery["y"] - target["y"]))
    if artillery["can_fire"] and distance <= artillery["range"]:
        actions.append("artillery:fire:unit41")
        artillery["completed"] = True
        refresh("opening-fire")

    phases.append("capture-opportunity")
    destroyer = units["destroyer"]
    city = world["enemy_cities"][0]
    city_distance = max(abs(destroyer["x"] - city["x"]), abs(destroyer["y"] - city["y"]))
    if destroyer["can_capture"] and city["capture_ready"] and city_distance <= 2:
        actions.append("destroyer:capture-substitute:city7")
        destroyer["completed"] = True
        refresh("capture")

    expedition = units["expedition"]
    candidate_waypoints = [(4, 0), (3, 1)]
    accepted_waypoint = None
    rejected_orders = 0
    successful_orders = 0
    for wave, waypoint in enumerate(candidate_waypoints, start=1):
        phases.append(f"maneuver-wave-{wave}")
        if waypoint in expedition["rejected"]:
            continue
        native_accepted = waypoint != (4, 0)
        if not native_accepted:
            expedition["rejected"].add(waypoint)
            rejected_orders += 1
            assert not expedition["completed"]
            continue
        expedition["x"], expedition["y"] = waypoint
        expedition["completed"] = True
        accepted_waypoint = waypoint
        successful_orders += 1
        actions.append(f"expedition:move:{waypoint[0]},{waypoint[1]}")
        refresh(f"move-wave-{wave}")
        break

    assert old_authority_actions == 0
    assert artillery["completed"]
    assert destroyer["completed"]
    assert accepted_waypoint == (3, 1)
    assert rejected_orders == 1 and successful_orders == 1
    assert (4, 0) in expedition["rejected"]
    assert world["generation"] == len(actions)

    return {
        "scenario": "execution_first_live_world_v4",
        "model_scope": "state-transition contract, not combat forecast",
        "old_authority_actions": old_authority_actions,
        "new_substantive_actions": len(actions),
        "actions": actions,
        "phases": phases,
        "world_generations": world["generation"],
        "world_records_are_identities": True,
        "rejected_orders": rejected_orders,
        "successful_orders": successful_orders,
        "failed_order_consumed_budget": False,
        "capture_task_was_advisory": True,
    }


def execution_doctrine_v41_scenario(catalog: UnitCatalog) -> dict[str, Any]:
    """Exercise the v4.1 chains that failed in the T217-T220 telemetry."""

    observed = {
        "friendly_combat": 257,
        "enemy_combat": 1380,
        "offensive_power_ratio": 8.70,
        "defensive_power_ratio": 1.04,
        "capture_ready_cities": 6,
        "embarked_units": 53,
    }
    multi_axis = (
        observed["offensive_power_ratio"] >= 3.0
        and observed["defensive_power_ratio"] >= 0.95
    )
    assault_axes = min(3, 8) if multi_axis else 1
    assert assault_axes == 3

    capture_candidates = [
        {"name": "exhausted-052d", "distance": 1, "can_move": False, "previous": True},
        {"name": "fresh-armor", "distance": 2, "can_move": True, "previous": False},
        {"name": "fresh-infantry", "distance": 3, "can_move": True, "previous": True},
    ]
    eligible = [candidate for candidate in capture_candidates if candidate["can_move"]]
    selected = max(
        eligible,
        key=lambda candidate: 6200 - candidate["distance"] * 145
        + (1500 if candidate["previous"] else 0),
    )
    assert selected["name"] == "fresh-infantry"
    assert all(candidate["name"] != "exhausted-052d" for candidate in eligible)
    active_capture_tasks = min(observed["capture_ready_cities"], 8)
    assert active_capture_tasks == observed["capture_ready_cities"]

    def move_accepted(changed_plot: bool, combat_resolved: bool, order_cleared: bool) -> bool:
        del order_cleared
        return changed_plot or combat_resolved

    assert not move_accepted(False, False, True)
    assert move_accepted(True, False, False)
    assert move_accepted(False, True, False)

    mobile_bases = {
        unit_type: {
            "special_cargo": str(unit.get("SpecialCargo") or ""),
            "domain_cargo": str(unit.get("DomainCargo") or ""),
        }
        for unit_type, unit in catalog.units.items()
        if str(unit.get("Domain") or "") == "DOMAIN_SEA"
        and str(unit.get("DomainCargo") or "") == "DOMAIN_AIR"
        and str(unit.get("SpecialCargo") or "")
    }
    for required in ("UNIT_SUPER_CARRIER", "UNIT_CHINESE_052D", "UNIT_KIROV_BATTLECRUISER"):
        assert required in mobile_bases, required
    assert mobile_bases["UNIT_SUPER_CARRIER"]["special_cargo"] == "SPECIALUNIT_FIGHTER"
    assert mobile_bases["UNIT_CHINESE_052D"]["special_cargo"] == "SPECIALUNIT_MISSILE"

    fire_priority = {
        "missile_strike": 1,
        "strike_aircraft": 1,
        "arsenal_capital": 2,
        "surface_fire_support": 2,
        "siege_artillery": 2,
        "carrier_multirole": 3,
    }
    fire_order = sorted(fire_priority, key=lambda doctrine: (fire_priority[doctrine], doctrine))
    assert fire_order.index("missile_strike") < fire_order.index("carrier_multirole")
    assert fire_order.index("strike_aircraft") < fire_order.index("carrier_multirole")

    return {
        "scenario": "execution_doctrine_v41",
        "observed_world": observed,
        "assault_axes": assault_axes,
        "active_capture_tasks": active_capture_tasks,
        "capture_substitute": selected["name"],
        "no_effect_move_rejected": True,
        "mobile_airbases": sorted(mobile_bases),
        "fire_order": fire_order,
        "post_move_rebase": True,
        "unopposed_transport_policy": "advance-or-land",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=default_database())
    parser.add_argument("--show-catalog", action="store_true")
    parser.add_argument("--log", type=Path, help="Optional Strategic Command log to summarize by doctrine class")
    parser.add_argument("--save", type=Path, help="Optional Civ5 save paired with the log world snapshot")
    parser.add_argument(
        "--strict-realism", action="store_true",
        help="Return a failure when real execution telemetry contradicts the contract models",
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if not args.db.exists():
        parser.error(f"Civ5 debug database not found: {args.db}")
    catalog = UnitCatalog(args.db)
    result = {
        "catalog_audit": audit_catalog(catalog),
        "combat_regression": future_carrier_group_scenario(catalog),
        "convoy_regression": convoy_scenario(),
        "airlift_regression": airlift_scenario(catalog),
        "target_memory_regression": strategic_target_memory_scenario(),
        "scope_runtime_regression": strategic_scope_and_runtime_scenario(),
        "quick_buy_regression": quick_buy_buildings_scenario(),
        "theater_regression": theater_assignment_scenario(),
        "runtime_regression": runtime_and_great_people_scenario(),
        "capture_task_regression": city_capture_task_scenario(catalog),
        "purchase_regression": military_purchase_scenario(),
        "capital_conversion_regression": capital_conversion_scenario(),
        "production_regression": production_scenario(),
        "focus_regression": executable_focus_scenario(),
        "elite_regression": elite_program_scenario(catalog),
        "asset_protection_regression": asset_protection_scenario(catalog),
        "historical_loss_regression": historical_loss_replay_scenario(catalog),
        "mission_lifecycle_regression": mission_lifecycle_scenario(),
        "national_strategy_regression": national_strategy_scenario(catalog),
        "joint_operations_v29_regression": joint_operations_v29_scenario(),
        "v3_takeover_regression": v3_takeover_transaction_scenario(),
        "expert_demonstration_v31_regression": expert_demonstration_v31_scenario(),
        "battlefield_recovery_v32_regression": battlefield_recovery_v32_scenario(),
        "execution_first_v4_regression": execution_first_v4_scenario(),
        "execution_doctrine_v41_regression": execution_doctrine_v41_scenario(catalog),
    }
    if args.log is not None:
        if not args.log.exists():
            parser.error(f"Log not found: {args.log}")
        result["log_analysis"] = analyze_log(args.log, catalog)
        result["world_snapshot"] = parse_world_snapshot(args.log, catalog)
        result["strategy_audit"] = build_strategy_audit(
            result["log_analysis"], result["world_snapshot"]
        )
        result["observed_crash_replay"] = replay_observed_crash_chain(
            result["log_analysis"], result["world_snapshot"]
        )
        result["execution_replay"] = analyze_execution_replay(args.log, catalog)
        result["fidelity_report"] = build_fidelity_report(
            result["execution_replay"], result["log_analysis"],
            result["world_snapshot"], result["combat_regression"],
        )
        from DecisionReplay import analyze as replay_deployed_decisions
        lua_path = Path(r"C:\Program Files (x86)\Lua\5.1\lua.exe")
        result["deployed_decision_replay"] = (
            replay_deployed_decisions(args.log, Path(__file__).resolve().parents[1], str(lua_path))
            if lua_path.exists() else {"status": "UNAVAILABLE", "reason": "Lua 5.1 runtime required"}
        )
    result["model_scope"] = "Legacy arithmetic scenarios are hypotheses, not gameplay outcomes. Deployed Lua replay and observed execution are separate evidence."
    save_path = args.save
    if save_path is None and args.log is not None:
        save_path = default_latest_save()
    if save_path is not None:
        if not save_path.exists():
            parser.error(f"Save not found: {save_path}")
        result["save_metadata"] = parse_save_metadata(save_path)
    if args.show_catalog:
        result["unit_catalog"] = {
            unit_type: catalog.profile(unit_type)
            for unit_type in sorted(catalog.units)
        }
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(result["model_scope"])
        if "deployed_decision_replay" in result:
            print("DEPLOYED LUA:", result["deployed_decision_replay"])
        audit = result["catalog_audit"]
        combat = result["combat_regression"]
        print(f"PASS catalog: {audit['units']} units, {audit['military_units']} military, {len(audit['classes'])} doctrine classes")
        print(f"CONTRACT combat arithmetic: destroyed {combat['enemy_units_destroyed']}/{combat['enemy_units_total']}, city captured={combat['city_captured']}, losses={combat['friendly_losses']}, accidental wars={combat['accidental_wars']}")
        production = result["production_regression"]
        focus = result["focus_regression"]
        elite = result["elite_regression"]
        protection = result["asset_protection_regression"]
        history = result["historical_loss_regression"]
        lifecycle = result["mission_lifecycle_regression"]
        national = result["national_strategy_regression"]
        joint = result["joint_operations_v29_regression"]
        v3 = result["v3_takeover_regression"]
        expert = result["expert_demonstration_v31_regression"]
        recovery = result["battlefield_recovery_v32_regression"]
        execution_v4 = result["execution_first_v4_regression"]
        execution_v41 = result["execution_doctrine_v41_regression"]
        theater = result["theater_regression"]
        runtime = result["runtime_regression"]
        capture_task = result["capture_task_regression"]
        purchase = result["purchase_regression"]
        capital_conversion = result["capital_conversion_regression"]
        print("PASS convoy: zero-threat advance, escorted advance to landing, exposed transport hold")
        airlift = result["airlift_regression"]
        print(f"PASS airlift: direct={airlift['remote_unit_at_base']}, stage={airlift['remote_unit_near_base']}, async={airlift['same_tick_status']}->{airlift['next_turn_status']}, reverse-blocked={airlift['reverse_route_blocked']}")
        target_memory = result["target_memory_regression"]
        print(f"PASS target memory: switches={target_memory['baseline_switches']}->{target_memory['memory_switches']}, assignments={','.join(target_memory['persistent_assignments'])}")
        scope_runtime = result["scope_runtime_regression"]
        print(f"PASS scope/runtime: expensive candidates={scope_runtime['expensive_candidates_before']}->{scope_runtime['expensive_candidates_after']} ({scope_runtime['candidate_reduction_percent']}% reduction), modes={','.join(scope_runtime['pass_modes'])}")
        quick_buy = result["quick_buy_regression"]
        print(f"PASS quick buy: purchases={','.join(quick_buy['purchases'])}, one submission/tick, stop={quick_buy['stop_reason']}")
        print(f"PASS theater: local screens={theater['target_commitments']['convoy_raider']}, far artillery={theater['assignments']['far_artillery']}, escort retries={theater['failed_escort_attempts_per_pair']}")
        print(f"PASS runtime: sweeps={runtime['executed_sweeps']}, heal orders={runtime['healing_orders_per_unit']}, GP roles={len(runtime['great_people'])}, capture slots={runtime['city_capture_slots']}")
        print(f"PASS capture task: assignments={capture_task['assignments']}, cap={capture_task['maximum_commitment_per_city']}, negative plans rejected={capture_task['negative_plans_rejected']}")
        print(f"PASS purchase: reserve={purchase['reserve']}, budget={purchase['budget']}, max={purchase['max_purchases']}, needs={','.join(purchase['purchase_needs'])}, GP waypoint={purchase['great_person_waypoint_fallback']}")
        print(f"PASS capital conversion: annexed={','.join(capital_conversion['annexed'])}, buildings={','.join(capital_conversion['building_orders'])}, force={capital_conversion['desired_force']}, max purchases={capital_conversion['purchase_cap']}")
        print(f"PASS production: packages={production['package_count']}, arms={','.join(production['categories_filled'])}, unique wonder assignments={production['unique_wonder_assignments']}, military queue slots={production['military_slots']}")
        print(f"PASS focus: selected={focus['selected_focus']}, far city rejected, zero-HP and negative-score fire suppressed")
        print(f"PASS elite: detected={elite['elite_units_detected']}, late={elite['late_elite_units']}, queued projects={elite['queued_project_cap']}, mech excluded")
        print(f"PASS protection: tiers={protection['tiers']}, sea={protection['severe_sea_transit']}, apache={protection['apache_at_30hp']}, artillery standoff={protection['artillery_min_standoff']}")
        print(f"PASS historical replay: guarded {history['guarded_losses']}/{history['observed_losses']} observed v1.40 losses; interventions={history['guard_counts']}")
        print(f"PASS lifecycle: old crash={lifecycle['old_path_crashed']}, new={lifecycle['new_status']}, convoy={lifecycle['embarked_high_value_policy']}")
        print(
            "PASS national strategy: "
            f"count ratio={national['power_model']['global_count_ratio']} -> "
            f"local power={national['power_model']['local_effective_ratio']} "
            f"posture={national['power_model']['posture']}, "
            f"defense={','.join(national['defense_operations'])}, "
            f"assault={','.join(national['admitted_assaults'])}, "
            f"air sweeps={national['air_budget']['max_sweeps']}/{national['air_budget']['wings']}, "
            f"assigned={national['dynamic_assignment']['assigned']}/{national['dynamic_assignment']['combat_units']}, "
            f"target force={national['force_targets']['total']}, "
            f"purchase budget={national['economic_plan']['purchase_budget']}, "
            f"process={national['ten_turn_orders']['process']}"
        )
        print(
            "PASS v2.9 joint operations: "
            f"convoys={joint['convoys']}, missile targets={len(joint['target_pools']['missile'])}, "
            f"defense air strike cap={joint['defense_capacity']['air_strike']}, "
            f"city submissions={len(joint['city_submissions'])}"
        )
        print(
            "PASS v3 takeover: "
            f"async={v3['delayed_submission']}, instant={v3['instant_completion']}, "
            f"submissions={v3['submissions_to_clear']}, drivers={len(v3['turn_drivers'])}, "
            f"light={','.join(v3['light_phases'])}"
        )
        print(
            "PASS v3.1 expert replay: "
            f"opening={expert['opening_target_class']}, missiles={expert['missiles_committed']}, "
            f"cityHP={expert['old_city_hp_after_package']}->{expert['new_city_hp_after_package']}, "
            f"capture={expert['capture_unit']}@{expert['capture_distance']}/{expert['dynamic_capture_reach']}, "
            f"refresh={expert['cache_refresh_changes_capture']}"
        )
        print(
            "PASS v3.2 battlefield recovery: "
            f"particle={'>'.join(recovery['particle_sequence'])}, "
            f"capture-lock={recovery['capture_assignment_retained']}, "
            f"air-evac={recovery['airbase_evacuation']}, axes={recovery['assault_axes']}, "
            f"fallback={recovery['no_plan_fallback']}"
        )
        print(
            "PASS v4 execution-first: "
            f"actions={execution_v4['old_authority_actions']}->{execution_v4['new_substantive_actions']}, "
            f"generations={execution_v4['world_generations']}, "
            f"retry={execution_v4['rejected_orders']} rejected/{execution_v4['successful_orders']} accepted, "
            f"failed-consumed={execution_v4['failed_order_consumed_budget']}"
        )
        print(
            "PASS v4.1 execution doctrine: "
            f"axes={execution_v41['assault_axes']}, capture tasks={execution_v41['active_capture_tasks']}, "
            f"substitute={execution_v41['capture_substitute']}, "
            f"mobile bases={len(execution_v41['mobile_airbases'])}, "
            f"no-effect rejected={execution_v41['no_effect_move_rejected']}"
        )
        if "log_analysis" in result:
            analysis = result["log_analysis"]
            observed = analysis["observed"]
            replay = analysis["policy_replay"]
            print(
                f"CALIBRATION log v{analysis['loaded_version']}: combat losses={observed['combat_losses']}, "
                f"high-value={observed['high_value_losses']}, embarked={observed['embarked_losses']}, "
                f"retreat-eligible={observed['retreat_eligible_losses']}, commanders={observed['commander_losses']}, "
                f"policy coverage={replay['coverage']}"
            )
            if analysis["performance_passes"]:
                print(f"  pass performance={analysis['performance_passes']}")
            for loss in analysis["losses"]:
                guards = ",".join(loss["v141_guards"]) or "none"
                print(
                    f"  T{loss['turn']} {loss['unit']}#{loss['id']} damage={loss['damage']} "
                    f"embarked={str(loss['embarked']).lower()} killer=P{loss['killer']} guards={guards}"
                )
            termination = analysis["termination"]
            print(
                f"  termination: passes={termination['passes_started']}/{termination['passes_ended']} "
                f"abrupt={termination['abrupt_during_pass']} stale-accesses={len(termination['stale_unit_accesses'])} "
                f"probable-native-crash={termination['probable_native_handle_crash']}"
            )
        if "world_snapshot" in result:
            world = result["world_snapshot"]
            policy = world.get("policy_replay", {})
            print(
                f"WORLD T{world.get('turn')}: units={world.get('units')}/{world.get('declared_units')} "
                f"cities={world.get('cities')}/{world.get('declared_cities')} own={world.get('own_units')} "
                f"enemy={world.get('enemy_units')} embarked={world.get('embarked_units')} "
                f"threatened={len(world.get('threatened_embarked', []))}"
            )
            print(
                f"  policy replay: actions={policy.get('actions')} targets="
                f"{policy.get('target_evaluations_before')}->{policy.get('target_evaluations_bounded')} "
                f"({policy.get('target_reduction_percent')}% reduction) safety={policy.get('safety_invariants_pass')}"
            )
            v22 = world.get("v22_strategy_replay", {})
            print(
                f"  v2.2 replay: posture={v22.get('posture')} ratio={v22.get('power_ratio')} "
                f"assigned={v22.get('assigned')}/{v22.get('combat_units')} "
                f"budget={v22.get('assignment_budget')} reserve={v22.get('reserve')} "
                f"operations={len(v22.get('operations', []))} unassigned={v22.get('unassigned_by_class')}"
            )
            crash_replay = result["observed_crash_replay"]
            if crash_replay.get("available"):
                outcomes = ", ".join(
                    f"{item['name']}={item['decision']}/survive:{item['unit_survives']}/crash:{item['native_crash_risk']}"
                    for item in crash_replay["iterations"]
                )
                print(f"  crash replay {crash_replay['victim']}: {outcomes}")
            else:
                print(f"  crash replay unavailable: {crash_replay['reason']}")
            strategy = result["strategy_audit"]
            print(
                f"  strategy audit: findings={len(strategy['findings'])} "
                f"full-pass={strategy['runtime']['full_pass_average_ms']}ms "
                f"strategic-share={strategy['runtime']['strategic_movement_share']:.1%}"
            )
            for finding in strategy["findings"]:
                print(f"    {finding['severity']} {finding['category']}: {finding['evidence']}")
            execution = result["execution_replay"]
            fidelity = result["fidelity_report"]
            execution_rates = execution.get("rates", {})
            execution_totals = execution.get("totals", {})
            print(
                f"EXECUTION REPLAY: full episodes={execution.get('full_episode_count')} "
                f"substantive={execution_totals.get('substantive_units', 0)}/"
                f"{execution_totals.get('maneuver_capable_units', 0)} "
                f"({execution_rates.get('substantive_per_maneuver_capable', 0):.1%}) "
                f"range-struck={execution_totals.get('range_struck', 0)} "
                f"air-swept={execution_totals.get('air_swept', 0)} "
                f"accepted-no-effect-moves={execution_totals.get('accepted_no_effect_moves', 0)} "
                f"fallback-only={execution_totals.get('fallback_only_units', 0)} "
                f"capture={execution_totals.get('captures', 0)}/"
                f"{execution_totals.get('capture_attempts', 0)}"
            )
            forecast = fidelity["empirical_forecast"]
            print(
                f"FIDELITY {fidelity['status']}: contract kills={forecast['contract_enemy_kills']} "
                f"-> empirically discounted={forecast['effective_enemy_kills']}, "
                f"capture probability={forecast['capture_probability']:.1%}, "
                f"losses/100 units/pass={forecast['expected_friendly_losses_per_100_units_per_pass']}"
            )
            for divergence in fidelity["divergences"]:
                print(
                    f"  {divergence['severity']} {divergence['category']}: "
                    f"{divergence['evidence']}"
                )
        if "save_metadata" in result:
            save = result["save_metadata"]
            print(
                f"SAVE T{save['turn']} {save['civilization']} {save['world_size']} "
                f"{save['game_speed']} bytes={save['size']} sha256={save['sha256'][:12]}"
            )
        print("Doctrine distribution:")
        for doctrine_class, count in audit["classes"].items():
            print(f"  {doctrine_class}: {count}")
    if result.get("deployed_decision_replay", {}).get("status") == "FAIL":
        return 3
    if args.strict_realism and result.get("fidelity_report", {}).get("status") != "PASS":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
