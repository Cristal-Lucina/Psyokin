# CSV Data Architecture

## Philosophy: Data-Driven Design

Psyokin is built on a **CSV-driven architecture** that separates game data from code. This design philosophy enables:

- **Quick Iteration**: Modify game balance, add items, or tweak skills without touching code
- **Easy Balancing**: Adjust numbers in spreadsheets, save as CSV, and reload
- **Designer Empowerment**: Non-programmers can edit game content directly
- **Version Control Friendly**: CSVs diff well in git, making changes trackable
- **Modding Support**: Community members can create mods by editing CSVs

The core principle: **All you need to do is edit CSV files to adjust the game system.**

---

## The CSVLoader System

### How It Works

The `CSVLoader` (located at `scripts/core/CSVLoader.gd`) is a singleton that:

1. **Loads CSV files** and parses them into dictionaries
2. **Caches results** for performance (no repeated file I/O)
3. **Auto-detects types**: converts numbers to int/float automatically
4. **Keys by ID**: returns a dictionary indexed by a specified column (default: "id")

### CSVLoader API

```gdscript
# Load a CSV file, keyed by "id" column
var items = CSVLoader.load_csv("res://data/items/items.csv")
var bokken = items["WEA_001"]

# Load with a custom key column
var party = CSVLoader.load_csv("res://data/actors/party.csv", "actor_id")
var tessa = party["secret_girl"]

# Clear cache (useful for hot-reloading during development)
CSVLoader.clear_cache()

# Clear cache for a specific file
CSVLoader.clear_cache_for_path("res://data/items/items.csv")
```

### Type Auto-Detection

The CSVLoader automatically converts CSV strings to appropriate types:

| CSV Value | Converted To | Type |
|-----------|--------------|------|
| `"100"` | `100` | int |
| `"3.14"` | `3.14` | float |
| `"Fire"` | `"Fire"` | String |
| `""` | `""` | String (empty) |

### Key Column Detection

CSVLoader looks for a key column in this order:
1. The specified `key_column` parameter
2. A case-insensitive match of the key column
3. Common alternatives: `"id"`, `"actor_id"`, `"code"`, `"key"`, `"name"`

---

## CSV File Structure

### Directory Organization

```
data/
├── actors/          # Character and enemy definitions
├── circles/         # Social bonds and relationship data
├── combat/          # Combat mechanics (skills, status effects, etc.)
├── dorms/           # Dorm room and affinity system config
├── items/           # Equipment, consumables, and materials
├── progression/     # Leveling and enemy scaling
├── skills/          # Sigil and skill progression
└── world/           # World map and location data
```

---

## CSV Files Reference

### 1. Actors

#### `actors/party.csv`
Defines playable party members.

**Key Column**: `actor_id`

**Important Columns**:
- `actor_id`: Unique identifier (e.g., `secret_girl`, `best_friend`)
- `name`: Display name (e.g., `Tessa`, `Kai`)
- `level_start`: Starting level
- `start_brw`, `start_mnd`, `start_tpo`, `start_vtl`, `start_fcs`: Base stats
- `mind_type`: Elemental affinity (Fire, Water, Earth, Air, Void, Data, Omega)
- `start_sigils`: Semicolon-separated list of starting sigils
- `portrait`, `sprite`: Asset paths
- `dsi_*`: Stat growth multipliers (DSI = Derived Stat Increase)
- `burst_skill`: ID of burst ability
- `bestie_buff`, `rival_debuff`: Social link mechanics

**Example Row**:
```csv
secret_girl,Tessa,1,1,1,1,1,1,Air,,,,,,SIG_002,portraits/rhea.png,sprites/rhea.tres,TRUE,Mage archetype,1,3,2,2,2,,red_girl;scientist,ai_friend
```

#### `actors/enemies.csv`
Defines enemy units.

**Key Column**: `actor_id`

**Important Columns**:
- `actor_id`: Unique identifier
- `name`: Display name
- `level_start`: Base level
- `start_weapon`, `start_armor`, etc.: Equipment IDs
- `start_skills`: Semicolon-separated skill IDs
- `mind_type`: Elemental type
- `dsi_*`: Stat scaling (affects difficulty at higher levels)
- `item_drops`: Drop table reference
- `cred_range`: Credit reward range (e.g., `"10-20"`)
- `boss_tag`: TRUE/FALSE - is this a boss?
- `capture_tag`: Capture difficulty (Easy/Medium/Hard/None)
- `capture_resist`: Base capture resistance percentage
- `env_tag`: Environment type (Regular/Elite/Boss)

**Example Row**:
```csv
slime,Slime,1,1,1,1,3,1,,,,,,,FIRE_L1,Water,,,0.5,0.5,0.5,1,0.5,drop_table_slime,10-20,FALSE,Easy,10,Regular
```

---

### 2. Combat

#### `combat/skills.csv`
Defines all combat skills and spells.

**Key Column**: `skill_id`

**Important Columns**:
- `skill_id`: Unique skill ID (e.g., `FIRE_L1`, `WATER_L2`)
- `name`: Display name
- `school`: Magic school (Fire, Water, Earth, Air, Void, Data, Normal)
- `type`: Attack/Heal/Buff/Debuff
- `element`: Damage element
- `target`: Enemy/Enemies/Ally/Allies/Self/Party
- `power`: Base damage/healing
- `acc`: Accuracy percentage
- `cost_mp`: MP cost
- `cooldown`: Turns before reuse
- `uses_per_battle`: Limited uses (0 = unlimited)
- `aoe`: 0=single, 1=AoE
- `crit_bonus_pct`: Extra crit chance
- `scaling_brw`, `scaling_mnd`, `scaling_fcs`: Stat scaling multipliers
- `status_apply`: Status effect to apply
- `status_chance`: Chance to apply status (%)
- `duration`: Status duration in rounds

**Example Row**:
```csv
FIRE_L1,Fire Bolt,Fire,Attack,fire,Enemy,30,90,6,0,0,0,0,Basic single-target fire.,Burn,0,1,0,Burn,20,3
```

#### `combat/status_effects.csv`
Defines status ailments and buffs.

**Key Column**: `effect_id`

**Important Columns**:
- `effect_id`: Unique ID (e.g., `poison`, `attack_up`)
- `category`: ailment/buff/debuff
- `name`: Display name
- `default_duration`: Default turns active
- `magnitude`: Effect strength (% or flat value)
- `description`: User-facing description

**Example Row**:
```csv
poison,ailment,Poison,0,5,DoT 5% MaxHP/turn
```

#### `combat/mind_types.csv`
Defines elemental types and resistances.

**Key Column**: `mind_type_id`

**Important Columns**:
- `mind_type_id`: Element ID
- `name`: Display name
- `allowed_schools`: Semicolon-separated list of schools this type can use
- `weak_to`: Element this is weak against
- `resist_to`: Element this resists
- `desc`: Description

**Example Row**:
```csv
Fire,Fire,Fire;Normal,Water,Air,Hot-headed attunement.
```

#### `combat/burst_abilities.csv`
Defines team-based burst attacks.

**Key Column**: `burst_id`

**Important Columns**:
- `burst_id`: Unique ID
- `name`: Display name
- `participants`: Semicolon-separated actor IDs
- `unlock_condition`: Condition to unlock (e.g., `affinity_tier:2`)
- `burst_cost`: Resource cost
- `type`, `element`, `target`, `power`, `acc`: Standard combat stats
- `scaling_*`: Stat scaling
- `status_apply`, `status_chance`, `duration`: Status effects

**Example Row**:
```csv
BURST_HERO_TESSA,Dual Mind Storm,hero;secret_girl,affinity_tier:2,75,Attack,Air,Enemies,160,92,1,20,Hero and Tessa combine minds...,Burst;Duo;AoE,0.3,1.2,0.5,Confuse,50,3
```

---

### 3. Items

#### `items/items.csv`
Defines all items (weapons, armor, consumables, materials, etc.).

**Key Column**: `item_id`

**Important Columns**:
- `item_id`: Unique ID (e.g., `WEA_001`, `CON_001`)
- `name`: Display name
- `category`: Weapons/Armor/Consumables/Sigils/Materials/Gifts/Key/Bindings
- `equip_slot`: Weapon/Armor/Headwear/Footwear/Bracelet/Sigil/none
- `rarity`: Common/Uncommon/Rare/Epic/Legendary
- `buy_price`, `sell_price`: Shop prices
- `shop_tier`: What tier of shop sells this
- `sellable`: TRUE/FALSE
- `stack_max`: Max stack size
- `drop_source`: Where it drops from
- `short_description`, `full_description`: Descriptions
- **Equipment Stats**: `armor_flat`, `ward_flat`, `max_hp_boost`, `max_mp_boost`, `base_watk`, `base_acc`, `crit_bonus_pct`, `sigil_slots`, etc.
- **Consumable Fields**: `use_type` (battle/field/both), `targeting`, `battle_status_effect`, `field_status_effect`
- **Capture Items**: `capture_type`, `non_lethal`
- `gift_type`: For gift items

**Example Weapon**:
```csv
WEA_001,Bokken,Weapons,Weapon,Common,null,100,50,1,TRUE,1,shop_start,Starter gear,"Simple wooden practice sword","A wooden practice sword...",none,slash,null,null,null,null,null,null,null,null,3,80,null,1,null,FALSE,...
```

**Example Consumable**:
```csv
CON_001,Health Drink,Consumables,none,Common,null,30,15,1,TRUE,99,null,Basic heal.,Restores a bit of health.,...,none,...,both,Ally,null,null,Heal 50 HP,Heal 50 HP,1,...
```

---

### 4. Circles (Social Bonds)

#### `circles/circle_bonds.csv`
Defines relationship/social link system.

**Key Column**: `actor_id`

**Important Columns**:
- `actor_id`: Actor this bond belongs to
- `bond_name`: Display name
- `bond_layer`: Current progression layer (0-4)
- `love_interest`: Yes/No
- `poly_connects`: Semicolon-separated list of connected bonds
- `burst_unlocked`: Yes/No
- `gift_likes`, `gift_dislikes`: Gift preferences
- `bond_description`: Flavor text
- `story_points`: Current story state
- `reward_outer`, `reward_middle`, `reward_inner`, `reward_core`: Layer-based rewards

**Example Row**:
```csv
secret_girl,Tessa,0,Yes,ai_friend;red_girl;scientist,No,tech,flowers,Mysterious ally with hidden agenda;...,Met; first hangout queued.,consumable:starter_pack;unlock:psyokin_growth_basic,...
```

#### `circles/circles_events.csv`
Defines social events and scenes.

**Key Column**: (varies - likely `event_id`)

---

### 5. Dorms

#### `dorms/affinity_power_config.csv`
Configures affinity power mechanics.

**Key Column**: (likely `tier` or `level`)

#### `dorms/room_config.csv`
Defines dorm room upgrades and configurations.

**Key Column**: (likely `room_id`)

---

### 6. Progression

#### `progression/enemy_defs.csv`
Enemy scaling definitions for progression.

**Key Column**: (likely `enemy_id` or `tier`)

---

### 7. Skills

#### `skills/skills.csv`
Already covered in Combat section (same file).

#### `skills/sigil_holder.csv`
Defines sigil socket/holder system.

**Key Column**: (likely `holder_id` or `slot_id`)

#### `skills/sigil_xp_table.csv`
XP progression for sigils.

**Key Column**: (likely `level` or `sigil_id`)

---

### 8. World

#### `world/world_spots.csv`
Defines world map locations.

**Key Column**: (likely `spot_id` or `location_id`)

---

## How to Add New Content

### Adding a New Item

1. **Open** `data/items/items.csv` in your preferred CSV editor (Excel, Google Sheets, LibreOffice Calc)
2. **Add a new row** with a unique `item_id`
3. **Fill in the columns**:
   - Core: `item_id`, `name`, `category`, `rarity`
   - Pricing: `buy_price`, `sell_price`, `shop_tier`
   - Descriptions: `short_description`, `full_description`
   - Stats: Equipment stats or consumable effects
4. **Save as CSV** (ensure it's UTF-8 encoded, comma-delimited)
5. **Reload in-game** (or restart)

**Example**: Adding a new healing item
```csv
CON_099,Mega Heal,Consumables,none,Rare,null,500,250,3,TRUE,99,null,Massive heal.,Restores lots of HP.,A powerful healing item that restores 500 HP.,none,null,null,null,null,null,null,null,null,null,null,null,null,null,null,FALSE,null,null,null,null,null,both,Ally,null,Heal 500 HP,Heal 500 HP,Heal 500 HP,1,null,null,null,null,null,null,null,null,null,null
```

### Adding a New Skill

1. **Open** `data/skills/skills.csv`
2. **Add a new row**:
   - `skill_id`: Unique ID (e.g., `FIRE_L5`)
   - `name`: Display name
   - `school`: Fire/Water/Earth/Air/Void/Data/Normal
   - `type`: Attack/Heal/Buff/Debuff
   - `power`, `acc`, `cost_mp`: Core stats
   - `scaling_*`: Which stats affect damage
   - `status_apply`, `status_chance`: Optional status effect
3. **Save the file**
4. **Assign to a character** via `actors/party.csv` or `actors/enemies.csv`

**Example**: Adding a high-tier fire skill
```csv
FIRE_L5,Inferno Apocalypse,Fire,Attack,fire,Enemies,150,82,30,0,0,1,15,Ultimate fire devastation.,Burn;Stagger;AOE,0,1.5,0,Burn,60,4
```

### Adding a New Party Member

1. **Open** `data/actors/party.csv`
2. **Add a new row**:
   - `actor_id`: Unique ID (e.g., `new_hero`)
   - `name`: Display name
   - `level_start`: Starting level
   - Base stats: `start_brw`, `start_mnd`, etc.
   - `mind_type`: Elemental type
   - `start_sigils`: Initial sigils (semicolon-separated)
   - `portrait`, `sprite`: Asset paths
   - DSI stats: Growth multipliers
3. **Save the file**
4. **Create social bond** in `circles/circle_bonds.csv` (optional)

### Adding a New Enemy

1. **Open** `data/actors/enemies.csv`
2. **Add a new row** (similar to party member)
3. **Set difficulty values**:
   - `dsi_*`: Stat scaling (0.5 = weak, 1 = normal, 2 = strong)
   - `capture_resist`: Higher = harder to capture
   - `boss_tag`: TRUE for bosses
4. **Assign loot**: `item_drops`, `cred_range`

### Adding a New Status Effect

1. **Open** `data/combat/status_effects.csv`
2. **Add a new row**:
   - `effect_id`: Unique ID (lowercase, e.g., `frozen`)
   - `category`: ailment/buff/debuff
   - `name`: Display name
   - `default_duration`: Turns active
   - `magnitude`: Effect strength
   - `description`: What it does
3. **Reference it** in skills/items via `status_apply` column

---

## Best Practices

### CSV Formatting Rules

1. **Use UTF-8 encoding** (no BOM)
2. **Comma-delimited** (not semicolon or tab)
3. **Semicolons for lists** (e.g., `Fire;Water;Earth`)
4. **Empty cells are valid** (treated as empty strings or 0)
5. **Quotes for long text** (descriptions with commas)
6. **Consistent IDs**: Use prefixes like `WEA_`, `CON_`, `FIRE_L1`

### ID Naming Conventions

| Category | Prefix | Example |
|----------|--------|---------|
| Weapons | `WEA_` | `WEA_001` |
| Armor | `ARM_` | `ARM_001` |
| Headwear | `HEA_` | `HEA_001` |
| Footwear | `FTW_` | `FTW_001` |
| Bracelets | `BRA_` | `BRA_001` |
| Sigils | `SIG_` | `SIG_002` |
| Consumables | `CON_` | `CON_001` |
| Healing | `HEAL_` | `HEAL_001` |
| Health % | `HP_` | `HP_001` |
| MP % | `MP_` | `MP_001` |
| Revives | `REV_` | `REV_001` |
| Buffs | `BUFF_` | `BUFF_001` |
| Cures | `CURE_` | `CURE_001` |
| Battle Items | `BAT_` | `BAT_001` |
| Tools | `TOOL_` | `TOOL_001` |
| Materials | `MAT_` | `MAT_001` |
| Gifts | `GIF_` | `GIF_001` |
| Key Items | `KEY_` | `KEY_001` |
| Bindings | `BIND_` | `BIND_001` |
| Skills | `ELEMENT_L#` | `FIRE_L1`, `WATER_L2` |
| Burst | `BURST_` | `BURST_HERO_TESSA` |

### Data Integrity

1. **No duplicate IDs**: Each ID must be unique within its file
2. **Reference valid IDs**: If a column references another CSV (e.g., `start_sigils` references `items.csv`), ensure those IDs exist
3. **Consistent naming**: Use the same element names everywhere (e.g., always "Fire", not "fire" or "FIRE")
4. **Test after changes**: Load the game and verify your changes work

### Version Control

1. **Commit CSVs separately**: Don't bundle CSV changes with code changes
2. **Clear commit messages**: "Added Fire L5 skill" is better than "Updated skills.csv"
3. **Review diffs**: GitHub/Git diffs for CSVs show exactly what changed

---

## Common Workflows

### Balancing Pass

1. **Export to spreadsheet** (open CSV in Excel/Sheets)
2. **Adjust values** (e.g., reduce all skill costs by 10%)
3. **Save as CSV**
4. **Test in-game**
5. **Iterate until balanced**

### Adding a New Equipment Set

1. **Plan the set**: List items (weapon, armor, head, foot)
2. **Add each item** to `items/items.csv` with matching `set_id`
3. **Define set bonuses** (if system supports it, or via code)
4. **Test equipping all pieces**

### Creating a New Boss

1. **Add enemy row** in `actors/enemies.csv`
   - Set `boss_tag: TRUE`
   - High stats, multiple skills
2. **Create loot table** (reference in `item_drops`)
3. **Add burst ability** in `combat/burst_abilities.csv` (if boss uses one)
4. **Test in combat**

### Hot-Reloading During Development

If you're iterating rapidly:

1. **Edit CSV**
2. **In-game console** (or debug menu):
   ```gdscript
   CSVLoader.clear_cache()
   # Then reload the system that uses that CSV
   ```
3. **Test immediately**

---

## Advanced: Extending the System

### Adding a New CSV File

1. **Create the file** in appropriate `data/` subdirectory
2. **Define columns** (first row is header)
3. **Choose a key column** (unique identifier)
4. **Load in code**:
   ```gdscript
   var my_data = CSVLoader.load_csv("res://data/my_category/my_file.csv", "my_id")
   var item = my_data["some_id"]
   ```

### Custom Data Types

If you need complex data (arrays, nested objects):

- **Use semicolons** for simple lists: `Fire;Water;Earth`
- **Parse in code**: Split on `;` and process
- **Alternative**: Use JSON strings in CSV cells (parse with `JSON.parse()`)

**Example**:
```csv
complex_config,"{""values"":[1,2,3],""flags"":{""active"":true}}"
```

### Localization

For multi-language support:

1. **Create locale-specific CSVs**: `items_en.csv`, `items_es.csv`, `items_jp.csv`
2. **Load based on locale**:
   ```gdscript
   var locale = OS.get_locale().substr(0, 2)  # "en", "es", "jp"
   var items = CSVLoader.load_csv("res://data/items/items_%s.csv" % locale)
   ```

---

## Troubleshooting

### "Key column not found"

**Problem**: CSVLoader can't find the specified key column.

**Solution**:
- Check the first row (header) for exact column name
- Ensure no extra spaces: `actor_id` not `actor_id `
- Try auto-detection by using common names: `id`, `actor_id`, `code`, etc.

### "Item not loading"

**Problem**: Added a row but it doesn't appear in-game.

**Checklist**:
1. Is the `item_id` unique?
2. Is the CSV properly formatted (commas, not tabs)?
3. Did you save the file?
4. Did you clear cache? `CSVLoader.clear_cache()`
5. Is the file path correct in your code?

### "Numbers treated as strings"

**Problem**: CSV values like "100" aren't converting to integers.

**Solution**: CSVLoader auto-converts. If it's not working:
- Check for extra spaces: `" 100 "` → `"100"`
- Ensure no special characters: `"100,"` won't convert
- Verify CSVLoader is using `_auto()` (it should by default)

### "Semicolon-separated lists not working"

**Problem**: Lists like `Fire;Water` aren't parsing.

**Solution**: CSVLoader doesn't auto-split lists. You must split in code:
```gdscript
var schools = row["allowed_schools"].split(";")
```

---

## Summary: The Power of CSV-Driven Design

By keeping all game data in CSV files, you achieve:

- **Rapid prototyping**: Test new ideas in minutes, not hours
- **Designer autonomy**: Balance without waiting for programmers
- **Clean separation**: Data changes don't pollute code history
- **Easy debugging**: Open a CSV, find the problem, fix it
- **Community mods**: Players can create content packs

**Remember**: The CSVLoader handles the hard part. You just edit the files and reload.

---

## Quick Reference Card

| Task | File | Key Column |
|------|------|------------|
| Add item | `items/items.csv` | `item_id` |
| Add skill | `skills/skills.csv` | `skill_id` |
| Add party member | `actors/party.csv` | `actor_id` |
| Add enemy | `actors/enemies.csv` | `actor_id` |
| Add status effect | `combat/status_effects.csv` | `effect_id` |
| Add mind type | `combat/mind_types.csv` | `mind_type_id` |
| Add burst ability | `combat/burst_abilities.csv` | `burst_id` |
| Add social bond | `circles/circle_bonds.csv` | `actor_id` |

**CSVLoader Methods**:
```gdscript
CSVLoader.load_csv(path, key_column = "id")  # Load and cache
CSVLoader.clear_cache()                       # Clear all cached CSVs
CSVLoader.clear_cache_for_path(path)         # Clear specific file
```

---

**That's it!** Edit CSVs, save, and watch your game world expand. The system handles the rest.
