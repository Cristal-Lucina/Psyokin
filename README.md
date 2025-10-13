# Psyokin

P S Y O K I N


1) PROJECT TITLE AND DESCRIPTION
Psyokin is a single‑player indie RPG built with Godot 4.4.1. It blends a school‑life calendar with strategic battles and relationship systems. Each in‑game day has phases, you attend classes, train, run missions or VR, manage gear and Sigils, and deepen Circle Bonds. Systems are data‑driven through CSV files and the game state is saved to JSON for fast resume.

2) FEATURES (IN PROGRESS)
* Calendar and time flow with morning and afternoon phases, week resets, and signals when days advance.
* Save and Load with JSON slot files, continue picks the newest timestamp automatically.
* GameState snapshot and restore, resilient to missing fields and older data, defensive loading.
* Typed GDScript autoload systems for stats, inventory and equipment, world spots, bonds, scene routing, audio, and more.
* Title screen with New, Load, Options, and Continue when saves exist.
* In‑game tabbed menu framework for Stats, Perks, Items, Loadout, Bonds, Outreach, Dorms, Calendar, Index, and System.
* Data‑driven content from CSVs for items, world spots, bond rewards and events, and optional enemy definitions.
* Robust UI patterns, connect signals once, refresh buttons, graceful fallbacks when data is missing.

3) GETTING STARTED
Required engine, Godot 4.4.1 stable.
Steps to run:
* Clone the repository to your machine.
* Open the folder in Godot and load project.godot.
* Press Play. You will see Boot, then the Title screen. Start a New Game or Continue if a save exists.

Project structure, common paths:
* scenes, Title.tscn, Main.tscn, SaveLoad.tscn, Options.tscn, UI overlays for save, load, training.
* scripts, core systems and UI panels organized under core, systems, main_menu, ui, dev.
* data, CSV files such as data,items,items.csv, data,world,world_spots.csv, data,circles, and optional data,progression,enemy_defs.csv.
* user, saves, created at runtime for slot files. This directory lives under your OS user data path, not in the repo.

Autoloads, typical list:
aCSVLoader, aSettings, aGameState, aSaveLoad, aCalendarSystem, aStatsSystem, aInventorySystem, aWorldSpotsSystem, aSceneRouter, aAudioBus, aCircleBondDB, aCircleBondSystem, aEnemyDB, optional, aDropTables, placeholder.
Confirm the current list and order in Project Settings, AutoLoad.

4) SAVE SYSTEM OVERVIEW
Each save slot is a JSON file at user://saves/slot_N.json. The SaveLoad singleton writes a wrapper with metadata and a payload captured by GameState. Continue chooses the slot with the highest ts value.

Typical file shape:
{
  "version": 1,
  "ts": 1730000000,
  "scene": "Main",
  "label": "05/10 — Saturday — Morning",
  "payload": {
    "scene": "Main",
    "label": "...",
    "player_name": "Player",
    "difficulty": "Normal",
    "calendar": {
      "date": {"year": 2025, "month": 5, "day": 10},
      "phase": 0,
      "weekday": 5
    }
  }
}

Notes:
* list_slots scans the saves directory for slot files and provides metadata for menus.
* delete_slot removes a given slot file.
* loaders validate JSON parse and expected fields, missing pieces are filled by GameState when possible.

5) MAIN MENU TABS, MVP SCOPE
Stats, shows player core stats, SXP, weekly fatigue.
Perks, 5 by 5 grid by stat tier, unlocks gated by stat level and perk points.
Items, inventory list from CSV with category filters and item inspect view.
Loadout, party and equipment slots, weapon, armor, head, foot, bracelet, shows derived stats and Sigils.
Bonds, Circle Bonds list and detail, shows CBXP totals and bond level, handles unknown and maxed states cleanly.
Outreach, quest log for Missions, Nodes, Mutual Aid, includes a dev button to advance the main event.
Dorms, dorm rooms and occupants, capacity summaries and detail view.
Calendar, planned month grid view with highlights for current day and events.
Index, codex with categories, Tutorials, Enemies, Past Missions, Locations, World Lore.
System, planned hub to access Save, Load, Settings, exit to Title.

6) CODE STYLE AND CONTRIBUTION GUIDELINES
* Typed GDScript, explicit variable and return types, warnings treated as errors.
* Defensive node access, use get_node_or_null, check has_method and has_signal.
* Do not use Node.get with default values, read properties directly or via typed getters.
* Connect each signal once, avoid duplicate connections.
* Clear anchors and expand flags on UI for correct scaling.
* Short docstring above every function explaining intent.
* Data‑driven approach, add new CSVs under data and follow existing loader patterns.
* Branch per feature, test save and load across versions, include edge cases and missing data.

7) DATA FILES, QUICK INDEX
* data,world,world_spots.csv, training spots and gates by phase, weekday, stats, items, flags.
* data,items,items.csv, all items and equipment definitions.
* data,circles, circles_rewards.csv and related files, ensure a reward_id column exists.
* data,progression,enemy_defs.csv, optional, EnemyDB logs a warning if missing.

8) ROADMAP, NEAR TERM
* Finish GameMenu shell, tab switching, pause behavior, polish.
* Wire System tab to Save, Load overlays and Settings.
* Expand Stats panel to include party summary and additional derived values.
* Implement item use and equip flows across Items and Loadout, finalize EquipmentSystem hooks.
* Flesh out Circle Bonds content and rewards, integrate events and duo skills where designed.
* Build Calendar tab grid, month navigation, event markers.
* Replace Index placeholders with real entries as content lands.
* Add tests for Stats, SaveLoad, Calendar, and UI refresh patterns, tighten performance on large lists.

9) LICENSE
TBD. Until a license file is added, treat the repository as proprietary or source‑available for review and contribution by permission. Ask the maintainer before reusing code elsewhere.

10) CONTACT AND NOTES
Open the project, run, and explore the panels. If a CSV is missing, the UI should fail gracefully and print a warning. When proposing code changes, always provide file paths, whether you want full replacement code or a patch, and node paths or a screenshot for safe signal wiring.
