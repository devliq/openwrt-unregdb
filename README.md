# openwrt-unregdb

A small, self-contained **unrestricted `regulatory.db`** for OpenWrt and any
cfg80211-based Linux device, plus an installer. One prebuilt database serves
any number of devices; there is no per-device build step.

The database maps **every country code** (plus the `00` world domain) to one
permissive rule set:

| Band | Range | Max bandwidth | Max EIRP |
|---|---|---|---|
| 2.4 GHz | 2400–2484 MHz | 40 MHz | 30 dBm |
| 5 GHz | 5150–5925 MHz | 160 MHz | 30 dBm |
| 6 GHz | 5925–7125 MHz | 320 MHz | 30 dBm |
| 60 GHz | 57000–71000 MHz | 2160 MHz | 40 dBm |

No DFS, passive-scan, indoor-only or outdoor-only flags. The driver may still
cap power or channels based on its own EEPROM/board data.

## Why it works

`cfg80211` reads the regulatory database from `/lib/firmware/regulatory.db`
at boot. OpenWrt builds cfg80211 **without**
`CONFIG_CFG80211_REQUIRE_SIGNED_REGDB`, so an unsigned database is loaded.
Replacing the file is enough; **reboot** to reload it.

## Install

On the device (OpenWrt, as root):

```sh
curl -fsSL https://raw.githubusercontent.com/devliq/openwrt-unregdb/main/install.sh | sh
reboot
```

The installer:

1. downloads `dist/regulatory.db` and verifies its SHA256;
2. backs up the current file to `/lib/firmware/regulatory.db.orig`;
3. installs the new database.

From a checkout, run `./install.sh install` (it prefers the local
`dist/regulatory.db`).

## Verify

```sh
iw reg get
```

Every listed band should show only ranges with no `NO-IR`, `DFS`, or
`NO-OUTDOOR` annotation, for example:

```
country CA:
	(2400.0 - 2484.0 @ 40.0), (N/A, 30.0), (N/A)
	(5150.0 - 5925.0 @ 160.0), (N/A, 30.0), (N/A)
	(5925.0 - 7125.0 @ 320.0), (N/A, 30.0), (N/A)
```

Check that the channels a driver previously marked passive are now usable:

```sh
iw phy phy0 info | grep -A6 'Frequencies:'
iw list | grep -E '^\s+\* [0-9]+ MHz \[[0-9]+ dBm\]' | head
```

If the file is invalid the kernel logs `Failed to load regulatory.db` in
`dmesg` and falls back to the built-in world domain.

## Revert

```sh
./install.sh revert
reboot
```

`install.sh status` prints the installed/backup hashes and the current
regulatory domain.

## Persistence

The install writes through the overlayfs, so it survives normal reboots.
It does **not** survive `sysupgrade`: re-run the installer after a firmware
upgrade, or add it to a custom image / uci-defaults script.

## Build

No dependencies beyond Python 3:

```sh
python3 build.py            # writes dist/regulatory.db
sha256sum dist/regulatory.db > dist/SHA256SUMS
```

Edit the `RULES` table in `build.py` to change the bands, bandwidth or EIRP.
`ci.yml` regenerates the database and fails if it differs from the committed
`dist/regulatory.db`.

## Repository layout

```
build.py              generator (RGDB v20)
install.sh            installer / revert / status
dist/regulatory.db    prebuilt database
dist/SHA256SUMS       checksum
```

## Caveats

- This removes the driver's regulatory restrictions. In most jurisdictions
  transmitting outside the locally permitted bands, power, or DFS rules is
  illegal and can interfere with licensed users. Use it only on hardware and
  spectrum you are authorised to operate (private lab, shielded/isolated
  site, licensed spectrum).
- Availability still depends on the driver and hardware: some MediaTek,
  Qualcomm and Broadcom parts enforce their own channel/power limits.
- 6 GHz AP operation may additionally require driver support
  (`ieee80211ax`/`be`, `he_6ghz_reg_power_mode`, AFC in some regions).
