# Psyokin Project Context

**Read this file at the start of every Claude Code session**

## Quick Reference

- **Engine**: Godot 4.5.1
- **Genre**: Turn-based JRPG with visual novel elements
- **Docs Location**: `docs/` folder
- **Viewport**: 1280x720 with integer scaling mode

## Key Documentation Files

- `docs/COMBAT_SYSTEM.md` - Complete combat mechanics
- `docs/EVENT_DIALOGUE_SYSTEM.md` - Event & dialogue system (with Quick Start Guide)
- `docs/CSV_DATA_REFERENCE.md` - All CSV file structures
- `docs/STATS_AND_BONDS.md` - Progression systems
- `docs/psyokin-jrpg.skill` - Comprehensive code patterns

## Core Systems (Autoloads at /root/)

```
aBattleManager         # Combat orchestrator
aCombatProfileSystem   # HP/MP management
aStatsSystem           # BRW/MND/TPO/VTL/FCS, SXP, fatigue
aAffinitySystem        # AXP combat bonuses
aCircleBondSystem      # BXP social progression
aGameState             # Party, HP/MP persistence
aCalendarSystem        # Date/time, signals
aEquipmentSystem       # Gear management
aSigilSystem           # Skill management
aMoralitySystem        # Capture/kill tracking
aEventManager          # Event triggers
aDialogueManager       # Branching dialogue
aMinigameManager       # Battle minigames
aPanelManager          # UI navigation
aCSVLoader             # Data loading
```

## Project Structure

```
/
├── docs/               # All documentation
├── data/               # CSV data files
│   ├── actors/         # party.csv, enemies.csv
│   ├── circles/        # bonds, events
│   ├── combat/         # bursts, types, status
│   ├── items/          # items.csv
│   └── skills/         # skills.csv, sigils
├── scenes/             # Godot scenes
│   ├── battle/         # Combat scenes
│   ├── overworld/      # World navigation
│   └── ui/             # UI panels
└── scripts/            # GDScript code
```

## When Working On:

**Combat** → Read `docs/COMBAT_SYSTEM.md`
**Dialogue** → Read `docs/EVENT_DIALOGUE_SYSTEM.md` (section 5: Quick Start Guide)
**CSV Data** → Read `docs/CSV_DATA_REFERENCE.md`
**Stats/Bonds** → Read `docs/STATS_AND_BONDS.md`
**Code Patterns** → Read `docs/psyokin-jrpg.skill`

## Common Commands

```bash
# Start fresh session with context
cat PROJECT_CONTEXT.md
cat docs/psyokin-jrpg.skill

# Search for autoload usage
grep -r "aBattleManager" scripts/

# Find CSV references
grep -r "CSVLoader" scripts/
```

## Remember

1. All content in CSV, logic in GDScript
2. Use signals for system communication
3. Check fatigue before awarding SXP
4. Save HP/MP after battles
5. Use NavState pattern for panels
6. Document all new systems
