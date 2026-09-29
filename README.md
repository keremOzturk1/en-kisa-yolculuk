# En Kısa Yolculuk

A native iPhone route finder for the Istanbul rail network and Metrobüs. Pick a
start and end station; the app offers three alternatives — fastest, fewest
transfers, fewest stops — each with its total time, transfer count and
step-by-step directions.

**22 lines · 307 stations · 329 segments · 55 transfer points.**
Swift 5 / SwiftUI, iOS 17+, no third-party dependencies.

---

## Running it

```bash
open EnKisaYolculuk.xcodeproj      # then ⌘R
```

Or from the command line:

```bash
xcodebuild -project EnKisaYolculuk.xcodeproj -scheme EnKisaYolculuk \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## First build after a clone

One file is deliberately not in this repository. The "seni ben götüreyim"
screen dials a real phone number, and this repo is public, so the number lives
in a gitignored file:

```bash
cp EnKisaYolculuk/Data/contact.example.json EnKisaYolculuk/Data/contact.json
# then put the real number in it, country code included, no spaces
```

Without it the app still builds and runs — the call/message/location buttons
simply stay disabled and say why. `RideWithMeUITests.testThePhoneNumberIsConfigured`
fails until the file exists, which is the intended reminder.

---

## Testing

```bash
xcodebuild test -project EnKisaYolculuk.xcodeproj -scheme EnKisaYolculuk \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

143 unit tests (Swift Testing) and 18 UI tests (XCUITest). `Tools/verify.sh`
runs the routing assertions without Xcode, against Command Line Tools alone.

---

## Releasing to TestFlight

The app is distributed through TestFlight only. Signing is automatic and uses
the Apple ID signed in to Xcode (Settings → Accounts); no API key is needed.

1. **Bump `CURRENT_PROJECT_VERSION`** in the app target (and in `project.yml`).
   App Store Connect rejects a build number it has already seen. Uploaded so
   far: 1.0 (1), 1.0 (2).
2. **Make sure `EnKisaYolculuk/Data/contact.json` exists.** It is gitignored,
   and an archive built without it ships a ride-with-me screen whose buttons
   are all disabled. `RideWithMeUITests.testThePhoneNumberIsConfigured` catches
   this.
3. Archive and upload:

```bash
A=~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/EnKisaYolculuk.xcarchive
xcodebuild archive -project EnKisaYolculuk.xcodeproj -scheme EnKisaYolculuk \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$A" -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath "$A" \
  -exportOptionsPlist Tools/ExportOptions.plist \
  -exportPath /tmp/EnKisaYolculuk-export -allowProvisioningUpdates
```

Or in Xcode: Product → Archive, then Distribute App → App Store Connect.

Processing takes a few minutes to half an hour. The build carries
`ITSAppUsesNonExemptEncryption = NO` (the app has no networking and no
cryptography), so it needs no export-compliance answer before testers get it.

---

## How it works

Routing is a **line-expanded graph**: each node is a `(station, line)` pair —
one platform. Riding one hop is an edge weighted with the travel time; changing
lines inside a station is an edge weighted with the transfer penalty.

That shape matters. Plain Dijkstra on travel time alone will happily pick a
path that saves two minutes by making three changes. Because the penalty is an
edge weight *inside* the search, the chosen path is correct — not just the
number printed next to it. Adding the penalty afterwards fixes the display and
leaves the route wrong.

It also removes a class of special cases: a station on four lines is simply
four nodes, the lines used are read straight off the path, and an A→B→A journey
counts two transfers without anyone detecting anything.

The three alternatives are three runs over the same graph under three
lexicographic orderings of `(minutes, transfers, stops)` — not a k-shortest
search, so the user gets genuinely different options rather than three
near-identical ones.

```
EnKisaYolculuk/
  Models/      Station, Line, Segment, MetroNetwork, Route, TransferPenaltyOverride
  Graph/       LineExpandedGraph, Dijkstra, LineTopology
  Services/    NetworkLoader, RouteService, AppState
  Views/       Splash, StationPicker, StationSelection, RouteList, RouteDetail
  Data/        network.json  ← generated, never hand-edited
```

---

## The data

The network is hand-compiled as a plain-text listing and compiled into the JSON
the app ships with:

```
Data/source/lines.txt  →  Tools/build_network.py  →  EnKisaYolculuk/Data/network.json
```

```bash
Tools/build_network.py --check    # parse and report, write nothing
Tools/build_network.py            # regenerate network.json
Tools/route.sh yenikapi kirazli   # spot-check one journey
```

The hard part of this project was never the algorithm — it was deciding when
two stations are one place. Marmaray and M4 both stop at a "Göztepe" and they
are different places; M7 "Mecidiyeköy" and M2 "Şişli-Mecidiyeköy" are the same
place. Name similarity therefore never merges anything: it only raises
candidates, and explicit verified tables decide. Interchanges split across two
official names keep both names and share a `complexId`.

Full rules in **[DATA_SCHEMA.md](DATA_SCHEMA.md)**.

---

## Documentation

| File | What it is |
|---|---|
| [AGENTS.md](AGENTS.md) | Rules, closed decisions, pitfalls. Read first. |
| [CONTEXT.md](CONTEXT.md) | Technical decisions and why. §7 is the current state, open questions and known issues. |
| [DATA_SCHEMA.md](DATA_SCHEMA.md) | The data pipeline, the JSON schema, and how station identity is decided. |

---

## Known limitations

- **F3 (Seyrantepe–Vadistanbul) is unreachable by design.** Seyrantepe is a
  surface entrance near the M2 corridor, not an M2 stop, so the line connects
  to nothing and is inert in the app.
- **"Fewest stops" can be pathological** — it will trade 40 minutes and 4
  transfers to save one stop. See CONTEXT.md §7.2.
- **A route's displayed transfer count can disagree with its own label** when
  the journey begins or ends with a walk. Also §7.2.
- Travel times are the user's figures, not a live feed. There are no
  timetables, no service hours and no disruptions.
