# EVENT & DIALOGUE SYSTEM DOCUMENTATION

## Table of Contents
1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Event System](#event-system)
4. [Dialogue System](#dialogue-system)
5. [Dialogue System Quick Start Guide](#dialogue-system-quick-start-guide)
6. [Emoji & Expression System](#emoji--expression-system)
7. [NPC Location Tracking](#npc-location-tracking)
8. [Mission System](#mission-system)
9. [Item Location System](#item-location-system)
10. [Shop System](#shop-system)
11. [Morality-Based NPC Reactions](#morality-based-npc-reactions)
12. [Monthly Critical Events](#monthly-critical-events)
13. [Localization & Multi-Language Support](#localization--multi-language-support)
14. [CSV Data Formats](#csv-data-formats)
15. [Integration Points](#integration-points)

---

## Overview

Psyokin uses a **CSV-driven event and dialogue system** to manage all narrative content, NPC interactions, and world state. This design enables:

- **Multi-language support** via separate dialogue CSV files per language
- **Data-driven content** that can be edited without code changes
- **Branching dialogue paths** based on player choices and game state
- **Dynamic NPC behavior** tied to calendar, morality, and story progression
- **Scalable event management** for monthly critical events and mission triggers
- **Flexible world tracking** for NPCs, items, and shops across the overworld

### Core Features

- **Event System**: Calendar-based and trigger-based events stored in CSV
- **Dialogue System**: Branching conversations with choice nodes and conditions
- **Emoji System**: Visual expressions displayed above character heads
- **NPC Tracking**: Calendar-aware location system (where NPCs are each day)
- **Mission System**: Quest definitions with objectives, rewards, and locations
- **Item Locations**: Overworld item placements defined in CSV
- **Shop System**: Dynamic shop inventories based on story progression
- **Morality Reactions**: NPC behavior changes based on player morality score
- **Monthly Events**: Critical story events each month with failure conditions

---

## System Architecture

### Core Components

| Component | Path | Purpose |
|-----------|------|---------|
| **EventManager** | `/root/aEventManager` | Manages event triggers, execution, and calendar-based event scheduling |
| **DialogueManager** | `/root/aDialogueManager` | Handles dialogue playback, branching logic, and choice processing |
| **DialogueUI** | `scenes/dialogue/DialogueBox.tscn` | Visual dialogue box with portrait, text, and choice buttons |
| **EmojiSystem** | `/root/aEmojiSystem` | Displays emojis above character heads in overworld |
| **NPCLocationSystem** | `/root/aNPCLocationSystem` | Tracks NPC positions by calendar day and time |
| **MissionSystem** | `/root/aMissionSystem` | Manages active missions, objectives, and completion tracking |
| **ItemLocationSystem** | `/root/aItemLocationSystem` | Tracks overworld item spawns and collection state |
| **ShopSystem** | `/root/aShopSystem` | Manages shop inventories and availability |
| **MoralitySystem** | `/root/aMoralitySystem` | Tracks player morality and provides NPC reaction context |
| **CalendarSystem** | `/root/aCalendarSystem` | Manages in-game date/time and triggers monthly events |
| **LocalizationManager** | `/root/aLocalizationManager` | Loads language-specific CSV files and provides translated text |

### Dependency Flow

```
CalendarSystem (Date/Time)
    ↓
EventManager (Triggers)
    ↓
DialogueManager (Execution) ←→ LocalizationManager (Translation)
    ↓                              ↓
DialogueUI (Display)          NPCLocationSystem (NPC placement)
    ↓                              ↓
Player Choices                 EmojiSystem (Expressions)
    ↓
MissionSystem / MoralitySystem / GameState (State Changes)
```

### CSV File Structure

All CSV files stored in `data/csv/`:

```
data/csv/
├── events/
│   ├── calendar_events.csv        # Monthly/daily scheduled events
│   ├── trigger_events.csv         # Location/condition-based events
│   └── critical_monthly.csv       # Required monthly story events
├── dialogue/
│   ├── en/                        # English dialogue
│   │   ├── main_story.csv
│   │   ├── npcs.csv
│   │   └── side_quests.csv
│   ├── es/                        # Spanish dialogue
│   ├── fr/                        # French dialogue
│   └── jp/                        # Japanese dialogue
├── npcs/
│   ├── npc_locations.csv          # NPC calendar-based positions
│   ├── npc_schedules.csv          # Daily schedules per NPC
│   └── npc_reactions.csv          # Morality-based reaction variants
├── missions/
│   ├── mission_definitions.csv    # Mission metadata
│   ├── mission_objectives.csv     # Objective definitions
│   └── mission_rewards.csv        # Rewards per mission
├── items/
│   ├── item_locations.csv         # Overworld item placements
│   └── collectibles.csv           # One-time collectibles
└── shops/
    ├── shop_definitions.csv       # Shop metadata
    ├── shop_inventory.csv         # Base shop inventories
    └── shop_progression.csv       # Story-gated shop unlocks
```

---

## Event System

### Event Types

| Type | Trigger | Description |
|------|---------|-------------|
| **Calendar Event** | Specific date/time | Events that occur on exact calendar days |
| **Trigger Event** | Location + Condition | Events triggered by player entering locations |
| **Critical Event** | Monthly deadline | Required story events (fail = game over) |
| **Mission Event** | Mission progress | Events triggered by mission completion/failure |
| **Morality Event** | Morality threshold | Events unlocked/changed by morality level |

### Event Flow

```
1. EVENT_CHECK
   ├── CalendarSystem emits day_advanced signal
   ├── EventManager checks calendar_events.csv for current date
   ├── Player enters location trigger
   └── EventManager checks trigger_events.csv for conditions

2. EVENT_TRIGGER
   ├── Load event definition from CSV
   ├── Check prerequisites (flags, morality, missions, etc.)
   ├── If conditions met → Queue event
   └── If conditions not met → Skip

3. EVENT_EXECUTION
   ├── Transition to event scene (if needed)
   ├── Play cutscene/animation (if defined)
   ├── Launch DialogueManager with dialogue_id
   ├── Process dialogue choices
   └── Apply event outcomes (flags, items, missions, etc.)

4. EVENT_COMPLETION
   ├── Mark event as completed (GameState.completed_events)
   ├── Update story flags
   ├── Emit event_completed signal
   └── Resume player control
```

### Event Priority System

Events are prioritized when multiple trigger simultaneously:

1. **Critical Events** (monthly deadlines) - highest priority
2. **Story Events** (main narrative progression)
3. **Mission Events** (active mission triggers)
4. **NPC Events** (dialogue interactions)
5. **Environmental Events** (location discoveries, item finds)

### Event Conditions

Events can be gated by multiple conditions:

- **Date/Time**: `month >= 5`, `day == 15`, `time_of_day == "evening"`
- **Story Flags**: `flag_met_npc_x == true`, `chapter >= 3`
- **Morality**: `morality >= 50`, `morality < -30`
- **Missions**: `mission_id_completed == "main_001"`, `active_mission == "side_05"`
- **Party**: `has_party_member("alice")`, `party_size >= 2`
- **Inventory**: `has_item("KeyCard_A")`, `item_count("Bind_Basic") >= 3`
- **Combat**: `battles_won >= 10`, `enemies_captured >= 5`

---

## Dialogue System

### Dialogue Architecture

The dialogue system uses a **node-based branching structure** with support for:
- Linear dialogue sequences
- Player choice branches (2-4 options)
- Conditional dialogue variants (based on flags, morality, etc.)
- Auto-branching (NPC reacts differently based on game state)
- Looping dialogue (repeatable conversations)

### Dialogue Node Types

| Node Type | CSV Flag | Description |
|-----------|----------|-------------|
| **Text** | `TEXT` | Standard dialogue line (speaker + text) |
| **Choice** | `CHOICE` | Player choice node (branches to different paths) |
| **Branch** | `BRANCH` | Auto-branch based on condition (no player input) |
| **Action** | `ACTION` | Trigger game action (give item, set flag, start battle, etc.) |
| **End** | `END` | Dialogue ends, return to gameplay |
| **Jump** | `JUMP` | Jump to different dialogue node/sequence |

### Dialogue Flow

```
1. DIALOGUE_START
   ├── DialogueManager.start_dialogue(dialogue_id, npc_id)
   ├── Load dialogue CSV from LocalizationManager (current language)
   ├── Parse dialogue tree starting at root node
   └── Emit dialogue_started signal

2. DIALOGUE_DISPLAY
   ├── DialogueUI shows character portrait
   ├── Display speaker name
   ├── Typewriter effect for text (configurable speed)
   ├── Wait for player input (A button to advance)
   └── If choices → Show choice buttons

3. DIALOGUE_CHOICE
   ├── Display 2-4 choice buttons
   ├── Player selects choice (A button)
   ├── Record choice in GameState.dialogue_choices
   ├── Branch to next node based on choice_id
   └── Some choices affect morality/flags

4. DIALOGUE_ACTION
   ├── Execute action node (give item, set flag, etc.)
   ├── Update GameState accordingly
   ├── Continue to next node
   └── Actions can trigger events/battles/scenes

5. DIALOGUE_END
   ├── Fade out dialogue box
   ├── Return control to player
   ├── Emit dialogue_ended signal
   └── Resume overworld gameplay
```

### Branching Logic

**Choice-Based Branching**:
```
Node 1: "Do you want to help me?"
  → Choice A: "Yes, I'll help." → Node 2A (accept quest)
  → Choice B: "No, sorry." → Node 2B (decline quest)
  → Choice C: "What's in it for me?" → Node 2C (negotiate)
```

**Conditional Branching**:
```
Node 1: Check player morality
  → If morality >= 30 → Node 2A (friendly greeting)
  → If morality <= -30 → Node 2B (hostile greeting)
  → Else → Node 2C (neutral greeting)
```

**Flag-Based Branching**:
```
Node 1: Check if player has met NPC before
  → If flag_met_alice == true → Node 2A ("Good to see you again!")
  → Else → Node 2B ("Hello, I'm Alice. Nice to meet you!")
```

### Dialogue Variables

Dialogue text supports variable substitution:

- `{player_name}` - Player character name
- `{morality}` - Current morality score
- `{date}` - Current in-game date
- `{item_name}` - Referenced item name
- `{npc_name}` - Current NPC speaker name
- `{choice_X}` - Previous choice made at node X

**Example**:
```
"Hello {player_name}, I heard you chose to {choice_5} yesterday. That takes courage."
```

### Repeatable Dialogue

NPCs can have multiple dialogue states:

- **First Meeting**: Plays once, sets flag `met_npc_X = true`
- **Repeatable Default**: Plays every time after first meeting
- **Event-Specific**: Plays during active events/missions
- **Post-Event**: Plays after event completion
- **Time-Specific**: Different dialogue based on time of day

---

## Dialogue System Quick Start Guide

This section provides practical examples and step-by-step walkthroughs for implementing common dialogue patterns.

### Example 1: Simple Linear Dialogue

**Goal**: Create a basic conversation with no choices.

**CSV Structure**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
intro_alice,1,TEXT,Alice,"Hi! I'm Alice. Welcome to the academy!",,,2,
intro_alice,2,TEXT,Alice,"This place can be overwhelming at first.",,,3,
intro_alice,3,TEXT,Alice,"Let me know if you need anything!",,,END,
```

**Flow**:
1. Player interacts with Alice
2. DialogueManager.start_dialogue("intro_alice", "npc_alice")
3. Node 1 displays → Player presses A
4. Node 2 displays → Player presses A
5. Node 3 displays → Player presses A
6. Dialogue ends, returns to gameplay

**Result**: Simple 3-line conversation that always plays the same way.

---

### Example 2: Player Choices with Consequences

**Goal**: Player makes a choice that affects morality and mission availability.

**CSV Structure**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
mission_cat,1,TEXT,Alice,"My cat is missing! Will you help me find her?",,,2,
mission_cat,2,CHOICE,Alice,"Please, I'm worried sick!","Yes, I'll help|No, sorry|What's the reward?","3|5|7",,
mission_cat,3,TEXT,Alice,"Thank you so much! Her name is Whiskers.",,,4,"morality:+3"
mission_cat,4,ACTION,,,,,,,"start_mission:side_cat_rescue;set_flag:accepted_cat_mission;show_emoji:npc_alice:happy:2.0"
mission_cat,4b,TEXT,Alice,"I last saw her near the park. Please hurry!",,,END,
mission_cat,5,TEXT,Alice,"Oh... I understand.",,,6,"morality:-2"
mission_cat,6,ACTION,,,,,,,"show_emoji:npc_alice:sad:2.0;set_flag:declined_cat_mission"
mission_cat,6b,TEXT,Alice,"I'll... I'll look by myself then.",,,END,
mission_cat,7,TEXT,Alice,"Really? You want a reward for helping?",,,8,
mission_cat,8,TEXT,Alice,"Fine. I'll give you 500 Creds if you find her.",,,9,
mission_cat,9,CHOICE,Alice,"Is that enough?","Okay, I'll do it|Still not interested","3|5",,
```

**Flow Diagram**:
```
Node 1: Alice asks for help
   ↓
Node 2: CHOICE
   ├─ "Yes, I'll help" (morality +3)
   │    ↓
   │  Node 3: Alice thanks player
   │    ↓
   │  Node 4: ACTION (start mission, set flag, show 😊)
   │    ↓
   │  Node 4b: Alice gives hint
   │    ↓
   │  END
   │
   ├─ "No, sorry" (morality -2)
   │    ↓
   │  Node 5: Alice disappointed
   │    ↓
   │  Node 6: ACTION (show 😢, set flag)
   │    ↓
   │  Node 6b: Alice accepts rejection
   │    ↓
   │  END
   │
   └─ "What's the reward?"
        ↓
      Node 7: Alice surprised
        ↓
      Node 8: Offers 500 Creds
        ↓
      Node 9: CHOICE again
        ├─ "Okay, I'll do it" → Node 3
        └─ "Still not interested" → Node 5
```

**Key Points**:
- Choice nodes branch to different paths
- Actions in node 3 and 5 affect morality (morality:+3, morality:-2)
- ACTION nodes trigger game events (start mission, show emoji)
- Some paths loop back (node 9 can return to node 3)

---

### Example 3: Conditional Branching Based on Morality

**Goal**: NPC greets player differently based on morality level.

**CSV Structure**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
shop_greet,1,BRANCH,,,,"2|3|4","morality>=50|morality<=-30|default",
shop_greet,2,TEXT,Shopkeeper,"Welcome back, hero! Everything is 10% off for you today!",,,5,"show_emoji:npc_shop:happy:2.0"
shop_greet,3,TEXT,Shopkeeper,"You again? I'm watching you. Don't try anything.",,,5,"show_emoji:npc_shop:angry:2.0"
shop_greet,4,TEXT,Shopkeeper,"Hello. What can I get you?",,,5,
shop_greet,5,ACTION,,,,,,,"open_shop:general_store"
```

**Flow**:
```
Node 1: BRANCH (auto-check morality, no player input)
   ├─ If morality >= 50 → Node 2 (hero greeting + 😊 + discount)
   ├─ If morality <= -30 → Node 3 (hostile greeting + 😡)
   └─ Else (default) → Node 4 (neutral greeting)
   ↓
Node 5: ACTION (open shop interface)
```

**Morality Tiers**:
- **High (≥50)**: Friendly, discount applied
- **Low (≤-30)**: Hostile, no discount (or price increase)
- **Neutral**: Standard greeting

**Result**: Same shop, different experience based on player's moral choices.

---

### Example 4: Flag-Based Repeatable Dialogue

**Goal**: NPC says different things on first meeting vs. subsequent visits.

**CSV Structure**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
npc_bob,1,BRANCH,,,,"2|4","flag_met_bob==false|flag_met_bob==true",
npc_bob,2,TEXT,Bob,"Hey there! I'm Bob. Nice to meet you!",,,3,
npc_bob,3,ACTION,,,,,,,"set_flag:met_bob:true"
npc_bob,3b,TEXT,Bob,"If you ever need training tips, come find me!",,,END,
npc_bob,4,TEXT,Bob,"Back for more training, {player_name}?",,,5,
npc_bob,5,CHOICE,Bob,"What do you want to work on?","Strength training|Speed training|Just chatting","6|7|8",,
npc_bob,6,ACTION,,,,,,,"activity:strength_training"
npc_bob,7,ACTION,,,,,,,"activity:speed_training"
npc_bob,8,TEXT,Bob,"Alright, catch you later!",,,END,
```

**Flow**:
```
Node 1: BRANCH (check flag_met_bob)
   ├─ First time (flag == false)
   │    ↓
   │  Node 2: "Nice to meet you!"
   │    ↓
   │  Node 3: ACTION (set flag_met_bob = true)
   │    ↓
   │  Node 3b: "Come find me!"
   │    ↓
   │  END
   │
   └─ Repeat visit (flag == true)
        ↓
      Node 4: "Back for more training?"
        ↓
      Node 5: CHOICE (training options)
        ├─ Strength → Node 6 (activity)
        ├─ Speed → Node 7 (activity)
        └─ Chat → Node 8 (goodbye)
```

**Key Points**:
- First visit: Introduction + sets flag
- Subsequent visits: Skip intro, go straight to options
- Uses `{player_name}` variable for personalization

---

### Example 5: Multi-Step Quest with Item Check

**Goal**: NPC asks for an item, player must return with it.

**CSV Structure**:

**First Conversation (Request)**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
quest_book,1,TEXT,Professor,"I need a specific book from the library.",,,2,
quest_book,2,TEXT,Professor,"Can you fetch 'Advanced Mind Theory' for me?",,,3,
quest_book,3,CHOICE,Professor,"It should be on the top shelf.","I'll get it|Not right now","4|5",,
quest_book,4,ACTION,,,,,,,"start_mission:fetch_book;set_flag:book_quest_active"
quest_book,4b,TEXT,Professor,"Great! I'll be here waiting.",,,END,
quest_book,5,TEXT,Professor,"Alright, but I really need it soon!",,,END,
```

**Second Conversation (Return with item)**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
quest_book_return,1,BRANCH,,,,"2|4","has_item:Advanced_Mind_Theory|default",
quest_book_return,2,TEXT,Professor,"Ah, you found it! Thank you!",,,3,
quest_book_return,3,ACTION,,,,,,,"remove_item:Advanced_Mind_Theory;give_item:Potion:5;add_creds:300;complete_mission:fetch_book;morality:+2"
quest_book_return,3b,TEXT,Professor,"Here, take these potions as thanks!",,,END,
quest_book_return,4,TEXT,Professor,"Still looking for that book?",,,5,
quest_book_return,5,TEXT,Professor,"It's 'Advanced Mind Theory' - top shelf in the library.",,,END,
```

**Flow**:
```
=== FIRST VISIT ===
Professor asks for book
   ↓
Player accepts quest
   ↓
Mission activates
   ↓
END

=== PLAYER FINDS BOOK IN LIBRARY ===
(ItemLocationSystem gives player book)

=== RETURN TO PROFESSOR ===
Node 1: BRANCH (check has_item:Advanced_Mind_Theory)
   ├─ Has book → Node 2 ("You found it!")
   │    ↓
   │  Node 3: ACTION
   │    - Remove book from inventory
   │    - Give 5 potions
   │    - Give 300 Creds
   │    - Complete mission
   │    - Morality +2
   │    ↓
   │  Node 3b: "Thanks!"
   │    ↓
   │  END
   │
   └─ No book → Node 4 ("Still looking?")
        ↓
      Node 5: Reminder hint
        ↓
      END
```

**Key Points**:
- Uses `has_item` condition to check inventory
- Multiple rewards in single ACTION node
- Quest progresses through multiple dialogue interactions

---

### Example 6: Mission Progress Check

**Goal**: NPC reacts to active mission objectives.

**CSV Structure**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
npc_witness,1,BRANCH,,,,"2|4|6","mission_active:investigate_theft and objective_incomplete:talk_to_witness|mission_active:investigate_theft and objective_complete:talk_to_witness|default",
npc_witness,2,TEXT,Witness,"You're investigating the theft? I saw something!",,,3,
npc_witness,3,ACTION,,,,,,,"complete_objective:talk_to_witness;set_flag:witness_testimony"
npc_witness,3b,TEXT,Witness,"I saw a figure in a red jacket running away!",,,END,
npc_witness,4,TEXT,Witness,"I hope that tip helped with your investigation!",,,END,
npc_witness,6,TEXT,Witness,"Beautiful day today, isn't it?",,,END,
```

**Flow**:
```
Node 1: BRANCH (check mission state)
   ├─ Mission active + objective incomplete
   │    ↓
   │  Node 2: "I saw something!"
   │    ↓
   │  Node 3: ACTION (complete objective, set flag)
   │    ↓
   │  Node 3b: Gives testimony
   │    ↓
   │  END
   │
   ├─ Mission active + objective already complete
   │    ↓
   │  Node 4: "Hope that helped!"
   │    ↓
   │  END
   │
   └─ No mission active
        ↓
      Node 6: Generic dialogue
        ↓
      END
```

**Key Points**:
- Checks both mission status AND objective status
- Dialogue is context-aware
- Once objective complete, dialogue changes

---

### Common Action Types

Actions are executed in ACTION nodes and modify game state:

| Action Type | Syntax | Example |
|-------------|--------|---------|
| **Start Mission** | `start_mission:<mission_id>` | `start_mission:side_cat_rescue` |
| **Complete Mission** | `complete_mission:<mission_id>` | `complete_mission:fetch_book` |
| **Complete Objective** | `complete_objective:<obj_id>` | `complete_objective:talk_to_witness` |
| **Set Flag** | `set_flag:<flag_name>:<value>` | `set_flag:met_alice:true` |
| **Give Item** | `give_item:<item_id>:<quantity>` | `give_item:Potion:5` |
| **Remove Item** | `remove_item:<item_id>:<quantity>` | `remove_item:KeyCard_A:1` |
| **Add Creds** | `add_creds:<amount>` | `add_creds:500` |
| **Morality Change** | `morality:<delta>` | `morality:+5` or `morality:-3` |
| **Show Emoji** | `show_emoji:<npc_id>:<emoji>:<duration>` | `show_emoji:npc_alice:happy:2.0` |
| **Start Battle** | `start_battle:<enemy_ids>` | `start_battle:bandit;bandit;goblin` |
| **Open Shop** | `open_shop:<shop_id>` | `open_shop:weapon_store` |
| **Teleport** | `teleport:<location>` | `teleport:downtown_plaza` |

**Multiple Actions** (semicolon-separated):
```
"give_item:Potion:3;add_creds:200;morality:+2;set_flag:quest_complete:true"
```

---

### Common Condition Patterns

Conditions are checked in BRANCH nodes:

| Condition Type | Syntax | Example |
|----------------|--------|---------|
| **Morality Check** | `morality>=[value]` / `morality<=[value]` | `morality>=50` |
| **Flag Check** | `flag_[name]==[value]` | `flag_met_alice==true` |
| **Item Check** | `has_item:[item_id]` | `has_item:KeyCard_A` |
| **Mission Check** | `mission_active:[mission_id]` | `mission_active:side_cat_rescue` |
| **Objective Check** | `objective_complete:[obj_id]` | `objective_complete:talk_to_bob` |
| **Party Check** | `has_party_member:[member_id]` | `has_party_member:best_friend` |
| **Date Check** | `month>=[value]` / `day==[value]` | `month>=5` |
| **Time Check** | `time_of_day==[value]` | `time_of_day==evening` |
| **Default** | `default` | Always matches (fallback) |

**Multiple Conditions** (AND logic with `and`):
```
"morality>=30 and flag_met_alice==true"
"mission_active:investigate and has_item:Evidence"
```

---

### Tips for Dialogue Design

**1. Always include a default branch**:
```csv
branch_node,1,BRANCH,,,,"2|3|4","morality>=50|morality<=-30|default"
```
The `default` ensures there's always a valid path.

**2. Use meaningful node IDs**:
- Good: `quest_start`, `accept_path`, `decline_path`
- Bad: `1`, `2`, `3`

**3. Test all paths**:
- What if player has low morality?
- What if player doesn't have the item?
- What if mission is already complete?

**4. Set flags for one-time events**:
```csv
action_node,10,ACTION,,,,,,,"set_flag:saw_cutscene_intro:true"
```
Then check the flag:
```csv
branch_node,1,BRANCH,,,,"2|3","flag_saw_cutscene_intro==false|default"
```

**5. Use emojis for visual feedback**:
```csv
action_node,5,ACTION,,,,,,,"show_emoji:npc_alice:happy:2.0"
```
Player instantly sees NPC reaction.

**6. Break long dialogues into chunks**:
- Instead of 10 TEXT nodes in a row
- Add CHOICE nodes to keep player engaged

**7. Provide clear choice labels**:
- Good: "Yes, I'll help you find your cat"
- Bad: "Option 1"

**8. Record important choices**:
All choices are automatically stored in `GameState.dialogue_choices[dialogue_id_node_id]`, allowing you to reference them later.

---

### Multi-Language Implementation

The same CSV structure works across all languages. Only the `text` column changes:

**English (en/side_quests.csv)**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
mission_cat,1,TEXT,Alice,"My cat is missing! Will you help?",,,2,
mission_cat,2,CHOICE,Alice,"Please!","Yes, I'll help|No, sorry","3|5",,
```

**Spanish (es/side_quests.csv)**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
mission_cat,1,TEXT,Alice,"¡Mi gato está perdido! ¿Me ayudarás?",,,2,
mission_cat,2,CHOICE,Alice,"¡Por favor!","Sí, te ayudaré|No, lo siento","3|5",,
```

**Japanese (jp/side_quests.csv)**:
```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
mission_cat,1,TEXT,Alice,"私の猫がいなくなった！助けてくれますか？",,,2,
mission_cat,2,CHOICE,Alice,"お願い！","はい、手伝います|いいえ、ごめんなさい","3|5",,
```

**Key Points**:
- Same `dialogue_id` and `node_id` across all languages
- Same branching logic (next_node, condition, action)
- Only translate `text` and `choices` columns
- Variables like `{player_name}` work in all languages

---

## Emoji & Expression System

### Purpose

The Emoji System displays visual expressions above character heads in the overworld to convey emotions and reactions without dialogue.

### Emoji Types

| Emoji | Unicode | Meaning | Usage |
|-------|---------|---------|-------|
| 😊 | U+1F60A | Happy | NPC pleased with player, successful interaction |
| 😢 | U+1F622 | Sad | NPC disappointed, player made negative choice |
| 😡 | U+1F621 | Angry | NPC hostile, low morality reaction |
| ❤️ | U+2764 | Love | High affinity, romance option |
| ❓ | U+2753 | Confused | NPC doesn't understand, puzzle hint |
| ❗ | U+2757 | Surprised | Discovery, sudden realization |
| 💤 | U+1F4A4 | Sleeping | NPC unavailable (nighttime) |
| 💡 | U+1F4A1 | Idea | Mission available, hint |
| 💰 | U+1F4B0 | Money | Shop available, trade opportunity |
| ⚔️ | U+2694 | Combat | Battle encounter imminent |
| 🎁 | U+1F381 | Gift | Item available, reward ready |
| 🔒 | U+1F512 | Locked | Area/dialogue locked by conditions |
| ✅ | U+2705 | Complete | Mission complete, objective done |
| 🌟 | U+1F31F | Special | Rare event, critical NPC |

### Emoji Display Flow

```
1. EMOJI_TRIGGER
   ├── Event calls EmojiSystem.show_emoji(npc_id, emoji_type, duration)
   ├── Find NPC node in overworld scene
   ├── Create emoji sprite above NPC head
   └── Position emoji (NPC position + Vector2(0, -50))

2. EMOJI_ANIMATION
   ├── Fade in (0.2 seconds)
   ├── Bob animation (slight up/down movement)
   ├── Display duration (1.0-3.0 seconds)
   └── Fade out (0.2 seconds)

3. EMOJI_CLEANUP
   ├── Remove emoji sprite from scene
   └── Emit emoji_completed signal
```

### Emoji Integration

Emojis are triggered by:
- **Dialogue Actions**: `ACTION: show_emoji, npc_alice, happy, 2.0`
- **Proximity**: Player enters NPC interaction range
- **Events**: Automatic emoji on event trigger (e.g., `❗` when mission available)
- **Morality**: NPC shows `😡` or `😊` based on player morality
- **Time**: `💤` automatically shown for sleeping NPCs at night

---

## NPC Location Tracking

### System Purpose

NPCs move around the overworld based on **calendar day** and **time of day**, creating a living world with schedules.

### NPC Schedule Structure

Each NPC has a weekly schedule defining their location by:
- **Day of Week**: Monday-Sunday (or in-game equivalent)
- **Time of Day**: Morning, Afternoon, Evening, Night
- **Special Dates**: Override default schedule on specific calendar days

### Location Types

| Location Type | Description | Example |
|---------------|-------------|---------|
| **Overworld** | Specific position on map | `overworld_downtown, (150, 200)` |
| **Interior** | Inside building/scene | `scene_cafe_interior, npc_seat_1` |
| **Off-Map** | Not available | `null` (NPC not present today) |
| **Event** | Event-specific location | `event_school_assembly` |

### NPC Tracking Flow

```
1. DAY_START
   ├── CalendarSystem emits day_advanced signal
   ├── NPCLocationSystem loads npc_schedules.csv
   ├── For each NPC:
   │   ├── Check calendar date
   │   ├── Check for special date overrides
   │   └── Load default weekly schedule

2. TIME_CHANGE
   ├── CalendarSystem emits time_changed signal (morning/afternoon/evening/night)
   ├── NPCLocationSystem updates NPC positions
   ├── For each NPC:
   │   ├── Get location for current time slot
   │   ├── If location changed → Despawn from old location
   │   ├── Spawn at new location
   │   └── Update npc_current_locations dictionary

3. PLAYER_QUERY
   ├── Player enters location or interacts with NPC
   ├── NPCLocationSystem.get_npc_location(npc_id) → returns current position
   ├── NPCLocationSystem.get_npcs_at_location(location_id) → returns NPC list
   └── Used for dialogue triggers and mission objectives

4. SPECIAL_EVENTS
   ├── Event overrides NPC schedule
   ├── NPCLocationSystem.override_npc_location(npc_id, location, duration)
   ├── NPC moves to event location
   └── After event ends → Resume normal schedule
```

### Schedule Priority

When multiple schedules conflict:
1. **Event Override** (highest priority) - Active events override schedules
2. **Special Date** - Calendar-specific location (holidays, story dates)
3. **Weekly Schedule** - Default weekly pattern
4. **Fallback** - Default home location if no schedule defined

### NPC Availability

NPCs can be marked unavailable:
- **Story Gated**: NPC doesn't appear until story flag set
- **Mission Locked**: NPC busy during active mission
- **Time Locked**: NPC only appears during specific time ranges
- **Morality Locked**: NPC refuses to appear if morality too low/high

---

## Mission System

### Mission Types

| Type | Description | Example |
|------|-------------|---------|
| **Main Story** | Critical narrative missions | "Investigate the Data Breach" |
| **Side Quest** | Optional missions | "Find Lost Cat" |
| **Repeatable** | Can be repeated | "Daily Training Exercise" |
| **Time-Limited** | Must complete before deadline | "Stop the Heist (3 days)" |
| **Hidden** | Unlocked by discovery | "Secret Underground Lab" |

### Mission Structure

Each mission has:
- **Mission ID**: Unique identifier
- **Mission Name**: Display name (localized)
- **Mission Description**: Quest details (localized)
- **Mission Giver**: NPC who assigns mission
- **Prerequisites**: Conditions to unlock mission
- **Objectives**: List of objectives to complete
- **Rewards**: LXP, GXP, Creds, Items
- **Time Limit**: Optional deadline (calendar days)
- **Failure Conditions**: Optional fail states

### Mission Objectives

Objectives are individual tasks within a mission:

| Objective Type | Description | Example |
|----------------|-------------|---------|
| **Talk to NPC** | Speak with specific NPC | `talk_to, npc_alice` |
| **Go to Location** | Reach map position | `reach_location, downtown_plaza` |
| **Collect Item** | Obtain item(s) | `collect_item, KeyCard_A, 1` |
| **Defeat Enemies** | Win battle(s) | `defeat_enemy, enemy_bandit, 5` |
| **Capture Enemies** | Capture specific enemies | `capture_enemy, enemy_rare_01, 1` |
| **Deliver Item** | Give item to NPC | `deliver_item, npc_bob, Potion, 3` |
| **Choice** | Make specific dialogue choice | `choose_option, dialogue_15, choice_A` |
| **Wait** | Wait until date/time | `wait_until, month_5_day_10` |

### Mission Flow

```
1. MISSION_UNLOCK
   ├── Prerequisites met (flags, story progress, morality, etc.)
   ├── MissionSystem.unlock_mission(mission_id)
   ├── Mission appears in Mission Log
   └── Mission Giver NPC shows 💡 emoji

2. MISSION_ACCEPT
   ├── Player talks to Mission Giver NPC
   ├── Dialogue plays mission briefing
   ├── Player accepts mission (choice node)
   ├── MissionSystem.start_mission(mission_id)
   ├── Objectives become active
   └── Mission Tracker UI updates

3. OBJECTIVE_PROGRESS
   ├── Player completes objective action
   ├── MissionSystem checks objective conditions
   ├── If met → Mark objective complete
   ├── Update Mission Tracker UI
   └── Emit objective_completed signal

4. MISSION_COMPLETE
   ├── All objectives completed
   ├── MissionSystem.complete_mission(mission_id)
   ├── Award rewards (LXP, GXP, Creds, Items)
   ├── Update story flags
   ├── Play completion dialogue (Mission Giver)
   └── Remove from Active Missions, add to Completed

5. MISSION_FAIL (optional)
   ├── Failure condition met (time expired, wrong choice, etc.)
   ├── MissionSystem.fail_mission(mission_id)
   ├── Play failure dialogue
   ├── Optional: Allow retry or mark permanently failed
   └── Update Mission Log
```

### Mission Locations

Missions reference locations in the overworld:
- **Objective Markers**: Map pins showing objective locations
- **NPC Positions**: Quest NPCs move to mission locations
- **Item Spawns**: Quest items appear at specific positions
- **Enemy Encounters**: Quest battles trigger at marked locations

**CSV Example**:
```
mission_id,objective_id,objective_type,target,location,quantity
main_05,obj_01,talk_to,npc_alice,overworld_downtown,1
main_05,obj_02,collect_item,KeyCard_A,overworld_office_building,1
main_05,obj_03,deliver_item,npc_bob,scene_lab_interior,1
```

---

## Item Location System

### Purpose

Defines where items spawn in the overworld and tracks which have been collected.

### Item Spawn Types

| Type | Description | Respawn |
|------|-------------|---------|
| **Static** | Permanent item location | Never |
| **Collectible** | One-time pickup | Never |
| **Daily** | Respawns daily | Every day |
| **Weekly** | Respawns weekly | Every 7 days |
| **Mission** | Only spawns during mission | Never (mission-gated) |
| **Event** | Only spawns during event | Never (event-gated) |

### Item Location Flow

```
1. WORLD_LOAD
   ├── ItemLocationSystem loads item_locations.csv
   ├── For each item spawn:
   │   ├── Check if already collected (GameState.collected_items)
   │   ├── Check prerequisites (mission active, event active, etc.)
   │   ├── If valid → Spawn item in overworld
   │   └── Create interaction area (Area2D collider)

2. PLAYER_COLLECT
   ├── Player enters item interaction area
   ├── Prompt displays: "Press A to collect [Item Name]"
   ├── Player presses A
   ├── ItemLocationSystem.collect_item(item_id, location_id)
   ├── Add item to inventory
   ├── Play collection animation/sound
   ├── Record collection in GameState
   └── Despawn item from world

3. DAILY_RESET (for respawning items)
   ├── CalendarSystem emits day_advanced signal
   ├── ItemLocationSystem checks respawn timers
   ├── For each daily/weekly item:
   │   ├── Check last collected date
   │   ├── If respawn time passed → Respawn item
   │   └── Update spawn state

4. MISSION_ITEMS
   ├── Mission becomes active
   ├── ItemLocationSystem spawns mission-specific items
   ├── Items only collectible during mission
   └── Items despawn when mission completes/fails
```

### Item Categories

Items placed in overworld:
- **Healing Items**: Potions, Energy Drinks
- **Combat Items**: Bind items, buff items
- **Key Items**: Story-critical items (keycards, documents)
- **Collectibles**: Lore items, optional pickups
- **Currency**: Cred drops in world

---

## Shop System

### Shop Types

| Shop Type | Description | Example |
|-----------|-------------|---------|
| **General Store** | Basic items, always available | Health items, common gear |
| **Weapon Shop** | Weapons and combat gear | Swords, bracelets, armor |
| **Sigil Shop** | Sigils and skill items | Elemental sigils |
| **Black Market** | Rare/expensive items | High-tier Binds, rare gear |
| **Event Shop** | Limited-time shop | Festival exclusive items |
| **NPC Vendor** | NPC-specific shop | Alice's homemade potions |

### Shop Progression System

Shops unlock new inventory based on:
- **Story Progression**: `chapter >= 3` unlocks Tier 2 weapons
- **Calendar Date**: `month >= 5` unlocks summer items
- **Morality**: High morality unlocks special items, low morality unlocks black market
- **Missions Completed**: Completing certain missions unlocks shop expansions
- **Creds Spent**: Spending certain amount unlocks VIP inventory

### Shop Flow

```
1. SHOP_ENTER
   ├── Player interacts with shop NPC/location
   ├── ShopSystem.open_shop(shop_id)
   ├── Load shop inventory from shop_inventory.csv
   ├── Check shop progression unlocks
   ├── Filter available items (story gates, stock limits)
   └── Display shop UI

2. SHOP_BROWSE
   ├── Player selects item category tab
   ├── Display items with:
   │   ├── Item name (localized)
   │   ├── Item description (localized)
   │   ├── Price (Creds)
   │   ├── Stock quantity (if limited)
   │   └── Owned quantity
   ├── Player can compare stats (for equipment)
   └── Player can view detailed info

3. SHOP_PURCHASE
   ├── Player selects item and quantity
   ├── Check if player has enough Creds
   ├── Check stock availability
   ├── Confirm purchase dialogue
   ├── Deduct Creds from GameState
   ├── Add item to inventory
   ├── Reduce shop stock (if limited)
   ├── Play purchase sound/animation
   └── Update ShopSystem.purchase_history

4. SHOP_SELL (optional)
   ├── Player selects item from inventory to sell
   ├── Calculate sell price (usually 50% of buy price)
   ├── Confirm sale dialogue
   ├── Remove item from inventory
   ├── Add Creds to GameState
   └── Update ShopSystem.sales_history

5. SHOP_EXIT
   ├── Player closes shop UI
   ├── Save shop state (stock changes)
   └── Return to overworld
```

### Shop Stock Management

Shops can have:
- **Unlimited Stock**: Always available
- **Limited Stock**: Finite quantity (restocks daily/weekly/never)
- **One-Time Purchase**: Can only buy once
- **Bundle Deals**: Buy X, get discount
- **Story-Gated**: Unlocked by story flags

**CSV Example**:
```
shop_id,item_id,price,stock,restock_days,unlock_flag
general_01,Potion,50,unlimited,0,
general_01,Ether,80,unlimited,0,
general_01,Bind_Basic,100,5,1,
weapon_01,Sword_Iron,500,1,0,chapter_2
black_market_01,Bind_Master,5000,1,7,morality_low
```

---

## Morality-Based NPC Reactions

### Morality Tiers

NPCs react differently based on player's morality score:

| Tier | Morality Range | Label | NPC Reaction |
|------|----------------|-------|--------------|
| **Saint** | 80-100 | Hero | Extremely friendly, discounts, special quests |
| **Good** | 40-79 | Upstanding | Friendly, normal interactions |
| **Neutral** | -39 to 39 | Citizen | Standard interactions |
| **Bad** | -79 to -40 | Troublemaker | Wary, higher prices, some NPCs refuse service |
| **Evil** | -100 to -80 | Villain | Hostile, shops refuse service, black market access |

### Reaction System

Each NPC can have up to 5 dialogue variants per interaction based on morality:

**Example**: NPC Shopkeeper greeting
- **Saint**: "Welcome back, hero! I saved my best items for you. 10% discount!"
- **Good**: "Hello! Thanks for shopping with us."
- **Neutral**: "What can I get you?"
- **Bad**: "I'm watching you. Don't cause trouble."
- **Evil**: "We don't serve your kind here. Get out."

### Morality Effects

| Effect | Saint | Good | Neutral | Bad | Evil |
|--------|-------|------|---------|-----|------|
| **Shop Prices** | -10% | 0% | 0% | +20% | Refused |
| **Mission Access** | All + Hero missions | All standard | Standard | Some locked | Villain missions only |
| **NPC Availability** | All available | Most available | Standard | Some refuse | Many refuse, black market opens |
| **Dialogue Tone** | Warm, grateful | Friendly | Professional | Cold, wary | Hostile, fearful |
| **Emoji Display** | ❤️😊 | 😊 | Neutral | 😡 | 😡🔒 |

### Reaction Triggers

Morality reactions update:
- **On Dialogue Start**: DialogueManager checks morality, loads appropriate variant
- **On Shop Enter**: ShopSystem applies price modifiers
- **On Mission Offer**: MissionSystem checks if NPC will offer mission
- **On Event Trigger**: EventManager selects morality-appropriate event path

### Dynamic Morality Events

Some events only trigger based on morality:
- **High Morality (≥50)**: "Heroic Request" events, NPCs ask for help
- **Low Morality (≤-50)**: "Villain Path" events, black market contacts player
- **Crossing Thresholds**: NPCs comment when player crosses from good→neutral→bad

---

## Monthly Critical Events

### System Purpose

Each in-game month requires the player to complete a **critical story event** or face **game over**. This creates urgency and narrative pacing.

### Critical Event Structure

Each month has:
- **Event ID**: Unique identifier
- **Event Name**: "Month 5 Crisis: Data Breach"
- **Unlock Date**: First day the event becomes available
- **Deadline Date**: Last day to complete event before game over
- **Prerequisites**: Story flags that must be set
- **Event Type**: Investigation, battle, choice sequence, etc.
- **Failure Consequence**: Game over message and bad ending flag

### Monthly Event Flow

```
1. MONTH_START
   ├── CalendarSystem emits month_changed signal
   ├── EventManager loads critical_monthly.csv
   ├── Check critical event for current month
   ├── Display notification: "New Critical Event Available"
   └── Add event marker to map

2. EVENT_AVAILABLE
   ├── Player can complete event anytime before deadline
   ├── UI shows days remaining
   ├── NPCs reference event in dialogue
   └── Warnings increase as deadline approaches

3. DEADLINE_WARNINGS
   ├── 7 days remaining: Yellow warning notification
   ├── 3 days remaining: Orange warning, NPC dialogue changes
   ├── 1 day remaining: Red urgent warning, dramatic music
   └── Deadline day: Final warning on day start

4. EVENT_COMPLETION
   ├── Player completes critical event
   ├── EventManager marks event complete
   ├── Story progresses to next chapter
   ├── Unlock next month's content
   └── Clear deadline warnings

5. EVENT_FAILURE (Deadline Passed)
   ├── CalendarSystem advances past deadline
   ├── EventManager checks if critical event completed
   ├── If NOT completed:
   │   ├── Trigger BAD END cutscene
   │   ├── Display failure message (localized)
   │   ├── Option to load last save
   │   └── OR continue in "failed timeline" (alternate path)
```

### Critical Event Types

| Type | Description | Example |
|------|-------------|---------|
| **Investigation** | Gather clues, talk to NPCs | "Solve the Data Breach mystery" |
| **Boss Battle** | Defeat critical enemy | "Stop the rogue AI" |
| **Choice Sequence** | Make critical story decision | "Choose alliance: Rebels or Corp" |
| **Rescue Mission** | Save NPC before time runs out | "Rescue kidnapped ally" |
| **Defense** | Protect location from attack | "Defend school from invasion" |
| **Infiltration** | Sneak into enemy base | "Infiltrate black market HQ" |

### Failure Consequences

When player fails critical event:
- **Game Over (Default)**: Load last save or start over
- **Bad Timeline (Optional)**: Continue with consequences
  - NPCs react negatively
  - Some content locked
  - Worse ending path
  - Harder difficulty

### Alternate Paths

Some critical events offer multiple solutions:
- **Heroic Path**: Complete event morally (high morality)
- **Neutral Path**: Complete event pragmatically
- **Villain Path**: Complete event ruthlessly (low morality)

All paths complete the event, but affect:
- Morality score
- NPC reactions
- Available missions
- Ending variations

---

## Localization & Multi-Language Support

### Supported Languages

Initial languages:
- **English (en)** - Default
- **Spanish (es)**
- **French (fr)**
- **Japanese (jp)**

Additional languages easily added by creating new CSV folders.

### Localization Architecture

All text content is stored in language-specific CSV files:

```
data/csv/dialogue/
├── en/
│   ├── main_story.csv
│   ├── npcs.csv
│   ├── side_quests.csv
│   ├── items.csv
│   ├── missions.csv
│   └── ui.csv
├── es/
│   └── [same structure]
├── fr/
│   └── [same structure]
└── jp/
    └── [same structure]
```

### LocalizationManager

**Responsibilities**:
1. Detect and load player's selected language
2. Load all CSV files for current language
3. Provide lookup functions for translated text
4. Handle missing translations (fallback to English)
5. Support dynamic language switching

**API**:
```gdscript
# Get translated text
LocalizationManager.get_text(key: String) → String

# Get dialogue line
LocalizationManager.get_dialogue(dialogue_id: String, node_id: String) → String

# Get item name/description
LocalizationManager.get_item_name(item_id: String) → String
LocalizationManager.get_item_desc(item_id: String) → String

# Get mission data
LocalizationManager.get_mission_name(mission_id: String) → String
LocalizationManager.get_mission_desc(mission_id: String) → String

# Get UI text
LocalizationManager.get_ui(ui_key: String) → String

# Change language at runtime
LocalizationManager.set_language(lang_code: String)
```

### Text Key Format

All text keys follow this format:

```
dialogue_<dialogue_id>_<node_id>
item_<item_id>_name
item_<item_id>_desc
mission_<mission_id>_name
mission_<mission_id>_desc
ui_<ui_element>
```

**Examples**:
- `dialogue_main_01_node_05` - Main story dialogue
- `item_Potion_name` - "Potion"
- `item_Potion_desc` - "Restores 50 HP"
- `mission_side_03_name` - "Lost Cat"
- `ui_start_game` - "Start Game"

### Variable Substitution

All languages support variable substitution:

**English**: `"Hello {player_name}, welcome to {location}!"`
**Spanish**: `"¡Hola {player_name}, bienvenido a {location}!"`
**French**: `"Bonjour {player_name}, bienvenue à {location} !"`
**Japanese**: `"こんにちは{player_name}さん、{location}へようこそ！"`

Variables are language-agnostic and replaced at runtime.

---

## CSV Data Formats

### calendar_events.csv

```csv
event_id,event_name,month,day,time_of_day,dialogue_id,scene,prerequisites,outcomes
event_month1_intro,Introduction,1,1,morning,main_intro,,chapter_0,chapter_1;flag_intro_done
event_month2_crisis,Data Breach,2,15,evening,main_crisis_01,,chapter_1,chapter_2;flag_crisis_started
```

### trigger_events.csv

```csv
event_id,event_name,location,trigger_type,dialogue_id,prerequisites,repeatable,outcomes
event_downtown_alice,Meet Alice,overworld_downtown,enter,npc_alice_meet,chapter_1,false,flag_met_alice
event_shop_tutorial,Shop Tutorial,scene_shop_01,interact,shop_tutorial,,false,flag_shop_unlocked
```

### critical_monthly.csv

```csv
month,event_id,event_name,unlock_day,deadline_day,dialogue_id,failure_message,is_optional
1,critical_month1,Survive First Week,1,7,main_critical_01,You failed to survive your first week.,false
2,critical_month2,Solve Data Breach,1,30,main_critical_02,The data breach spiraled out of control.,false
```

### dialogue CSV (en/main_story.csv)

```csv
dialogue_id,node_id,node_type,speaker,text,choices,next_node,condition,action
main_intro,1,TEXT,Alice,"Welcome to Psyokin Academy!",,,2,
main_intro,2,TEXT,Alice,"This is where your journey begins.",,,3,
main_intro,3,CHOICE,Alice,"Are you ready?","Yes|No","4|5",,
main_intro,4,TEXT,Alice,"Great! Let's get started.",,,END,
main_intro,5,TEXT,Alice,"Take your time. I'll be here.",,,END,
```

### npc_locations.csv

```csv
npc_id,day_of_week,time_of_day,location,position_x,position_y,special_date
npc_alice,monday,morning,overworld_downtown,150,200,
npc_alice,monday,afternoon,scene_cafe,,npc_seat_2,
npc_alice,monday,evening,overworld_residential,300,400,
npc_alice,,night,,,2025-05-15
npc_alice,,,event_school_assembly,,,2025-05-15
```

### npc_reactions.csv

```csv
npc_id,interaction_type,morality_tier,dialogue_variant_id,emoji,price_modifier
npc_shopkeeper,greeting,saint,shop_greeting_saint,😊❤️,-10
npc_shopkeeper,greeting,good,shop_greeting_good,😊,0
npc_shopkeeper,greeting,neutral,shop_greeting_neutral,,0
npc_shopkeeper,greeting,bad,shop_greeting_bad,😡,20
npc_shopkeeper,greeting,evil,shop_greeting_refuse,😡🔒,REFUSE
```

### mission_definitions.csv

```csv
mission_id,mission_type,mission_name_key,mission_desc_key,mission_giver,prerequisites,time_limit_days,rewards_lxp,rewards_gxp,rewards_creds,rewards_items
main_01,main_story,mission_main_01_name,mission_main_01_desc,npc_alice,chapter_1,,100,50,500,Potion:3
side_03,side_quest,mission_side_03_name,mission_side_03_desc,npc_cat_lady,flag_met_alice,3,50,25,200,
```

### mission_objectives.csv

```csv
mission_id,objective_id,objective_type,target,location,quantity,display_text_key
main_01,obj_01,talk_to,npc_bob,overworld_downtown,1,objective_talk_bob
main_01,obj_02,collect_item,KeyCard_A,overworld_office,1,objective_collect_keycard
main_01,obj_03,deliver_item:npc_alice:KeyCard_A,npc_alice,scene_cafe,1,objective_deliver_keycard
```

### item_locations.csv

```csv
location_id,item_id,position_x,position_y,spawn_type,respawn_days,prerequisites,is_visible
overworld_downtown_item_01,Potion,400,300,static,0,,true
overworld_forest_item_05,Ether,150,600,daily,1,chapter_2,true
mission_main_05_key,KeyCard_A,500,200,mission,0,mission_main_05_active,false
```

### shop_inventory.csv

```csv
shop_id,item_id,price,stock_quantity,restock_days,unlock_flag,unlock_morality_min,unlock_morality_max
general_01,Potion,50,unlimited,0,,,
general_01,Ether,80,unlimited,0,chapter_2,,
weapon_01,Sword_Steel,1000,5,7,chapter_3,,
black_market_01,Bind_Master,5000,1,30,,-100,-50
hero_shop_01,Hero_Badge,9999,1,0,morality_high,80,100
```

---

## Integration Points

### CalendarSystem Integration

All systems hook into CalendarSystem:

```gdscript
# Listen to calendar signals
CalendarSystem.day_advanced.connect(_on_day_advanced)
CalendarSystem.month_changed.connect(_on_month_changed)
CalendarSystem.time_changed.connect(_on_time_changed)

func _on_day_advanced(year: int, month: int, day: int):
    # EventManager: Check calendar events
    # NPCLocationSystem: Update NPC schedules
    # ItemLocationSystem: Respawn daily items
    # ShopSystem: Restock shops
    # MissionSystem: Check mission deadlines
```

### MoralitySystem Integration

Morality affects multiple systems:

```gdscript
# Get current morality
var morality = MoralitySystem.get_current_morality()

# DialogueManager: Select dialogue variant
var dialogue_variant = get_dialogue_for_morality(morality)

# ShopSystem: Apply price modifiers
var final_price = base_price * get_morality_price_modifier(morality)

# EventManager: Check morality-gated events
if morality >= event.min_morality and morality <= event.max_morality:
    trigger_event(event)

# NPCLocationSystem: Some NPCs refuse to appear
if morality < npc.min_morality_to_appear:
    return null # NPC not available
```

### GameState Integration

All systems save/load state through GameState:

```gdscript
# Save data
GameState.completed_events = EventManager.get_completed_events()
GameState.dialogue_choices = DialogueManager.get_choice_history()
GameState.collected_items = ItemLocationSystem.get_collected_items()
GameState.active_missions = MissionSystem.get_active_missions()
GameState.completed_missions = MissionSystem.get_completed_missions()
GameState.npc_flags = NPCLocationSystem.get_npc_flags()
GameState.shop_purchases = ShopSystem.get_purchase_history()

# Load data
EventManager.load_state(GameState.completed_events)
DialogueManager.load_state(GameState.dialogue_choices)
ItemLocationSystem.load_state(GameState.collected_items)
MissionSystem.load_state(GameState.active_missions, GameState.completed_missions)
```

### UI Integration

UI elements display data from all systems:

**Mission Tracker UI**:
- Pulls active missions from MissionSystem
- Displays objective progress
- Shows time remaining for time-limited missions

**Map UI**:
- Shows NPC locations from NPCLocationSystem
- Displays mission objective markers from MissionSystem
- Shows item collectible locations from ItemLocationSystem
- Highlights event locations from EventManager

**Dialogue Box UI**:
- Renders text from LocalizationManager
- Displays character portraits
- Shows choice buttons from DialogueManager
- Plays emojis from EmojiSystem

**Calendar UI**:
- Shows current date from CalendarSystem
- Highlights critical event deadlines from EventManager
- Shows NPC schedules from NPCLocationSystem

---

## Summary

The Event & Dialogue System is a comprehensive, CSV-driven narrative engine that provides:

- **Scalable content management** via CSV files (easy to edit without code)
- **Multi-language support** with full localization for dialogue, items, missions, and UI
- **Dynamic NPC behavior** based on calendar, morality, and story progression
- **Branching dialogue** with player choices and conditional paths
- **Mission system** with objectives, rewards, and deadlines
- **Living world** with NPC schedules, item spawns, and shop inventories
- **Morality integration** affecting all NPC interactions and content access
- **Critical monthly events** creating narrative urgency and pacing
- **Visual feedback** via emoji expression system
- **Future-proof architecture** designed for expansion and iteration

All systems are **data-driven**, allowing for rapid content creation, easy balancing, and seamless localization without touching code.
