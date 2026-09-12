# CONTEXT.md — En Kısa Yolculuk (Istanbul Metro Route Finder)

> This file is the project's **technical reference**. It explains what we're
> building, why each decision was made, and which pitfalls to avoid. Read this
> file in full before writing any code.

---

## 1. What Is the Project?

A native iPhone metro route finder, specific to Istanbul.

- The user enters a **start** and an **end** station.
- The app generates and shows **3 alternative routes**.
- The user picks one of them.
- Each route shows **total time** and **transfer count**
  (e.g. "Total time: 50 minutes, transfers: 2").
- The UI will include some graphic/visual design elements — a polished UX is
  the goal.

**Scope boundaries (v1):**
- Istanbul only. No other city.
- iPhone (iOS) only. **No** Android target.
- **Settled:** metro (M1A–M11), tram (T1/T2/T4/T5/T6), funicular (F1–F4),
  Marmaray and Metrobüs are all in. Ferries and buses are out.

---

## 2. Tech Decision: Swift + SwiftUI

**Final decision: Swift + SwiftUI. This decision is closed; do not reopen it.**

Rationale:
- Single platform (iOS only) + a polished-visuals goal → native delivers the
  best performance and the cleanest UX.
- React Native/Expo's only advantage (one codebase also covering Android) is
  useless here because Android isn't wanted; you'd pay the cost of that
  abstraction layer for no reason.
- Python is not practical for native iOS (it can only help as data-prep
  scripting, not in the app itself).
- SwiftUI is declarative (similar to React's model); the developer's Java/OOP
  background transfers well to Swift.

**Key principle:** The language choice was driven by **platform, not algorithm**.
The graph algorithm runs trivially fast in any language at this scale (a few
hundred nodes); performance is never the bottleneck.

**Permitted helper language:** Python scripts may be used to clean the network
data (stations/lines/times) and convert it to JSON. This is not app code.

---

## 3. Data Model

### 3.1. The graph is undirected
On the metro you travel in both directions and both trips take the same time →
an **undirected, weighted graph**. Edge weight = travel time between stations
(minutes).

### 3.2. Line ↔ Station relationship: NOT inheritance — an association
> ⚠️ A station can belong to more than one line. Therefore an **inheritance**
> model like "Line = superclass, Station = subclass" is WRONG (it leads to a
> multiple-inheritance mess).

The correct model is a **many-to-many association**:
- A **Line** has multiple **Stations**.
- A **Station** belongs to multiple **Lines**.
Model as two separate entities + the relationship between them.

### 3.3. Where data lives: JSON, NOT a DB
> ⚠️ **Do not use a database.** The Istanbul metro network is static and small
> (a few hundred stations). A DB is over-engineering.

- Embed the network data as a **JSON file** in the app bundle.
- Load it into memory at startup (adjacency list / map).
- A DB only comes into play if you store **user data** (favorite routes, search
  history, accounts) — and even that, at this scale, is probably solved with
  simple local storage (e.g. UserDefaults / a file).

---

## 4. Algorithm: Line-Expanded Graph + Dijkstra

### 4.1. The real problem to solve
Adding the transfer penalty **after** running Dijkstra gives WRONG results.

> ⚠️ Why it's a bug: plain Dijkstra only minimizes time. It might pick a path
> that saves 2 minutes via 3 transfers; but once the +10min × transfers penalty
> is accounted for, a 1-transfer path is far better. Adding the penalty
> afterward only corrects the **number shown on screen**, it does **not correct
> the chosen path**. The penalty must be **inside** the search.

### 4.2. The correct model — Line-Expanded graph
Define nodes as `(station, line)` pairs:

- **Node:** every `(station, line)` combination is a distinct node.
- **Ride edge:** between consecutive `(station, line)` nodes on the same line.
  Weight = travel time.
- **Transfer edge:** within the same station, between
  `(station, line A) ↔ (station, line B)`. Weight = **10 min** (fixed penalty).
- **Virtual start:** `START → (start station, *)` for all lines, weight 0.
- **Virtual end:** `(end station, *) → END` for all lines, weight 0.

Run **plain Dijkstra** on this graph.

### 4.3. What this model solves (all at once)
- The transfer penalty enters the search **naturally** → the optimal path is
  chosen correctly.
- Multi-line stations are already modeled by the `(station, line)` pair.
- Cases like "line A → line B → line A again" are **counted correctly**; done if
  genuinely optimal, not done otherwise. No need to hand-wave "probably won't
  happen."
- **No separate algorithm** is needed to detect which lines were used after the
  path is found — the lines are read directly off the nodes on the path.
- The old "if n lines found then n−1 transfers" formula is **unnecessary** (and
  that formula would have miscounted the A→B→A case anyway).

### 4.4. Transfer penalty — DONE, and now variable
- Default: **10 min**, read from `transferPenaltyMinutes` in the data.
- **Per-pair overrides shipped.** `customTransferPenalties` re-weights a
  specific `(station, lineA) ↔ (station, lineB)` pair; 28 are declared, all
  15 min, for walking transfers (almost all Metrobüs ↔ rail). See
  `DATA_SCHEMA.md` §5.
- The lookup lives in `TransferPenaltyTable` and is consulted by
  `LineExpandedGraph.buildTransferEdges()`, falling back to the default.

---

## 5. The "3 Routes" Requirement

> ⚠️ Plain Dijkstra gives you **one** shortest path. An extra approach is
> required for 3 routes.

Two options:
1. **k-shortest paths (Yen's algorithm):** the mathematically best 3
   alternatives.
2. **3 routes by criteria (PREFERRED UX):** generate 3 routes with different
   criteria like "fastest", "fewest transfers", "fewest stops". This gives the
   user **3 genuinely different options** instead of 3 near-identical paths —
   which is usually what people want.

**Decision: option 2, settled 2026-09-11 and shipped.** Three Dijkstra runs
over the same line-expanded graph under three lexicographic orderings of
`PathCost`. Not k-shortest.

Two consequences worth knowing:
- When two criteria pick the same path it is shown **once with both labels**,
  so a short trip often yields 2 cards rather than 3.
- On the real network "fewest stops" can be pathological: it will trade 40
  extra minutes and 4 extra transfers to save a single stop. See §7.2.

---

## 6. The Biggest Risk: DATA

> ⚠️ In this project the hard part is **not** the algorithm, it's the data.

What's needed:
- The station list.
- Which station is on which line(s).
- **Travel times between stations** (the most frustrating part).

The app is only as good as the quality of this data. Sources:
- Metro İstanbul / İBB open-data portals should be tried first.
- If unavailable, times may have to be compiled by hand.

**Resolved.** The user supplied the network by hand, line by line, as the
plain-text listing in `Data/source/lines.txt`. It compiles to `network.json`
via `Tools/build_network.py`.

The prediction held: the algorithm was never the hard part. Every real problem
in this project has been a data-modelling one — stations that share a name but
are different places, interchanges split across two official names, and
transfers that are a 15-minute walk. `DATA_SCHEMA.md` §4 is the accumulated
answer.

---

## 7. Current State

**22 lines · 307 stations · 329 segments · 55 transfer points · 28 penalty
overrides.** `validate()` passes; 137 unit tests and 14 UI tests pass; the app
builds and runs on the simulator.

Lines: M1A, M1B, M2, M3, M4, M5, M6, M7, M8, M9, M11, T1, T2, T4, T5, T6,
F1–F4, Marmaray, Metrobüs.

---

### 7.1. Still open

- [ ] Will user data (favourites / history) ship in v1? If so, local storage
      (UserDefaults or a file) — still no DB.
- [ ] Visual design of the three screens. The wiring is real; the layout is a
      first pass.
- [ ] Ferries and buses: out of scope for v1, never discussed for v2.

Settled and shipped, kept here so they are not reopened:

- [x] **Data source** — hand-compiled by the user as `Data/source/lines.txt`.
- [x] **Network scope** — metro + tram + funicular + Marmaray + Metrobüs.
- [x] **3-route strategy** — criteria-based, not k-shortest (§5).
- [x] **Variable transfer penalty** — shipped as `customTransferPenalties`
      (§4.4). This was the v2 item; it arrived in v1 because Metrobüs needed it.

---

### 7.2. Known issues

1. **"En Az Durak" is pathological on a real network.** Atatürk Havalimanı →
   Hacıosman: the fewest-stops route spends 112 min and 5 transfers to save a
   single stop over a 72-minute, 1-transfer alternative. The algorithm is
   right, the criterion is a poor product choice. Options: cap transfers, or
   replace the criterion with a genuine second-best-by-time alternative.
2. **A route's displayed transfer count can disagree with its own label.** A
   walk at either end of a journey is a transfer edge, so the search counts it
   in `cost.transfers`, but the display counts vehicle changes only
   (`legs.count - 1`). Where two routes tie on `cost.transfers`, the card
   labelled "En Az Aktarma" can show a *higher* number than the card beside it
   (reproducible: 15 Temmuz → Cevizlibağ-AÖY). Pinned by
   `transferCountCanDisagreeWithItsLabel`. Fix is a product decision: either
   count end-walks on screen too, or re-assign the three labels from the
   displayed metrics after the search.
3. ~~**A walk endpoint borrowed the ridden line's identity.**~~ Fixed
   2026-09-12. A journey starting at Zincirlikuyu (a Metrobüs stop) rendered
   it as "Zincirlikuyu (M2)" in M2 green, because the row was labelled with the
   line boarded *after* the 15-minute walk to Gayrettepe. `Route` now carries
   `originLines` / `destinationLines` and the view uses a `.walkEndpoint` kind.
   Pinned by `walkEndpointKeepsItsOwnLines`.
4. **F3 is unreachable by design.** Seyrantepe is a surface entrance near the
   M2 corridor, not an M2 stop, so F3's two stations connect to nothing. The
   line is therefore inert in the app.

---

### 7.3. Standing decisions

Judgment calls made while building, listed so they are overturned deliberately
rather than by accident.

1. **Fewer than 3 cards when criteria agree.** One path, both labels — never a
   duplicated row.
2. **Displayed total time includes transfer penalties.** The honest number, and
   the same one the search optimised.
3. **Virtual START/END folded into seeding.** §4.2 describes 0-weight edges
   from a START node; implemented equivalently as multi-source seeding and
   multi-target termination, so the graph is built once and reused per query.
4. **Criteria are orderings, not weight hacks.** `fewestTransfers` compares
   `(transfers, minutes, stops)` lexicographically — no magic constants, exact
   ties, no overflow.
5. **Topology lives entirely in `segments`.** No per-line ordered station list,
   so there is nothing to drift out of sync. A line's running order (used only
   to name the direction) is derived by `LineTopology`.
6. **Nodes exist only where a line actually stops**, so no phantom transfers at
   stations a line passes without serving.
7. **Branching lines are separate line ids**, and changing between them costs a
   transfer. Riding the shared trunk does not: both platforms exist at every
   trunk station and the search seeds both at zero.
8. **Travel times are `Double` minutes.** Tram and funicular hops are 2.5 min.
   Half-minutes are exact in binary floating point, so the lexicographic cost
   comparisons need no epsilon. *(Supersedes the earlier "whole minutes only"
   decision, which was taken before tram data arrived.)*
9. **Station identity is never inferred from names.** Similarity produces
   review candidates; explicit tables decide. See `DATA_SCHEMA.md` §4.
10. **Official names are never rewritten.** Stations that are one interchange
    keep both names and share a `complexId`; stations that share a name but are
    different places keep the name and get distinct ids. Disambiguation for the
    picker happens at display time only.
11. **A journey may begin or end with a walk.** `Route` carries the requested
    `origin`/`destination` plus `leadingWalkMinutes` / `trailingWalkMinutes`;
    without this a route would appear to start at the boarding station and
    silently swallow 15 minutes.

---

### 7.4. Testing

Two targets in the Xcode project — `xcodebuild test -scheme EnKisaYolculuk`, or
⌘U:

- **`EnKisaYolculukTests`** — 137 Swift Testing cases. Fixture-driven units
  (`Support/Fixtures.swift` builds small networks from JSON, including a
  `penaltyTrap` fixture that fails if the penalty ever leaves the search), plus
  `RealNetworkTests` asserting against the shipped `network.json`.
- **`EnKisaYolculukUITests`** — 14 XCUITest cases driving the real app: splash,
  station search, the three alternatives, the step-by-step detail, swap,
  back-and-search-again, and the unreachable-pair error.

Two things to know before adding more:

- **UI tests address elements by accessibility identifier**, not visible text
  (`originPicker`, `findRoutes`, `stationOption`, `routingError`, …). Those
  identifiers are part of the views; keep them.
- **Wait for hittability, not existence.** For a beat after the splash fades
  the rows exist but silently drop taps. `AppUITestCase.waitForPicker()`
  handles it; every flow test must go through it.

`Tools/verify.sh` remains the no-Xcode path for checking a regenerated data
file.

---

### 7.5. How the data arrived

| Date | Batch | Result |
|---|---|---|
| 2026-09-11 | Scaffold + placeholder data | 3 lines, 4 stations |
| 2026-09-12 | Metro M1A–M11 | 11 lines, 156 stations. Europe and Asia disconnected — Marmaray was still out of scope. |
| 2026-09-12 | Tram + funicular | 20 lines, 229 stations. `complexId` introduced; times widened to `Double`. |
| 2026-09-12 | Marmaray | 21 lines, 263 stations. `customTransferPenalties` and `VERIFIED_SEPARATE_BY_LINE` introduced; the two sides joined. |
| 2026-09-12 | Metrobüs | 22 lines, 307 stations. Penalty entries gained the power to establish a link; walks at the ends of a journey surfaced. |
| 2026-09-12 | Test suite | 137 unit + 14 UI tests. Found that the 307-item `Picker` never opened; replaced with a searchable list. |

---

## 8. Decision Summary Table

| Topic | Decision | Note |
|-------|----------|------|
| Language/Platform | Swift + SwiftUI | Closed |
| Graph direction | Undirected | Both directions, same time |
| Line ↔ Station | Many-to-many association | NOT inheritance |
| Data storage | JSON in bundle | No DB (except user data) |
| Route algorithm | Line-expanded graph + Dijkstra | Penalty inside the search |
| Transfer penalty | 10 min default, per-pair overrides | 28 overrides, all 15 min |
| 3 routes | By criteria | Shipped; not k-shortest |
| Travel times | `Double` minutes | Tram/funicular hops are 2.5 |
| Station identity | Explicit verified tables | Never inferred from names |
| Network scope | Metro + tram + funicular + Marmaray + Metrobüs | Ferries/buses out |
| Main risk | Data quality | Confirmed — every real bug was a data-modelling one |
