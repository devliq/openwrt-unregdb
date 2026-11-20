#!/usr/bin/env python3
"""Generate an unrestricted cfg80211 regulatory.db (RGDB v20).

The kernel's binary format (net/wireless/reg.c):

  struct fwdb_header   { __be32 magic; __be32 version; struct fwdb_country[]; }
  struct fwdb_country  { u8 alpha2[2]; __be16 coll_ptr; }        // ptr = off >> 2
  struct fwdb_collection { u8 len; u8 n_rules; u8 dfs_region; }  // then u16 rule ptrs
  struct fwdb_rule     { u8 len; u8 flags; __be16 max_eirp;
                         __be32 start, end, max_bw; }

max_eirp is in mBm (100 = 1 dBm). Frequencies and bandwidth are in kHz.
`len` in a collection is the fixed header size (3); the rule-pointer array
starts at ALIGN(len, 2) = 4.

OpenWrt builds cfg80211 without CONFIG_CFG80211_REQUIRE_SIGNED_REGDB, so an
unsigned regulatory.db is loaded. The kernel must be rebooted to reload it.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

MAGIC = 0x52474442
VERSION = 20

# (start MHz, end MHz, max bandwidth MHz, max EIRP dBm, flags)
# flags: 0 = no restrictions (no DFS, no NO-IR, no NO-OUTDOOR).
RULES = [
    (2400, 2484, 40, 30, 0),      # 2.4 GHz
    (5150, 5925, 160, 30, 0),     # 5 GHz, including DFS channels
    (5925, 7125, 320, 30, 0),     # 6 GHz
    (57000, 71000, 2160, 40, 0),  # 60 GHz
]

# ISO 3166-1 alpha-2 codes plus the "00" world domain.
COUNTRIES = """
00 AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ
BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU
CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB
GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL
IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI
LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV
MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN
PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR
SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US
UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW
""".split()


def build() -> bytes:
    countries = sorted(set(COUNTRIES) | {"00"})
    n_countries = len(countries)
    n_rules = len(RULES)

    rules_off = 8 + 4 * n_countries
    collection_off = rules_off + 16 * n_rules
    assert collection_off % 4 == 0

    out = bytearray()
    out += b"RGDB"
    out += struct.pack(">I", VERSION)

    # Country table: every country shares the same permissive collection.
    for cc in countries:
        out += cc.encode("ascii")
        out += struct.pack(">H", collection_off >> 2)

    # Rules.
    for i, (start, end, max_bw, eirp, flags) in enumerate(RULES):
        assert (rules_off + 16 * i) % 4 == 0
        out += struct.pack(
            ">BBHIII",
            16,                      # rule length
            flags,
            int(round(eirp * 100)),  # mBm
            int(round(start * 1000)),  # kHz
            int(round(end * 1000)),
            int(round(max_bw * 1000)),
        )

    # Collection: len=3 fixed header, n_rules, dfs_region=0, pad, pointers.
    coll = bytearray(struct.pack(">BBBB", 3, n_rules, 0, 0))
    for i in range(n_rules):
        coll += struct.pack(">H", (rules_off + 16 * i) >> 2)
    while len(coll) % 4:
        coll += b"\x00"
    out += coll

    assert len(out) == collection_off + len(coll)
    return bytes(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("-o", "--output", type=Path, default=Path("dist/regulatory.db"))
    args = ap.parse_args()
    data = build()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f"wrote {args.output} ({len(data)} bytes, {len(RULES)} rules)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
