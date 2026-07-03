Strategic Command v1

Purpose:
Reduce late-game micromanagement by adding a high-level automation layer.

Current MVP features:
- Adds a visible SC button and a small Strategic Command panel.
- Every configured interval, posts a national brief notification.
- Automatically assigns production only to non-puppet, non-resisting cities with an empty queue.
- In wartime, cities can prioritize modern combat units if the army is below the target size.
- Ranged combat units can automatically fire at valid war targets when they still have movement.
- Optional automatic research selection, based on the selected doctrine.
- Optional automatic unit upgrades.
- Optional healing orders for damaged combat units.
- Optional city ranged strike automation.
- Optional idle posture cleanup for combat units.
- Buttons to open the tech tree and social policy screen.

Configuration:
Edit Lua/StrategicCommand_Config.lua before loading a game.

Important defaults:
- InterventionInterval = 10
- AutoCityProduction = false
- AutoLocalDefense = false
- AutoResearch = false
- AutoUpgradeUnits = false
- AutoHealDamagedUnits = false
- AutoCityRangedStrike = false
- AutoIdlePosture = false
- Doctrine = "BALANCED"

Supported doctrines:
- BALANCED
- SCIENCE
- INDUSTRY
- WAR

Roadmap:
- Diplomatic secretary for low-value trade/contact filtering.
- Strategic command panel for in-game configuration.
- Army group orders: rally, defend, attack city, naval expedition.
- World Congress auto-voting policy.
