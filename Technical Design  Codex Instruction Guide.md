### **Purpose**

This document takes the high‑level Game Design Document and turns it into an actionable technical spec that ChatGPT Codex (or Roblox Assistant) can consume **module‑by‑module** to produce production‑ready Luau code. The design consciously avoids paid plug‑ins; everything is built on Roblox’s first‑party services plus the free Vibe Blocks MCP you already configured.

---

### **1  Game‑cycle & finite‑state machine (FSM)**

| State | Duration | Early‑exit condition | On timeout | Next state |
| ----- | ----- | ----- | ----- | ----- |
| `Lobby` | 20 s | All active clients have loaded & pressed Ready | Auto‑advance even if only one player (bot substitution) | `Dilemma` |
| `Dilemma` | 15 s | Both choices submitted | Treat missing choice as **Defect** | `Maze` |
| `Maze` | 120 s | All players reach exit or die | End run, award minimum loot | `Progression` |
| `Progression` | 10 s | — | — | `Lobby` |

FSM lives in **ServerScriptService/GameLoopController**. It emits `RoundStateChanged(stateEnum, timeRemaining)` every second so low‑end devices stay in sync. If a player disconnects mid‑round, the FSM promotes a bot to keep pay‑offs fair.

---

### **2  Module architecture**

**ServerScriptService**

* `GameLoopController` – drives FSM & timers.  
* `MatchmakerService` – pairs players or spawns bots.  
* `DilemmaService` – records choices, resolves pay‑offs.  
* `MazeService` – generates maze, spawns obstacles, runs autoscroll.  
* `EconomyService` – stamps, inventory, shop.  
* `DataPersistence` – DataStore I/O \+ version migration.  
* `BotAI` – strategies:  
  * `AlwaysCooperate`  
  * `AlwaysDefect`  
  * `TitForTat` (mirrors last human choice)

**ReplicatedStorage/Modules** – `Constants`, `Enums`, `RemoteDefinitions`, `ItemDefinitions`, `PlayerProfile`.

**Client** – `StateListener`, `UILayer` (one sub‑module per state), `MazeRunner` (camera/controls), `CosmeticHandler`.

---

### **3  Folder & script layout (Rojo)**

| ReplicatedStorage/  Modules/ServerScriptService/  GameLoopController  MatchmakerService  ...StarterPlayer/  StarterPlayerScripts/StateListenerStarterGui/  UILayer/ |
| :---- |

### **4  Key Luau APIs & native patterns**

CollectionService (obstacle tagging) · TweenService (UI transitions) · RunService.Stepped (autoscroll) · DataStoreService \+ OrderedDataStore (leaderboard) · Stream‑enabled workspace. External frameworks optional; **no paid assets**.

---

### **5  Maze generation & obstacle registry**

| \-- returns a Folder "Floor\<X\>" containing Parts & Obstaclesfunction generateMaze(floorLevel: number, seed: number): Folder |
| :---- |

Algorithm: depth‑first search builds a two‑cell‑wide critical path and random side branches; dead ends receive minor loot pickups.

**ObstacleRegistry (JSON‑style):**

| local Obstacles \= {  {name \= "Spike",    tag \= "Obstacle", prefab \= "Spike",    probability \= 0.15},  {name \= "Oil",      tag \= "Slow",     prefab \= "OilPatch", probability \= 0.10},  {name \= "Fan",      tag \= "Push",     prefab \= "Fan",      probability \= 0.05},} |
| :---- |

MazeService rolls once per empty tile; obstacles carry the specified CollectionService tag so the shared client code can apply effects.

Autoscroll moves the **camera**, not the parts, to lower physics cost:

| local scrollSpeed \= 8 \-- studs/s; accelerates \+1 every 20 s |
| :---- |

### **6  Prisoner’s Dilemma resolution**

RemoteFunction: `SubmitChoice(choice: ChoiceEnum): bool` (returns success). Pay‑off lookup:

| local Payoff \= {  CC \= Vector2.new(3, 3),  CD \= Vector2.new(5, 0),  DC \= Vector2.new(0, 5),  DD \= Vector2.new(0.5, 0.5),} |
| :---- |

Results are sent via `ShowPayoff` RemoteEvent together with a short tween animation.

---

### **7  Persistent data schema & migration**

| PlayerProfile \= {  Version       \= 1,      \-- bump when schema changes  UserId        \= 0,  Floor         \= 1,  Health        \= 100,  Stamps        \= 0,  Inventory     \= {},  ChoiceHistory \= {},  AutoStrategy  \= "manual",} |
| :---- |

`DataPersistence` checks the Version field at load; if lower than current, runs a `migrate(profile)` function before saving.

---

### **8  Networking contract & enums**

| export type RoundState \= Enum.EnumItem & {  Lobby:   EnumItem,  Dilemma: EnumItem,  Maze:    EnumItem,  Prog:    EnumItem,}\-- ChoiceEnum \= {Cooperate \= 0, Defect \= 1} |
| :---- |

RemoteEvents

* `RoundStateChanged(state: RoundState, timeRemaining: number)`  
* `ShowPayoff(data: table)`  
* `BotSpawned(name: string, strategyId: string)`

RemoteFunctions

* `SubmitChoice(choice: ChoiceEnum)`  
* `PurchaseItem(itemId: string)`

---

### **9  Codex prompt style guide**

Place a **multiline header** atop every module:

| \--\[\[Module: MazeServiceRole: Create procedural maze, tag obstacles, drive autoscroll.Inputs: generateMaze(level, seed)Outputs: RemoteEvents.RoundStateChanged (state \= Maze)Constraints: server‑only; must respect CollectionService tags.Style: Luau strict, camelCase locals, PascalCase modules.\]\] |
| :---- |

Then ask Codex to **fill in function bodies but leave TODO comments** where external modules are referenced.

---

### **10  Recommended workflow**

1\. Write headers & empty functions in VS Code \+ Rojo. 2\. Feed one module at a time to Codex. 3\. Lint with `selene` (strict mode) before pasting into Studio. 4\. PlaySolo → 2‑player → Live test.

---

### **11  Compliance, monetisation & analytics**

Frame rewards as "bonus stamps;" keep Robux spend cosmetic or mild. Use `AnalyticsService:SetEvent` for funnel tracking. Validate every Remote on server; kick exploits. Localisation hooks for wording later.

---

### **12  Milestones**

* **v0.1** FSM \+ basic UI.  
* **v0.2** Maze generation & autoscroll.  
* **v0.3** Persistence \+ economy.  
* **v1.0** Bot AI, store polish, analytics.

---

### **13  Testing strategy (TestEZ)**

| Service | Edge case covered by test |
| :---- | :---- |
| GameLoopController | Player disconnect during Dilemma; ensure bot substitution & FSM continues |
| DilemmaService | Tie‑out after 15 s with only one choice submitted |
| MazeService | Obstacle duplication check vs registry probabilities |
| DataPersistence | Simulated DataStore outage and version migration |
| EconomyService | Injection of fake Remote `PurchaseItem` with tampered cost |

Integration tests use `RunService.Stepped` mocks to fast‑forward timers.

---

### **14  Further considerations**

Accessibility (mobile buttons 58 px+, colour‑blind safe palette), low‑end device performance (`StreamingEnabled`, parts count \<3 k), future localisation (`LocalizationTable` stubs), analytics A/B hooks on payoff matrix.

---

### **15  Code style & conventions**

* **Luau strict‑type annotations**  
* `camelCase` for locals & functions, `PascalCase` for modules, `UPPER_SNAKE` for constants.  
* One public class per ModuleScript.  
* 120 char line length.  
* Favor array‑style `for … in ipairs` over `pairs` for deterministic order.

---

This v1.1 pass adds: explicit FSM table, obstacle registry, bot strategies, schema versioning, enum definitions, concrete edge‑case tests, and style conventions—enough detail for Codex to generate coherent, unified code without improvising. Let me know if you’d like a deeper dive into any specific module before we cue Codex.

