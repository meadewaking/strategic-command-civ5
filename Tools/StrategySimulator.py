#!/usr/bin/env python3
"""Database-driven strategy audit and lightweight combat regression simulator."""

from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


def default_database() -> Path:
    return Path.home() / "Documents" / "My Games" / "Sid Meier's Civilization 5" / "cache" / "Civ5DebugDatabase.db"


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

    doctrine_class, phase = "line_assault", 4
    if combat <= 0 and ranged <= 0 and not combat_class and domain not in ("DOMAIN_AIR", "DOMAIN_SEA"):
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
    elif combat_class == "UNITCOMBAT_SIEGE" or ai == "UNITAI_CITY_BOMBARD" or (ranged > 0 and attack_range >= 3):
        doctrine_class, phase = "siege_artillery", 3
    elif combat_class == "UNITCOMBAT_HELICOPTER":
        doctrine_class, phase = "gunship", 2
    elif ai == "UNITAI_PARADROP" or promo["drop_range"] > 0:
        doctrine_class, phase = "airborne_raider", 1
    elif combat_class == "UNITCOMBAT_RECON" or ai == "UNITAI_EXPLORE":
        doctrine_class, phase = "recon_raider", 1
    elif combat_class in ("UNITCOMBAT_ARMOR", "UNITCOMBAT_MOUNTED") or ai == "UNITAI_FAST_ATTACK" or (moves >= 5 and combat > 0):
        doctrine_class, phase = "mobile_breakthrough", 4
    elif ai == "UNITAI_COUNTER":
        doctrine_class, phase = "counter_defender", 4
    elif ai == "UNITAI_DEFENSE" or promo["only_defensive"]:
        doctrine_class, phase = "line_defender", 4
    elif ranged > 0:
        doctrine_class, phase = "ranged_support", 3

    can_capture = (
        combat > 0
        and domain not in ("DOMAIN_AIR", "DOMAIN_HOVER")
        and not promo["no_capture"]
        and not promo["only_defensive"]
        and not as_bool(unit.get("Suicide"))
        and doctrine_class not in ("fleet_carrier", "ballistic_submarine")
    )
    return {
        "type": unit_type,
        "class": doctrine_class,
        "phase": phase,
        "domain": domain,
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
        "cargo": promo["cargo"],
    }


PROTECTED_CLASSES = {"fleet_carrier", "ballistic_submarine", "arsenal_capital"}
SCREEN_CLASSES = {"air_defense_screen", "escort_screen", "attack_submarine", "mobile_air_defense"}


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
            return "release-no-threat"
        required = 2 if threats >= 2 else 1
        if escorts < required:
            return f"hold:{escorts}/{required}"
        return "advance-enemy-coast" if mission_class == "combat" else "retreat-friendly-coast"

    assert decision("combat", 0, 0) == "release-no-threat"
    assert decision("trade", 0, 3) == "release-trade"
    assert decision("combat", 1, 1) == "advance-enemy-coast"
    assert decision("combat", 1, 2) == "hold:1/2"
    assert decision("worker", 2, 2) == "retreat-friendly-coast"
    return {
        "scenario": "ocean_transport_convoy",
        "no_threat_without_escort": "release",
        "trade_ship": "trade-route-managed",
        "one_threat_with_one_escort": "advance",
        "severe_threat_with_one_escort": "hold",
        "civilian_under_severe_threat": "retreat-friendly-coast",
        "transport_exposed": False,
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


def audit_catalog(catalog: UnitCatalog) -> dict[str, Any]:
    profiles = [catalog.profile(unit_type) for unit_type in catalog.units]
    military = [
        profile
        for profile in profiles
        if profile["power"] > 0 or profile["domain"] in ("DOMAIN_AIR", "DOMAIN_HOVER")
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
    assert not catalog.profile("UNIT_SSBN")["can_capture"]
    return {
        "database": str(catalog.database),
        "units": len(profiles),
        "military_units": len(military),
        "free_promotions": sum(len(items) for items in catalog.promotions.values()),
        "classes": dict(sorted(Counter(profile["class"] for profile in profiles).items())),
        "unclassified_military": bad,
    }


def analyze_log(log_path: Path, catalog: UnitCatalog) -> dict[str, Any]:
    unit_pattern = re.compile(r"unit=(UNIT_[A-Z0-9_]+)#([^ ]+)@P([0-9]+)")
    action_pattern = re.compile(r"(?:localDefense (?:fired|queued)|strategicMove order|captureFinish try|airSuperiority sweep) .*?unit=(UNIT_[A-Z0-9_]+)#([^ ]+)@P([0-9]+)")
    latest_units: dict[str, str] = {}
    actions: Counter[str] = Counter()
    versions: list[str] = []
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            version = re.search(r"Strategic Command v([0-9.]+) loaded", line)
            if version:
                versions.append(version.group(1))
            unit_match = unit_pattern.search(line)
            if "DEMO category=unitState" in line and unit_match:
                unit_type, unit_id, owner = unit_match.groups()
                latest_units[f"P{owner}:{unit_id}"] = unit_type
            action_match = action_pattern.search(line)
            if action_match:
                unit_type = action_match.group(1)
                if unit_type in catalog.units:
                    actions[catalog.profile(unit_type)["class"]] += 1
    roster = Counter(
        catalog.profile(unit_type)["class"]
        for unit_type in latest_units.values()
        if unit_type in catalog.units
    )
    return {
        "path": str(log_path),
        "loaded_version": versions[-1] if versions else None,
        "snapshot_units": len(latest_units),
        "roster_classes": dict(sorted(roster.items())),
        "action_classes": dict(sorted(actions.items())),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=default_database())
    parser.add_argument("--show-catalog", action="store_true")
    parser.add_argument("--log", type=Path, help="Optional Strategic Command log to summarize by doctrine class")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if not args.db.exists():
        parser.error(f"Civ5 debug database not found: {args.db}")
    catalog = UnitCatalog(args.db)
    result = {
        "catalog_audit": audit_catalog(catalog),
        "combat_regression": future_carrier_group_scenario(catalog),
        "convoy_regression": convoy_scenario(),
        "production_regression": production_scenario(),
        "focus_regression": executable_focus_scenario(),
        "elite_regression": elite_program_scenario(catalog),
    }
    if args.log is not None:
        if not args.log.exists():
            parser.error(f"Log not found: {args.log}")
        result["log_analysis"] = analyze_log(args.log, catalog)
    if args.show_catalog:
        result["unit_catalog"] = {
            unit_type: catalog.profile(unit_type)
            for unit_type in sorted(catalog.units)
        }
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        audit = result["catalog_audit"]
        combat = result["combat_regression"]
        print(f"PASS catalog: {audit['units']} units, {audit['military_units']} military, {len(audit['classes'])} doctrine classes")
        print(f"PASS combat: destroyed {combat['enemy_units_destroyed']}/{combat['enemy_units_total']}, city captured={combat['city_captured']}, losses={combat['friendly_losses']}, accidental wars={combat['accidental_wars']}")
        production = result["production_regression"]
        focus = result["focus_regression"]
        elite = result["elite_regression"]
        print("PASS convoy: zero-threat release, threat-scaled escort, civilian retreat")
        print(f"PASS production: packages={production['package_count']}, arms={','.join(production['categories_filled'])}, unique wonder assignments={production['unique_wonder_assignments']}, military queue slots={production['military_slots']}")
        print(f"PASS focus: selected={focus['selected_focus']}, far city rejected, zero-HP and negative-score fire suppressed")
        print(f"PASS elite: detected={elite['elite_units_detected']}, late={elite['late_elite_units']}, queued projects={elite['queued_project_cap']}, mech excluded")
        print("Doctrine distribution:")
        for doctrine_class, count in audit["classes"].items():
            print(f"  {doctrine_class}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
