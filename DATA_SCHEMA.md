# DATA_SCHEMA.md — the network data

How the network data is written, how it is compiled, and every rule that
decides whether two stations are one place or two.

Current contents: **22 lines · 307 stations · 329 segments · 55 transfer
points**.

---

## 1. The pipeline

```
Data/source/lines.txt        the thing a human writes
        │
        │  Tools/build_network.py        (+ the verified mapping tables in it)
        ▼
EnKisaYolculuk/Data/network.json         the compiled artefact, shipped in the bundle
        │
        │  NetworkLoader.load()  →  MetroNetwork.validate()
        ▼
LineExpandedGraph → Dijkstra → RouteService
```

**Never hand-edit `network.json`.** It is generated. Edit `lines.txt` (for
stations, lines and times) or the tables in `build_network.py` (for anything
about *relationships between* stations), then regenerate.

```bash
Tools/build_network.py --check      # parse + report, write nothing
Tools/build_network.py              # write EnKisaYolculuk/Data/network.json
Tools/verify.sh                     # assert known routes, no Xcode needed
Tools/route.sh                      # list every station id and its lines
Tools/route.sh yenikapi kirazli     # spot-check one journey
```

---

## 2. The source format (`Data/source/lines.txt`)

One block per line of the network. Working reference:
`Data/source/example.txt`.

```
LINE: M2 | M2 Yenikapı – Hacıosman | #009A44
DEFAULT: 2
Yenikapı
Vezneciler-İstanbul Üniversitesi
Şişhane
Taksim | 3
Osmanbey
```

| Row | Meaning |
|---|---|
| `LINE: id \| name \| #RRGGBB` | Starts a block. Only `id` is required. |
| `DEFAULT: n` | Minutes between consecutive stations on this line. Optional if every hop is explicit. |
| `Station Name` | One per row, **in running order**. Uses `DEFAULT`. |
| `Station Name \| n` | Minutes **from the previous station**, overriding `DEFAULT`. |
| `# …` | Comment. Blank rows ignored. |

The first station of a block never carries a time. Fractional minutes are
allowed (`2.5`, `2,5`) and are stored exactly — tram and funicular hops are
2.5 min.

**Station ids are generated from names** by folding Turkish letters and
slugifying: `Ayrılık Çeşmesi` → `ayrilik_cesmesi`. You never write ids by hand.

---

## 3. `network.json`

```json
{
  "version": 1,
  "transferPenaltyMinutes": 10,
  "stations": [
    { "id": "mecidiyekoy", "name": "Mecidiyeköy", "complexId": "cx_mecidiyekoy" }
  ],
  "lines": [
    { "id": "M2", "name": "M2 Yenikapı – Hacıosman", "colorHex": "#009A44" }
  ],
  "segments": [
    { "line": "M2", "from": "yenikapi", "to": "vezneciler_istanbul_universitesi", "minutes": 2 }
  ],
  "customTransferPenalties": [
    { "stationA": "bakirkoy", "lineA": "Marmaray",
      "stationB": "ozgurluk_meydani", "lineB": "M3", "minutes": 15 }
  ]
}
```

Unknown keys are ignored, so annotations (`"_comment"`) are safe to leave in.

### Top level

| Key | Type | Required | Meaning |
|---|---|---|---|
| `version` | Int | yes | Schema version. Currently `1`. |
| `transferPenaltyMinutes` | Double ≥ 0 | yes | Default transfer cost. Lives in the data, so tuning it needs no rebuild. |
| `stations` | Array | yes | Every station, once. |
| `lines` | Array | yes | Every line, once. |
| `segments` | Array | yes | Every adjacent-station hop. **This is the whole topology.** |
| `customTransferPenalties` | Array | no | Per-pair exceptions. See §5. |

### `stations[]`

| Key | Type | Required | Meaning |
|---|---|---|---|
| `id` | String | yes | Stable, unique, ASCII. Generated from the name. |
| `name` | String | yes | **Official** display name, full Turkish characters. |
| `complexId` | String | no | Shared by stations forming one interchange under different names. See §4. |
| `latitude` / `longitude` | Double | no | For a future map view. |

### `lines[]`

| Key | Type | Required | Meaning |
|---|---|---|---|
| `id` | String | yes | `M4`, `T1`, `F2`, `Marmaray`, `Metrobüs`. |
| `name` | String | yes | Display name. |
| `colorHex` | String | no | `"#RRGGBB"`. Falls back to the app accent if missing or malformed. |

### `segments[]`

| Key | Type | Required | Meaning |
|---|---|---|---|
| `line` | String | yes | Must match a `lines[].id`. |
| `from` / `to` | String | yes | Must match a `stations[].id`. |
| `minutes` | Double ≥ 0 | yes | Travel time for this one hop. |

Segments are **undirected** — one row per hop, not per direction. The graph
builder adds the reverse edge.

---

## 4. Is it one station or two?

This is where the real work is, and **name similarity never decides it.**
Similarity only produces *review candidates*; the tables in
`Tools/build_network.py` are the only source of truth.

Four cases, in the order the build applies them:

### 4.1. Identical names → one station, automatically

Two blocks spelling a station the same way produce one station on two lines.
That is what makes an interchange. Nothing to declare.

### 4.2. `VERIFIED_SAME_COMPLEX` → one interchange, two names

M7 `Mecidiyeköy` and M2 `Şişli-Mecidiyeköy` are one place. They keep **both
ids and both official names** and gain a shared `complexId`:

```json
{ "id": "mecidiyekoy",       "name": "Mecidiyeköy",       "complexId": "cx_mecidiyekoy" },
{ "id": "sisli_mecidiyekoy", "name": "Şişli-Mecidiyeköy", "complexId": "cx_mecidiyekoy" }
```

`LineExpandedGraph` groups platforms by `complexId ?? id`, so every platform in
the complex gets a normal transfer edge. The UI shows both names
("Mecidiyeköy → Şişli-Mecidiyeköy") and the picker qualifies them where a bare
name would appear twice. **28 complexes are declared.**

### 4.3. `VERIFIED_SEPARATE_BY_LINE` → same name, different place

The mirror image. Ids come from names, so Marmaray's `Göztepe` would otherwise
silently merge with M4's `Göztepe` and invent a transfer between lines that
never meet. Declaring `(name, line)` gives that station its own id
(`goztepe_marmaray`) while its `name` stays the official `Göztepe`.

Currently declared: Marmaray's Göztepe, Maltepe, Kartal, Pendik, Küçükyalı and
Yenimahalle; and 15 Metrobüs stops that share a name with the rail station
beside them (Zeytinburnu, Mecidiyeköy, İncirli, Florya, …).

### 4.4. `VERIFIED_DISTINCT` → similar, but definitively not the same

31 pairs that keep getting flagged and must not be merged — `Halkalı` /
`Halkalı Caddesi`, `Levent` / `4.Levent`, `Soğanlı` / `Soğanlık`, and so on.
Listing them here stops the detector reporting them every run.

### Automatic resolutions

Two rules settle candidates without a manual entry:

- **A line stops once per place.** Two stations served by a line in common are
  necessarily two places, so `Haramidere` / `Haramidere Sanayi` needs no entry.
  An explicit complex declaration still wins — T1 stops at both `Aksaray` and
  `Yusufpaşa`, which *are* declared one interchange.
- **A declared split** makes a shared name an explicit decision, not a
  candidate.

Anything still unresolved is printed by `build_network.py` for a human to rule
on. **It is never auto-merged.** The current count is 0.

---

## 5. Transfer costs

Every transfer costs `transferPenaltyMinutes` (10) unless a
`customTransferPenalties` entry says otherwise. **28 entries are declared, all
15 minutes** — walking transfers, almost all of them Metrobüs ↔ rail.

```json
{ "stationId": "yenikapi", "lineA": "M1A", "lineB": "M2", "minutes": 14 }
{ "stationA": "bakirkoy",  "lineA": "Marmaray",
  "stationB": "ozgurluk_meydani", "lineB": "M3", "minutes": 15 }
```

| Key | Required | Meaning |
|---|---|---|
| `stationId` | one of | Both platforms are at this station. |
| `stationA` / `stationB` | one of | The transfer spans two stations. |
| `lineA` / `lineB` | yes | The two lines being changed between. |
| `minutes` | yes | Double ≥ 0. Replaces the default. |

Matching is direction-independent.

**An entry naming two different stations also *establishes* the link** — the
build unions them into one complex, so the edge exists and this is its weight.
That is why the 25 cross-name Metrobüs transfers need one table entry each
rather than two.

---

## 6. What the loader rejects

`MetroNetwork.validate()` runs at every launch and fails loudly rather than
routing on bad data:

- duplicate `stations[].id` or `lines[].id`;
- a segment naming a station or line that does not exist;
- `minutes` < 0 (Dijkstra requires non-negative weights);
- a segment with `from == to`;
- `transferPenaltyMinutes` < 0;
- an override naming no station, an unknown station, an unknown line, or
  negative minutes.

`build_network.py` additionally reports, without failing: disconnected parts of
the network, unresolved similar-name candidates, and mappings that reference
stations which do not exist.

---

## 7. Known properties of the current data

- **The network is in two parts.** 305 stations are mutually reachable; **F3
  (Seyrantepe–Vadistanbul, 2 stations) is deliberately isolated** — Seyrantepe
  is a surface entrance near the M2 corridor, not an M2 stop, so no transfer
  edge exists and nothing can route to or from F3.
- **Line colours come from the user's stated list**, not from the hex values
  originally written in the `LINE:` headers, which contradicted it. M1A and M1B
  are deliberately the same red.
- **Branching lines are separate line ids** (M1A/M1B). Riding the shared trunk
  costs no transfer — both platforms exist at every trunk station and the
  search seeds both at zero — but a genuine M1A→M1B change is charged, which
  matches reality.
- **Six station names belong to two different places each.** The picker
  qualifies those rows with their lines ("Göztepe (M4)" / "Göztepe
  (Marmaray)"); the stored names are untouched.

---

## 8. Adding the next batch

1. Append the `LINE:` blocks to `Data/source/lines.txt`.
2. Run `Tools/build_network.py --check` and read the report.
3. Rule on every unresolved similar-name candidate — add each to
   `VERIFIED_SAME_COMPLEX`, `VERIFIED_DISTINCT`, or
   `VERIFIED_SEPARATE_BY_LINE`. Do not leave any unresolved.
4. Add any non-default transfer costs to `CUSTOM_TRANSFER_PENALTIES`.
5. Run `Tools/build_network.py` to write the JSON.
6. Update the expected counts in `EnKisaYolculukTests/RealNetworkTests.swift`
   and run the suite.

The single likeliest mistake is a station that should have been split or
complexed and instead merged by name. It is silent — it invents or deletes a
transfer — which is why step 3 is not optional.
