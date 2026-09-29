# AGENTS.md — En Kısa Yolculuk

> Every AI agent working on this project must read **this file first, then
> `CONTEXT.md`**. Goal: take the decisions and rules from one place instead of
> re-learning the project from scratch (and burning tokens) every session.

---

## How to Start (every session)
1. Read this `AGENTS.md` (rules + working style).
2. Read `CONTEXT.md` (all technical decisions and their rationale).
   `CONTEXT.md` §7 is the current state, the open questions and the known
   issues — start there.
3. If the task touches the network data, read `DATA_SCHEMA.md` too.
4. Review the current structure, then start the task.

Do not reopen a topic that these files have already settled.

---

## The Project in One Sentence
A native iPhone (Swift + SwiftUI) route finder for Istanbul rail and Metrobüs:
the user picks a start and end station, the app shows 3 alternative routes, and
each route reports total time, transfer count and stop count.

---

## Where Things Live

```
EnKisaYolculuk/          the app
  Models/                Station, Line, Segment, MetroNetwork, Route, penalties
  Graph/                 LineExpandedGraph, Dijkstra, LineTopology
  Models/Chauffeur       the personal "ride with me" strings
  Services/              NetworkLoader, RouteService, AppState, LocationProvider
  Views/                 Splash, StationPicker, StationSelection, RouteList, RouteDetail
  Views/RideWithMe*      the personal card and its screen (presentation only)
  Data/network.json      GENERATED — never hand-edit
  Data/contact.json      GITIGNORED — the real phone number; see contact.example.json
Data/source/lines.txt    the hand-written network listing
Tools/                   build_network.py, verify.sh, route.sh
EnKisaYolculukTests/     143 unit tests
EnKisaYolculukUITests/   18 UI tests
```

⚠️ **This repository is public.** Never write the phone number, or any other
personal detail, into a tracked file. It belongs in `Data/contact.json`.

```bash
Tools/build_network.py --check                  # parse the data, report, write nothing
Tools/build_network.py                          # regenerate network.json
Tools/verify.sh                                 # assert known routes, no Xcode needed
Tools/route.sh yenikapi kirazli                 # spot-check one journey
xcodebuild test -project EnKisaYolculuk.xcodeproj \
  -scheme EnKisaYolculuk -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## Closed Decisions (do not reopen unless the user says otherwise)
- **Platform/Language:** Swift + SwiftUI. (Python/TS/RN were ruled out —
  rationale in CONTEXT.md.)
- **Graph:** undirected, weighted (edge = travel time).
- **Line-Station:** many-to-many association — **not** inheritance.
- **Data storage:** JSON in the bundle, **no DB** (except user data).
- **Route algorithm:** line-expanded graph + Dijkstra; the transfer penalty is
  **inside** the search, never added afterwards.
- **3 routes by criteria** (fastest / fewest transfers / fewest stops), not
  k-shortest.
- **Transfer penalty:** 10 min default, with per-pair overrides in
  `customTransferPenalties`.
- **Travel times are `Double` minutes** — tram and funicular hops are 2.5.
- **Network scope:** metro, tram, funicular, Marmaray, Metrobüs. Ferries and
  buses are out.
- **Station identity is never inferred from names.** Explicit verified tables
  decide; see `DATA_SCHEMA.md` §4.
- **Official station names are never rewritten.** Disambiguation happens at
  display time only.

---

## Known Pitfalls to Avoid

Algorithm:
- ❌ Adding the transfer penalty **after** Dijkstra → picks the wrong path.
  There is a `penaltyTrap` test fixture that fails if this regresses.
- ❌ Making Line a superclass and Station a subclass → multiple-inheritance mess.
- ❌ Setting up a database for static data → over-engineering.
- ❌ Forgetting that plain Dijkstra returns one path and skipping the "3 routes"
  requirement.
- ❌ Trusting the "n lines → n−1 transfers" formula → miscounts the A→B→A case.
  The line-expanded model does not need it; there is a test for this.

Data (this is where every real bug has come from):
- ❌ Letting two stations merge because they share a name. Marmaray and M4 both
  stop at a "Göztepe" and they are different places. Silent, and it invents a
  transfer.
- ❌ Assuming a same-named pair is an interchange, or that a differently-named
  pair is not. Both happen. Only the verified tables decide.
- ❌ Hand-editing `network.json`. It is generated from `Data/source/lines.txt`.
- ❌ Leaving an unresolved similar-name candidate in the build report. Rule on
  every one of them.

Tests / UI:
- ❌ Writing a UI test that waits for an element to *exist* before tapping. For
  a beat after the splash fades the rows exist but drop taps. Go through
  `AppUITestCase.waitForPicker()`.
- ❌ Addressing UI elements by visible text. Use the accessibility identifiers.
- ❌ Carrying an expected number over from an older batch without re-deriving
  it. Adding a line changes the fastest route between existing stations.

---

## Working Style (user preferences)
- On coding work, act as a **collaborating engineer, not a teacher**.
- Provide explanations **only when asked**; don't launch into long write-ups
  unprompted.
- Give **objective, critical** feedback; no unnecessary optimism. If a decision
  is weak or there's a pitfall, say so plainly.
- User's technical background: Java/OOP, Python, SQL; 3rd-year Computer
  Engineering student. Don't explain basic concepts from scratch — get to the
  point.
- The user writes in Turkish and expects replies in Turkish. Code, comments and
  these documents stay in English.

---

## Before Changing Anything
If you're proposing a change to one of the closed decisions above:
1. Briefly justify which decision you're changing and why.
2. Get the user's approval.
3. If approved, update `CONTEXT.md` (and this file if needed) so later sessions
   stay consistent.

If you see an inconsistency between the decision files and the code, don't
silently pick one — flag it to the user.

When you finish a batch of work, update the relevant `.md` file in the same
session. `CONTEXT.md` §7 is the part that goes stale fastest.

---

## Open Work
Current open questions are in `CONTEXT.md` §7.1, and known issues — including
two that are real and unfixed — are in §7.2. When a new uncertainty comes up,
add it there.
