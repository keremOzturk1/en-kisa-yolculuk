#!/usr/bin/env python3
"""
Converts the human-written line listing (Data/source/lines.txt) into
EnKisaYolculuk/Data/network.json.

Data prep only — not app code (CONTEXT §2 permits Python for exactly this).

    Tools/build_network.py                      # source -> network.json
    Tools/build_network.py --check              # parse + report, write nothing

Input format, one block per line of the network:

    # comments and blank lines are ignored

    LINE: M2 | M2 Yenikapı – Hacıosman | #E30613
    DEFAULT: 2
    Yenikapı
    Vezneciler
    Haliç
    Şişhane
    Taksim | 3
    Osmanbey

  LINE:     starts a block.  id | display name | colorHex
            Only the id is required; name defaults to the id, colour to none.
  DEFAULT:  minutes between two consecutive stations on this line. Optional if
            every station carries its own explicit time.
  station   one per row, in running order.
  | n       minutes from the PREVIOUS station, overriding DEFAULT.
            The first station of a block never takes a time.

Interchanges need no special syntax: the same station spelled the same way in
two blocks becomes one station on two lines. That spelling is the only thing
that has to be exact, so the script warns about near-miss names.
"""

from __future__ import annotations

import argparse
import difflib
import json
import math
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "Data" / "source" / "lines.txt"
DEFAULT_OUTPUT = ROOT / "EnKisaYolculuk" / "Data" / "network.json"

# Turkish letters that must be folded *before* lowercasing ("İ".lower() grows a
# combining dot in Python, which would produce two ids for one station).
TR_FOLD = str.maketrans({
    "ç": "c", "Ç": "c", "ğ": "g", "Ğ": "g", "ı": "i", "I": "i",
    "İ": "i", "i": "i", "ö": "o", "Ö": "o", "ş": "s", "Ş": "s",
    "ü": "u", "Ü": "u", "â": "a", "Â": "a", "î": "i", "Î": "i",
    "û": "u", "Û": "u", "é": "e", "É": "e",
})


# ---------------------------------------------------------------------------
# Verified station mappings.
#
# Name similarity NEVER merges stations. It only produces review candidates.
# The two tables below are the only source of truth about whether two
# differently-named stations are the same place.
# ---------------------------------------------------------------------------

# Stations that are one interchange complex under different official names.
# Each group keeps its own station ids and its own names; they gain a shared
# complexId so the graph links their platforms with real transfer edges.
VERIFIED_SAME_COMPLEX: list[list[str]] = [
    # --- metro, verified 2026-09-12 ---
    ["Mecidiyeköy", "Şişli-Mecidiyeköy"],
    ["İncirli", "Bakırköy-İncirli"],
    ["Kayaşehir", "Kayaşehir Merkez"],
    ["Olimpiyat", "Olimpiyatköy"],
    # --- tram / funicular batch, verified 2026-09-12 ---
    ["Laleli-İstanbul Ü.", "Vezneciler-İstanbul Üniversitesi"],
    ["Yusufpaşa", "Aksaray"],
    ["Vatan", "Topkapı-Ulubatlı"],
    ["Kiptaş-Venezia", "Karadeniz Mahallesi"],
    ["Küçükpazar", "Haliç"],
    ["Alibeyköy Metro", "Alibeyköy"],
    # --- Marmaray batch, verified 2026-09-12 ---
    # A 15 min walk, not a same-building change — see CUSTOM_TRANSFER_PENALTIES.
    ["Bakırköy", "Özgürlük Meydanı"],
]

# Pairs that look similar but are definitively different places. Listed here so
# the detector stops reporting them as unresolved every run.
VERIFIED_DISTINCT: list[tuple[str, str]] = [
    ("Halkalı", "Halkalı Caddesi"),
    ("Ataköy", "Ataköy-Şirinevler"),
    ("Levent", "4.Levent"),
    ("Maltepe", "Bayrampaşa-Maltepe"),
    ("Göztepe", "Göztepe Mahallesi"),
    ("Veysel Karani", "Veysel Karani-Akşemsettin"),
    ("Çakmak", "Fevzi Çakmak-Hastane"),
    ("Halkalı", "Halkalı Stadı"),
    ("Sancaktepe", "Sancaktepe Şehir Hastanesi"),
    ("Şehir Hastanesi", "Sancaktepe Şehir Hastanesi"),
    # --- tram / funicular batch ---
    ("Topkapı", "Topkapı-Ulubatlı"),
    ("Karadeniz", "Karadeniz Mahallesi"),
    ("Merter", "Merter Tekstil Merkezi"),
    ("Mimar Sinan", "Fındıklı-Mimar Sinan Ü."),
    ("Alibeyköy", "Alibeyköy Merkez"),
    ("Alibeyköy", "Alibeyköy Cep Otogarı"),
    ("Alibeyköy Merkez", "Alibeyköy Metro"),
    ("Alibeyköy Metro", "Alibeyköy Cep Otogarı"),
    ("Alibeyköy Merkez", "Alibeyköy Cep Otogarı"),
    # T1 Soğanlı is in Bağcılar (European side); M4 Soğanlık is in Kartal
    # (Anatolian side). Different continents — independently verifiable.
    ("Soğanlı", "Soğanlık"),
    # --- Marmaray batch ---
    # Marmaray Bakırköy is the coastal station; M1A Bakırköy-İncirli is inland.
    ("Bakırköy", "Bakırköy-İncirli"),
    # The M3 station that meets Marmaray Bakırköy is Özgürlük Meydanı (see
    # CUSTOM_TRANSFER_PENALTIES), not the M3 terminus Bakırköy Sahil.
    ("Bakırköy", "Bakırköy Sahil"),
    # Marmaray Başak is in Kartal; M3 Başak Konutları is in Başakşehir.
    ("Başak", "Başak Konutları"),
    # Marmaray Maltepe (Anatolian) vs M1A Bayrampaşa-Maltepe (European).
    ("Maltepe", "Bayrampaşa-Maltepe"),
    # Marmaray Fatih is out past Gebze; M1A Emniyet-Fatih is in Istanbul Fatih.
    ("Fatih", "Emniyet-Fatih"),
    # Consecutive Marmaray stops, so trivially not the same place.
    ("Florya", "Florya Akvaryum"),
    # Marmaray Göztepe (Anatolian) vs M7 Göztepe Mahallesi (Bağcılar).
    ("Göztepe", "Göztepe Mahallesi"),
    # --- Metrobüs batch ---
    # M9's 15 Temmuz is in Başakşehir; the Metrobüs stop is on the bridge.
    ("15 Temmuz", "15 Temmuz Şehitler Köprüsü"),
    # T5 Üniversite is in Alibeyköy; both Metrobüs stops are in Avcılar.
    ("Üniversite", "Avcılar Merkez-Üniversite Kampüsü"),
    ("Üniversite", "Cihangir-Üniversite Mahallesi"),
    # Marmaray Mustafa Kemal is near Halkalı; Metrobüs Mustafa Kemalpaşa is
    # in Avcılar.
    ("Mustafa Kemal", "Mustafa Kemalpaşa"),
]


# Stations that SHARE A NAME with an existing station but are a different
# physical place. Station ids are derived from names, so without this table
# they would silently collapse into one node and invent a transfer.
#
# The station keeps its official `name`; only its generated id gets the line
# suffix. (station name, line id) -> id becomes "<name slug>_<line slug>".
VERIFIED_SEPARATE_BY_LINE: set[tuple[str, str]] = {
    # Marmaray runs parallel to M4 down the Anatolian coast, stopping at
    # similarly-named but physically separate stations.
    ("Göztepe", "Marmaray"),
    ("Maltepe", "Marmaray"),
    ("Kartal", "Marmaray"),
    ("Pendik", "Marmaray"),
    ("Küçükyalı", "Marmaray"),
    # Different corridor from the M3/M7/T4 Yenimahalle.
    ("Yenimahalle", "Marmaray"),
    # Metrobüs runs on the motorway; every one of its stops is a separate
    # place from the like-named rail station — which is exactly why changing
    # between them is a 15 min walk rather than a same-building transfer.
    ("Cumhuriyet Mahallesi", "Metrobüs"),
    ("Küçükçekmece", "Metrobüs"),
    ("Florya", "Metrobüs"),
    ("Yenibosna", "Metrobüs"),
    ("Bahçelievler", "Metrobüs"),
    ("İncirli", "Metrobüs"),
    ("Zeytinburnu", "Metrobüs"),
    ("Merter", "Metrobüs"),
    ("Bayrampaşa-Maltepe", "Metrobüs"),
    ("Edirnekapı", "Metrobüs"),
    ("Çağlayan", "Metrobüs"),
    ("Mecidiyeköy", "Metrobüs"),
    ("Altunizade", "Metrobüs"),
    ("Acıbadem", "Metrobüs"),
    ("Söğütlüçeşme", "Metrobüs"),
}


def station_id(name: str, line: str) -> str:
    """Resolve (name, line) to a station id.

    Needed because a split station shares its name with the rail station it
    sits beside, so a name alone is ambiguous once Metrobüs is in the data.
    """
    if (name, line) in VERIFIED_SEPARATE_BY_LINE:
        return f"{slugify(name)}_{slugify(line)}"
    return slugify(name)

# Transfers that cost something other than the global penalty — long walks
# between platforms that are officially one interchange.
#
# An entry naming two DIFFERENT stations also *establishes* the link: the two
# stations are unioned into one complex so the transfer edge exists, and this
# weight is what it costs. Entries naming one station only re-weight an edge
# that already exists there.
#
# (station A, line A, station B, line B, minutes)
CUSTOM_TRANSFER_PENALTIES: list[tuple[str, str, str, str, float]] = [
    ("Bakırköy", "Marmaray", "Özgürlük Meydanı", "M3", 15),

    # --- Metrobüs: every rail interchange is a 15 min walk ---
    ("Şirinevler", "Metrobüs", "Ataköy-Şirinevler", "M1A", 15),
    ("İncirli", "Metrobüs", "Bakırköy-İncirli", "M1A", 15),
    ("İncirli", "Metrobüs", "İncirli", "M3", 15),
    ("Bahçelievler", "Metrobüs", "Bahçelievler", "M1A", 15),
    ("Merter", "Metrobüs", "Merter", "M1A", 15),
    ("Yenibosna", "Metrobüs", "Yenibosna", "M1A", 15),
    ("Yenibosna", "Metrobüs", "Yenibosna", "M9", 15),
    ("Zeytinburnu", "Metrobüs", "Zeytinburnu", "M1A", 15),
    ("Zeytinburnu", "Metrobüs", "Zeytinburnu", "T1", 15),
    # Not in the supplied list, but Marmaray also stops at that same rail
    # station, so the walk from the Metrobüs stop is identical. Flagged.
    ("Zeytinburnu", "Metrobüs", "Zeytinburnu", "Marmaray", 15),
    ("Cevizlibağ", "Metrobüs", "Cevizlibağ-AÖY", "T1", 15),
    ("Topkapı-Şehit Mustafa Cambaz", "Metrobüs", "Topkapı", "T1", 15),
    ("Topkapı-Şehit Mustafa Cambaz", "Metrobüs", "Topkapı", "T4", 15),
    ("Edirnekapı", "Metrobüs", "Edirnekapı", "T4", 15),
    ("Ayvansaray-Eyüpsultan", "Metrobüs", "Ayvansaray", "T5", 15),
    ("Çağlayan", "Metrobüs", "Çağlayan", "M7", 15),
    ("Mecidiyeköy", "Metrobüs", "Şişli-Mecidiyeköy", "M2", 15),
    ("Mecidiyeköy", "Metrobüs", "Mecidiyeköy", "M7", 15),
    ("Zincirlikuyu", "Metrobüs", "Gayrettepe", "M2", 15),
    ("Zincirlikuyu", "Metrobüs", "Gayrettepe", "M11", 15),
    ("Altunizade", "Metrobüs", "Altunizade", "M5", 15),
    ("Uzunçayır", "Metrobüs", "Ünalan", "M4", 15),
    ("Küçükçekmece", "Metrobüs", "Küçükçekmece", "Marmaray", 15),
    ("Söğütlüçeşme", "Metrobüs", "Söğütlüçeşme", "Marmaray", 15),
    ("Bayrampaşa-Maltepe", "Metrobüs", "Bayrampaşa-Maltepe", "M1A", 15),
    ("Bayrampaşa-Maltepe", "Metrobüs", "Bayrampaşa-Maltepe", "M1B", 15),
    ("Florya", "Metrobüs", "Florya", "Marmaray", 15),
]


class SourceError(Exception):
    pass


def slugify(name: str) -> str:
    """Station display name -> stable ascii id. Deterministic, so the same name
    always yields the same id and interchanges merge on their own."""
    folded = name.translate(TR_FOLD).lower()
    folded = unicodedata.normalize("NFKD", folded)
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch))
    slug = re.sub(r"[^a-z0-9]+", "_", folded).strip("_")
    if not slug:
        raise SourceError(f"Station name {name!r} produces an empty id.")
    return slug


def parse_minutes(raw: str, where: str) -> float:
    value = raw.strip().replace(",", ".")
    try:
        minutes = float(value)
    except ValueError:
        raise SourceError(f"{where}: {raw!r} is not a number.") from None
    if minutes < 0:
        raise SourceError(f"{where}: travel time cannot be negative ({minutes}).")
    return minutes


def parse(text: str):
    """-> (lines, blocks) where blocks is [(line_id, [(station_name, minutes_or_None)])]"""
    lines_meta: list[dict] = []
    blocks: list[tuple[str, list[tuple[str, float | None]]]] = []
    defaults: dict[str, float | None] = {}

    current_id: str | None = None
    current_stations: list[tuple[str, float | None]] = []

    for lineno, raw in enumerate(text.splitlines(), start=1):
        row = raw.strip()
        if not row or row.startswith("#"):
            continue
        where = f"line {lineno}"

        if row.upper().startswith("LINE:"):
            if current_id is not None:
                blocks.append((current_id, current_stations))
            parts = [p.strip() for p in row.split(":", 1)[1].split("|")]
            line_id = parts[0]
            if not line_id:
                raise SourceError(f"{where}: LINE: needs an id.")
            name = parts[1] if len(parts) > 1 and parts[1] else line_id
            color = parts[2] if len(parts) > 2 and parts[2] else None
            if color and not re.fullmatch(r"#?[0-9A-Fa-f]{6}", color):
                raise SourceError(f"{where}: {color!r} is not a #RRGGBB colour.")
            if color and not color.startswith("#"):
                color = "#" + color
            lines_meta.append({"id": line_id, "name": name, "colorHex": color})
            defaults[line_id] = None
            current_id, current_stations = line_id, []
            continue

        if row.upper().startswith("DEFAULT:"):
            if current_id is None:
                raise SourceError(f"{where}: DEFAULT: before any LINE:.")
            defaults[current_id] = parse_minutes(row.split(":", 1)[1], where)
            continue

        if current_id is None:
            raise SourceError(f"{where}: station {row!r} before any LINE:.")

        if "|" in row:
            name, _, minutes_raw = row.partition("|")
            current_stations.append((name.strip(), parse_minutes(minutes_raw, where)))
        else:
            current_stations.append((row, None))

    if current_id is not None:
        blocks.append((current_id, current_stations))
    if not blocks:
        raise SourceError("No LINE: blocks found.")
    return lines_meta, blocks, defaults


def build(lines_meta, blocks, defaults):
    stations: dict[str, str] = {}   # id -> display name
    segments: list[dict] = []
    warnings: list[str] = []
    fractional: list[str] = []

    for line_id, station_rows in blocks:
        if len(station_rows) < 2:
            raise SourceError(f"Line '{line_id}' has fewer than 2 stations.")

        ids: list[str] = []
        for name, _ in station_rows:
            # A station explicitly declared separate for this line gets its own
            # id, so an identical name on another line does not absorb it.
            if (name, line_id) in VERIFIED_SEPARATE_BY_LINE:
                sid = f"{slugify(name)}_{slugify(line_id)}"
                stations.setdefault(sid, name)
                ids.append(sid)
                continue
            sid = slugify(name)
            if sid in stations and stations[sid] != name:
                warnings.append(
                    f"'{name}' and '{stations[sid]}' both map to id '{sid}' — "
                    f"treated as the SAME station. Rename one if that is wrong."
                )
            stations.setdefault(sid, name)
            ids.append(sid)

        if len(set(ids)) != len(ids):
            dupes = {s for s in ids if ids.count(s) > 1}
            raise SourceError(f"Line '{line_id}' lists {sorted(dupes)} more than once.")

        for index in range(1, len(station_rows)):
            explicit = station_rows[index][1]
            minutes = explicit if explicit is not None else defaults.get(line_id)
            if minutes is None:
                raise SourceError(
                    f"Line '{line_id}': no time for "
                    f"'{station_rows[index - 1][0]}' -> '{station_rows[index][0]}' "
                    f"and the line has no DEFAULT:."
                )
            # Times are Double in the schema (tram/funicular hops are 2.5 min),
            # so fractional values are stored exactly — no rounding. Whole
            # numbers are written as ints purely to keep the JSON readable;
            # Swift decodes either into Double.
            stored = int(minutes) if float(minutes).is_integer() else minutes
            if not float(minutes).is_integer():
                fractional.append(
                    f"{line_id} {station_rows[index-1][0]} -> {station_rows[index][0]}: "
                    f"{minutes} min"
                )
            segments.append({
                "line": line_id,
                "from": ids[index - 1],
                "to": ids[index],
                "minutes": stored,
            })

    # --- Step 2: explicit verified alias mappings -> shared complexId --------
    # Resolve the custom penalties first: a penalty between two different
    # stations declares them one interchange, so it feeds the complex union.
    known_lines = {meta["id"] for meta in lines_meta}
    resolved_penalties: list[tuple[str, str, str, str, float]] = []
    for name_a, line_a, name_b, line_b, minutes in CUSTOM_TRANSFER_PENALTIES:
        id_a, id_b = station_id(name_a, line_a), station_id(name_b, line_b)
        problem = None
        if id_a not in stations:
            problem = f"unknown station '{name_a}' on '{line_a}'"
        elif id_b not in stations:
            problem = f"unknown station '{name_b}' on '{line_b}'"
        elif line_a not in known_lines:
            problem = f"unknown line '{line_a}'"
        elif line_b not in known_lines:
            problem = f"unknown line '{line_b}'"
        if problem:
            warnings.append(f"custom transfer penalty ignored — {problem}.")
            continue
        resolved_penalties.append((id_a, line_a, id_b, line_b, minutes))

    extra_groups = [[a, b] for a, _, b, _, _ in resolved_penalties if a != b]
    complex_of, complex_members, mapping_problems = assign_complexes(stations, extra_groups)
    warnings.extend(mapping_problems)

    # --- Step 3 + 4: classify every similar-name candidate -------------------
    # Detection never merges. It only sorts candidates into
    # already-resolved-same / already-resolved-distinct / needs-review.
    # Matched on names as well as ids: a split station's id carries a line
    # suffix (goztepe_marmaray) that the name-based table cannot predict.
    distinct_pairs = {
        tuple(sorted((slugify(a), slugify(b)))) for a, b in VERIFIED_DISTINCT
    }
    distinct_names = {tuple(sorted((a, b))) for a, b in VERIFIED_DISTINCT}
    # Ids declared separate-by-line; an identical name on another line is then
    # an explicit decision, not an unresolved candidate.
    split_ids = {
        f"{slugify(name)}_{slugify(line)}" for name, line in VERIFIED_SEPARATE_BY_LINE
    }

    # Which lines serve each station — used by the "a line stops once per
    # place" rule below.
    lines_at: dict[str, set[str]] = {}
    for seg in segments:
        lines_at.setdefault(seg["from"], set()).add(seg["line"])
        lines_at.setdefault(seg["to"], set()).add(seg["line"])

    # Keyed by id, not name — after a split two stations can share a name.
    ids_sorted = sorted(stations)
    tokens = {
        sid: {t for t in re.split(r"[^a-z0-9]+", stations[sid].translate(TR_FOLD).lower()) if t}
        for sid in ids_sorted
    }

    unresolved: list[str] = []
    for i, ida in enumerate(ids_sorted):
        for idb in ids_sorted[i + 1:]:
            a, b = stations[ida], stations[idb]
            ta, tb = tokens[ida], tokens[idb]
            subset = ta < tb or tb < ta
            similar = difflib.SequenceMatcher(None, a.lower(), b.lower()).ratio() >= 0.86
            if not (subset or similar):
                continue

            # Already declared the same complex…
            if complex_of.get(ida) is not None and complex_of.get(ida) == complex_of.get(idb):
                continue
            # …or already declared distinct…
            if tuple(sorted((ida, idb))) in distinct_pairs:
                continue
            if tuple(sorted((a, b))) in distinct_names:
                continue
            # …or deliberately split apart despite sharing a name…
            if (ida in split_ids or idb in split_ids) and a == b:
                continue
            # …or served by a line in common, which settles it: a line stops
            # once per place, so two stations it both serves are two places.
            # (An explicit complex declaration above still wins — T1 stops at
            # both Aksaray and Yusufpaşa, which are declared one interchange.)
            if lines_at.get(ida, set()) & lines_at.get(idb, set()):
                continue

            reason = "one name contains the other" if subset else "near-identical spelling"
            unresolved.append(
                f"'{a}' ({ida}) / '{b}' ({idb}) — {reason}. "
                f"REVIEW: add to VERIFIED_SAME_COMPLEX or VERIFIED_DISTINCT."
            )

    station_rows = []
    for sid, name in sorted(stations.items()):
        row = {"id": sid, "name": name}
        if sid in complex_of:
            row["complexId"] = complex_of[sid]
        station_rows.append(row)

    overrides = []
    for id_a, line_a, id_b, line_b, minutes in resolved_penalties:
        entry = {"lineA": line_a, "lineB": line_b, "minutes": minutes}
        if id_a == id_b:
            entry["stationId"] = id_a
        else:
            entry["stationA"], entry["stationB"] = id_a, id_b
        overrides.append(entry)

    network = {
        "version": 1,
        "transferPenaltyMinutes": 10.0,
        "stations": station_rows,
        "lines": [
            {k: v for k, v in meta.items() if v is not None}
            for meta in lines_meta
        ],
        "segments": segments,
        "customTransferPenalties": overrides,
    }
    return network, warnings, fractional, unresolved, complex_members


def assign_complexes(stations: dict[str, str], extra_groups: list[list[str]] | None = None):
    """Turn VERIFIED_SAME_COMPLEX into a station-id -> complexId map.

    `extra_groups` carries id pairs already resolved elsewhere — the
    cross-station custom penalties, which declare an interchange as well as
    pricing it.

    Groups that share a station are merged, so listing ("A","B") and ("B","C")
    yields one complex of three rather than two conflicting ones.
    """
    problems: list[str] = []
    known_ids = set(stations)

    # Union-find over the declared groups.
    parent: dict[str, str] = {}

    def find(x: str) -> str:
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x: str, y: str) -> None:
        rx, ry = find(x), find(y)
        if rx != ry:
            parent[ry] = rx

    for group in VERIFIED_SAME_COMPLEX:
        ids = []
        for name in group:
            sid = slugify(name)
            if sid not in known_ids:
                problems.append(
                    f"verified-same mapping names '{name}' ({sid}), which is not "
                    f"in the network — mapping ignored."
                )
                continue
            ids.append(sid)
        if len(ids) < 2:
            continue
        for other in ids[1:]:
            union(ids[0], other)

    for group in (extra_groups or []):
        for other in group[1:]:
            union(group[0], other)

    complex_of: dict[str, str] = {}
    members: dict[str, list[str]] = {}
    for sid in list(parent):
        root = find(sid)
        members.setdefault(root, []).append(sid)
    for root, group in members.items():
        if len(group) < 2:
            continue
        cid = "cx_" + root
        for sid in group:
            complex_of[sid] = cid

    named = {
        "cx_" + root: sorted(group)
        for root, group in members.items() if len(group) >= 2
    }
    return complex_of, named, problems


def transfer_group(station: dict) -> str:
    """Mirrors Station.transferGroup in Swift: the complex when there is one."""
    return station.get("complexId") or station["id"]


def interchanges(network):
    """Places where you can change lines — keyed by transfer complex, not by
    station id, so an interchange split across two official names counts once
    and lists every line reachable from it."""
    stations = {s["id"]: s for s in network["stations"]}
    lines_by_group: dict[str, set[str]] = {}
    names_by_group: dict[str, set[str]] = {}
    for seg in network["segments"]:
        for sid in (seg["from"], seg["to"]):
            group = transfer_group(stations[sid])
            lines_by_group.setdefault(group, set()).add(seg["line"])
            names_by_group.setdefault(group, set()).add(stations[sid]["name"])

    rows = []
    for group, lines in lines_by_group.items():
        if len(lines) < 2:
            continue
        label = " / ".join(sorted(names_by_group[group]))
        rows.append((label, sorted(lines)))
    return sorted(rows, key=lambda pair: (-len(pair[1]), pair[0]))


def components(network):
    """Connected components of the station graph, largest first.

    More than one means some station pairs have NO route at all — usually a
    missing link line rather than a typo, and worth shouting about because the
    app can only answer 'rota bulunamadı' for every pair that straddles them.
    """
    adjacency: dict[str, set[str]] = {}
    for segment in network["segments"]:
        adjacency.setdefault(segment["from"], set()).add(segment["to"])
        adjacency.setdefault(segment["to"], set()).add(segment["from"])

    # Stations of one complex are walkable between, so they are connected even
    # though no segment joins them.
    by_complex: dict[str, list[str]] = {}
    for station in network["stations"]:
        if station.get("complexId"):
            by_complex.setdefault(station["complexId"], []).append(station["id"])
    for group in by_complex.values():
        for a in group:
            for b in group:
                if a != b:
                    adjacency.setdefault(a, set()).add(b)

    lines_of: dict[str, set[str]] = {}
    for segment in network["segments"]:
        lines_of.setdefault(segment["from"], set()).add(segment["line"])
        lines_of.setdefault(segment["to"], set()).add(segment["line"])

    seen: set[str] = set()
    found: list[tuple[set[str], list[str]]] = []
    for start in adjacency:
        if start in seen:
            continue
        stack, group = [start], {start}
        seen.add(start)
        while stack:
            node = stack.pop()
            for neighbour in adjacency[node]:
                if neighbour not in seen:
                    seen.add(neighbour)
                    group.add(neighbour)
                    stack.append(neighbour)
        found.append((group, sorted({l for s in group for l in lines_of[s]})))

    found.sort(key=lambda pair: len(pair[0]), reverse=True)
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", nargs="?", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="parse and report, write nothing")
    args = parser.parse_args()

    if not args.source.exists():
        print(f"error: {args.source} not found", file=sys.stderr)
        return 1

    try:
        network, warnings, fractional, unresolved, complexes = build(
            *parse(args.source.read_text(encoding="utf-8"))
        )
    except SourceError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    names = {s["id"]: s["name"] for s in network["stations"]}

    print(f"{len(network['lines'])} lines, {len(network['stations'])} stations, "
          f"{len(network['segments'])} segments")

    print(f"\n=== VERIFIED SAME-COMPLEX MAPPINGS ({len(complexes)}) ===")
    print("    (stations keep their own ids and official names; they are linked "
          "by transfer edges)")
    for cid, members in sorted(complexes.items()):
        joined = "  +  ".join(f"'{names[m]}' ({m})" for m in members)
        print(f"  {cid}\n      {joined}")

    print(f"\n=== VERIFIED DISTINCT OVERRIDES ({len(VERIFIED_DISTINCT)}) ===")
    print("    (similar names that must NEVER be merged)")
    for a, b in VERIFIED_DISTINCT:
        print(f"  '{a}'  !=  '{b}'")

    found = interchanges(network)
    print(f"\n=== TRANSFER POINTS ({len(found)}) ===")
    for name, lines in found:
        print(f"  {name}: {', '.join(lines)}")

    groups = components(network)
    if len(groups) > 1:
        print(f"\n!! NETWORK IS SPLIT INTO {len(groups)} DISCONNECTED PARTS — "
              f"no route exists between them:")
        for index, (group, group_lines) in enumerate(groups, start=1):
            print(f"   part {index}: {len(group)} stations · {', '.join(group_lines)}")

    if fractional:
        print(f"\n{len(fractional)} fractional travel time(s), stored exactly as Double:")
        shown = sorted({note.split(':')[0].split()[0] for note in fractional})
        print(f"  on lines: {', '.join(shown)}  ({len(fractional)} segments)")

    print(f"\n=== UNRESOLVED SIMILAR-NAME CANDIDATES ({len(unresolved)}) ===")
    if unresolved:
        for note in unresolved:
            print(f"  ? {note}")
    else:
        print("  none — every similar-name pair is explicitly classified.")

    if warnings:
        print(f"\n{len(warnings)} warning(s):")
        for note in dict.fromkeys(warnings):
            print(f"  ! {note}")

    if args.check:
        print("\n--check: nothing written")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(network, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    try:
        shown = args.output.resolve().relative_to(ROOT)
    except ValueError:
        shown = args.output
    print(f"\nwrote {shown}")
    print("next: Tools/verify.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
