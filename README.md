# openwrt-unregdb

A small, self-contained **unrestricted `regulatory.db`** for OpenWrt and any
cfg80211-based Linux device, shipped as:

- a plain file installer (`install.sh`),
- an **opkg feed** for OpenWrt ≤ 24.10,
- an **apk feed** for OpenWrt 25.x / snapshots.

One prebuilt database serves any number of devices.

The database maps **every country code** (plus the `00` world domain) to one
permissive rule set:

| Band | Range | Max bandwidth | Max EIRP |
|---|---|---|---|
| 2.4 GHz | 2400–2484 MHz | 40 MHz | 30 dBm |
| 5 GHz | 5150–5925 MHz | 160 MHz | 30 dBm |
| 6 GHz | 5925–7125 MHz | 320 MHz | 30 dBm |
| 60 GHz | 57000–71000 MHz | 2160 MHz | 40 dBm |

No DFS, passive-scan, indoor-only or outdoor-only flags. The driver may still
cap power or channels from its own EEPROM/board data.

## Why it works

`cfg80211` reads the regulatory database from `/lib/firmware/regulatory.db`
at boot. OpenWrt builds cfg80211 **without**
`CONFIG_CFG80211_REQUIRE_SIGNED_REGDB`, so an unsigned database is loaded.
Replacing the file is enough; **reboot** to reload it.

## Package feeds

Both feeds replace the distribution `wireless-regdb` package with version
`9999.0001-r1`, so a normal upgrade picks it up. The database is the same
in both.

### opkg (OpenWrt 24.10 and earlier)

The feed index is signed with usign; the public key is
`dist/keys/unregdb.pub`.

```sh
wget -O /tmp/unregdb.pub \
  https://raw.githubusercontent.com/devliq/openwrt-unregdb/main/dist/keys/unregdb.pub
opkg-key add /tmp/unregdb.pub
echo "src/gz unregdb https://raw.githubusercontent.com/devliq/openwrt-unregdb/main/dist/opkg" \
  >> /etc/opkg/customfeeds.conf
opkg update
opkg install wireless-regdb
reboot
```

To drop the feed again: remove the `src/gz unregdb` line, `opkg update`, then
`opkg install --force-reinstall wireless-regdb` from the official feed.

### apk (OpenWrt 25.x / snapshots)

apk trusts unsigned indexes over HTTPS (that is how the official feeds are
published) and verifies each **package** signature with the key in
`/etc/apk/keys`. Install the EC public key once:

```sh
wget -O /etc/apk/keys/unregdb.pem \
  https://raw.githubusercontent.com/devliq/openwrt-unregdb/main/dist/keys/unregdb-apk.pem
mkdir -p /etc/apk/repositories.d
echo "https://raw.githubusercontent.com/devliq/openwrt-unregdb/main/dist/apk/packages.adb" \
  > /etc/apk/repositories.d/unregdb.list
apk update
apk add --upgrade wireless-regdb
reboot
```

A `file://` or plain-HTTP repo is treated as untrusted by apk (even for the
official index); use the HTTPS URL above.

### Single package (no feed)

```sh
# opkg
wget -O /tmp/wr.ipk https://raw.githubusercontent.com/devliq/openwrt-unregdb/main/dist/opkg/wireless-regdb_9999.0001-r1_all.ipk
opkg install /tmp/wr.ipk

# apk (key from above installed)
wget -O /tmp/wr.apk https://raw.githubusercontent.com/devliq/openwrt-unregdb/main/dist/apk/wireless-regdb-9999.0001-r1.apk
apk add /tmp/wr.apk
```

## Install (script, any device)

```sh
curl -fsSL https://raw.githubusercontent.com/devliq/openwrt-unregdb/main/install.sh | sh
reboot
```

The installer downloads `dist/regulatory.db`, verifies its SHA256, backs up
the current file to `/lib/firmware/regulatory.db.orig`, and installs it.
`./install.sh status` shows the current domain and hashes; `./install.sh
revert` restores the backup. A reboot is required.

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

Check that channels the driver previously marked passive are now usable:

```sh
iw phy phy0 info | grep -A6 'Frequencies:'
iw list | grep -E '^\s+\* [0-9]+ MHz \[[0-9]+ dBm\]' | head
```

If the file is invalid the kernel logs `Failed to load regulatory.db` in
`dmesg` and falls back to the built-in world domain.

## Persistence

The file installer writes through overlayfs, so it survives normal reboots
but **not** `sysupgrade`. The packages are normal packages: they also do not
survive `sysupgrade` unless included in the image. Re-install after a
firmware upgrade, or bake it into a custom image.

## Automation

`make feed` rebuilds the database, both packages, both indexes, the usign
signature and `dist/SHA256SUMS`. Signing keys live in `keys/private/`
(gitignored) and are restored from repository secrets in CI:

| Secret | Contents |
|---|---|
| `USIGN_SECRET_B64` | base64 of `keys/private/unregdb.sec` |
| `APK_SIGN_KEY_B64` | base64 of `keys/private/unregdb-apk.key` |

- `.github/workflows/ci.yml` rebuilds weekly and on `workflow_dispatch`, then
  commits `dist/` (the HTTPS raw URLs update immediately).
- `make publish` does the same from any machine that has the keys, e.g. from
  a systemd timer:

```ini
# /etc/systemd/system/unregdb-feed.service
[Service]
Type=oneshot
WorkingDirectory=/opt/openwrt-unregdb
ExecStart=/usr/bin/make publish
```

Enable with `systemctl enable --now unregdb-feed.timer` (a matching
`[Timer] OnCalendar=weekly` unit).

- `make keys` generates a fresh usign + EC keypair. Back up
  `keys/private/` outside the repository (this project stores them in
  OpenBao `kv/network/unregdb`) and set the CI secrets.

## Build

No runtime dependencies beyond Python 3; the host `apk` and `usign` tools are
built automatically into `.cache/`:

```sh
make feed      # dist/regulatory.db + dist/opkg + dist/apk
make check     # rebuild the db and verify the opkg index signature
```

Edit the `RULES` table in `build.py` to change the bands, bandwidth or EIRP.

## Repository layout

```
build.py                  generator (RGDB v20)
install.sh                file installer / revert / status
scripts/build-packages.sh builds the .ipk and .apk
scripts/build-feed.sh     builds the opkg/apk indexes + signatures
scripts/build-apk-tool.sh builds host apk-tools (mkpkg/mkndx)
scripts/build-usign.sh    builds host usign
scripts/gen-keys.sh       generates the signing keypairs
scripts/publish.sh        rebuild + commit dist/
keys/unregdb.pub          usign public key (opkg index)
keys/unregdb-apk.pem      EC public key (apk packages)
dist/                     published feed (committed)
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
