# Multifon — Multi-instance Psiphon Manager (v2.3.3)

> 🔐 Run multiple isolated Psiphon tunnels in parallel with systemd-unit sandboxing, smart port allocation, and region selection — now modular, with more cores and a real cleanup/doctor flow.

---

## 🧩 About

**Multifon** is a Bash-based manager for [Psiphon](https://github.com/Psiphon-Labs/psiphon-tunnel-core-binaries) (the official Psiphon-Labs core — the SpherionOS repack turned out to be a broken 90-byte wrapper, see v2.3.1).
It installs Psiphon, manages multiple isolated instances, and runs them simultaneously in different regions.
Each instance runs as its own systemd unit (`multifon-<cc>.service`) under its own system user (`multifon-<cc>`, home = the instance folder, mode 700) in the shared group `multifon` — Unix permissions keep instances from seeing each other's folders, and one client still gets one exit IP.

v2 keeps the v1 behaviour (same folders, same port registry, same INFO.txt) and adds:
- a modular layout (`multifon.sh` + `lib/*.sh`)
- a `doctor` command that repairs registry/INFO/unit drift
- IP rotation and health checks (exit IP, latency, blacklist)
- iptables port open/block in the menu
- a cores system (Psiphon, WARP, Tor, Geph, Arman — see `cores.yaml`)
- Force DNS: DNS leaves through the same SOCKS as the traffic

v2.1 (on `codr1`, on top of v2) fixes the v2.0 server-wide port-53 block
(replaced by a scoped owner-match block on a dedicated `multifon` uid,
so Xray keeps working), adds a scoped STUN block, an updater for the
Psiphon core, per-egress sandbox timezones, per-service
egress recommendations (`services.yaml`, `docs/SERVICES.md`) and
`multifon fix` — one command that runs the whole checklist.

v2.2 (on `codr1`, on top of v2.1) implements the main parts of Phase 4
and 5: a per-egress DoH forwarder with dnscrypt-proxy (menu 8 → 4/5/6),
per-core health checks for WARP/Tor/Arman (menu 5 → 3), a recommended
country set helper (menu 3 → 9: DE/NL/SE/SG), the exact Xray patch
(`docs/XRAY-PATCH.md`), and a WARP + Tor test procedure
(`docs/TEST-WARP-TOR.md` — both cores are test-only). It also adds the
"Phase before 6" patch + test round to `docs/PHASES.md`, including the
new cores from the serverless research (Cloudflare Workers VLESS as the
next egress core, VLESS+REALITY / AmneziaWG / Hysteria2 as leg-1
inbounds).

v2.3.3 (on `codr1`, on top of v2.3.2) fixes the two live-test failures
that survived v2.3.1, both confirmed with hard evidence on the server:
(1) the scoped port-53 + STUN block was real but dead — the rules were
APPENDED (-A) at the end of OUTPUT, AFTER UFW's jumps, and UFW's
before-output chain ACCEPTs ~everything, so all multifon rules showed
0 packets / 0 bytes and a dig as multifon-nl still answered. The block
is now INSERTED at the very top of OUTPUT (position 1, before the UFW
jumps), bootstrap ACCEPTs first, then the REJECTs; enabling runs a
counter-based self-test (REJECT counters before/after a dig as the
instance user) and says plainly if the block is not catching traffic
instead of printing "block on"; a oneshot unit
(`multifon-firewall.service`, + `multifon reapply-block`) re-applies
the rules at boot, because a reboot or `ufw reload` wipes OUTPUT; and
doctor sync re-applies them when they are gone or sitting below UFW.
The leak probe now runs dig with the unit's gid too (`sudo -u <user>
-g multifon`) and never says "enable the block" when the block is
already on. (2) the DoH forwarder exited instantly because the
generated toml used `bootstrap_resolvers`, which is NOT a valid key in
dnscrypt-proxy 2.0.45 (FATAL) — the correct key is
`fallback_resolvers`, verified against the upstream 2.0.45 example
config and the real binary; the server now comes from a `[static]`
stamp copied verbatim from the upstream public-resolvers list, so no
`[sources]` download is needed at startup (that download goes through
the SOCKS proxy and FATALs when the egress is down). Forwarder start
validates the toml with `dnscrypt-proxy -check` and prints the real
error + last log lines instead of "check the config", and "No running
egresses" is only printed when genuinely nothing is running (running /
started / failed are counted separately). Also: health check measures
each egress with 3 spaced samples (~2s apart, never back-to-back or
parallel) to Google's generate_204 endpoint and reports median latency
+ jitter, ranks egresses by median then jitter, and says which one is
best now; and the menu header now says "Source: Psiphon-Labs".

v2.3.1 (on `codr1`, on top of v2.3) fixes the live-test failures of v2.3:
the SpherionOS install turned out to be a broken 90-byte wrapper, and the
create path copied the first `-x` file it found with no verification, so
every instance got the wrapper (exit 127, restart loop). Now the binary
is verified (ELF + >= 1 MB) at create time, in the updater, and before a
unit is written or started; `repair_instance_binaries` (doctor sync,
`multifon fix`) re-copies the verified official core into broken
instances; units get restart-loop protection (5 failures in 5 min, then
failed); status shows FAILED / RESTART-LOOP instead of STOPPED; the DNS
leak check skips stopped instances and probes as each instance's own
user; the firewall status classifier is fixed (it misread gid-owner
rules as legacy); doctor sync reports stopped units and legacy rules
instead of "everything already in sync". The manual repair is now in
the script: menu 10 → 1 downloads the pinned core, verifies it and
re-copies it into every instance (with a fallback to the
already-installed verified core when the download fails), menu 10 → 3
re-copies the verified core on its own, and `multifon fix` / doctor
sync repair broken instance binaries automatically. The create path
prefers the verified `/usr/bin/psiphon-tunnel-core-x86_64` and never
copies `/usr/bin/psiphon` (the broken wrapper) as a core. `multifon`
now works from any directory (the entrypoint resolves its symlink),
and menu 9 verifies that with `multifon status` from /tmp. Menu 4 → 2
(`multifon nuke`) is the clean slate: printed list + confirmation,
then it deletes instances, units, users, group, firewall rules, DoH
forwarders, the wrapper and the old sandbox package (~1 GB autoremove)
— and keeps the verified core. Egress separation verified live:
nl 172.235.160.143, se 172.232.158.24, sg 139.59.119.126.

v2.3 (on `codr1`, on top of v2.2) replaces the old sandbox with
systemd units (historical note: v2.3 replaced the previous sandbox
with systemd units): one user + one unit per instance
(`multifon-<cc>`, `multifon-<cc>.service`, `Environment=TZ` per egress),
lifecycle via `systemctl` (this also kills the pidfile-desync bug class —
there is no pidfile any more), the scoped port-53 + STUN block switches
from `--uid-owner multifon` to `--gid-owner multifon` (one rule set for
all instances), and menu 2 becomes the systemd-units entry. The old
sandbox package purge moved into the clean-slate function (menu 4 → 2,
`multifon nuke`) in v2.3.1. The folder submenu renumbered (old item 2 is
gone); `multifon start-all` / `stop-all` / `status` work from the CLI.

---

## 🚀 Installation

One-time install — no `cd` at all, `multifon` runs from anywhere afterwards:

```bash
git clone https://github.com/h4m1dr/multifon.git
bash multifon/multifon.sh install
```

Then run it from any directory:

```bash
multifon
```

Or open the menu directly (also without `cd`):

```bash
bash multifon/multifon.sh
```

Or run the fixer directly (no menu):

```bash
multifon fix
```

---

## 📂 Layout

```text
multifon.sh            thin entrypoint — sources lib/*.sh, starts the menu
lib/
  common.sh            colors, logo, pause, status, confirm_yes
  ports.sh             port registry (.allocated_ports) + allocation
  info.sh              INFO.txt read/write/validate
  psiphon.sh           install, folders, start/stop/restart, delete, rotate IP,
                       updater (Psiphon core), sandbox timezone (via the unit),
                       recommended country set (DE/NL/SE/SG)
  systemd.sh           per-instance users + units, lifecycle (systemctl)
  firewall.sh          iptables open/block ports, scoped port-53 + STUN block
                       (--gid-owner multifon, v2.3)
  doctor.sh            doctor/sync, unit reconcile, health check
                       (Psiphon instances + WARP/Tor/Arman cores)
  cores.sh             core loader (Psiphon / WARP / Tor / Geph / Arman)
  dns.sh               Force DNS: DoH through SOCKS, leak check,
                       per-egress dnscrypt-proxy forwarder
  fixer.sh             `multifon fix` — the SERVICES.md checklist, automated
  menu.sh              main menu + submenus + PATH install
cores.yaml             cores manifest (versions, ports, status)
services.yaml          per-service egress recommendations (Gemini, Qwen, Muse, …)
docs/PHASES.md          phase list for the work ahead (incl. Phase before 6 + Phase 6 bot design)
docs/SERVICES.md        the IPFighter checklist: what is fixed and what is not
docs/XRAY-PATCH.md      exact Xray JSON patch + 3x-ui panel steps (Phase 5)
docs/TEST-WARP-TOR.md   WARP + Tor test procedure (test-only cores)
```

Each configured instance lives under:

```text
~/psiphon/psiphon-<cc>/          (home of user multifon-<cc>, mode 700)
 ├─ config.json
 ├─ psiphon-tunnel-core-x86_64
 └─ log.txt
```
plus its unit file `/etc/systemd/system/multifon-<cc>.service`
(enabled — autostarts on boot). There is no `start.sh`, no
`start-psiphons.sh` and no pidfile any more; `multifon start-all` /
`stop-all` are `systemctl` loops.

---

## ✨ Features

- 📦 **Install & update Psiphon** (automatic, manual, or latest binary — pinned to library release v2.0.43, SHA-256 recorded locally)
- 🛡 **Systemd units** for sandboxed execution — one user + unit per instance, 700 dirs, shared `multifon` group
- 🌍 **Multi-region support** with per-country folders (`psiphon-us`, `psiphon-de`, etc.)
- 🔀 **Smart port management** (avoids collisions across runs)
- ⚡ **Bulk operations**: start, stop, restart all tunnels
- 🩺 **Doctor**: repairs orphan registry/INFO entries and stale units
- 🔁 **Rotate IP** per location, **health check** (exit IP, latency, blacklist)
- 🧱 **Firewall menu**: open/block ports with iptables (nft fallback)
- 🔒 **Force DNS**: DoH through the same SOCKS, leak check, **scoped** port-53 + STUN block (`multifon` group only — Xray keeps working)
- 🌐 **Per-egress DoH forwarder**: dnscrypt-proxy, one listener per egress (menu 8 → 4/5/6) — DNS leaves through the same core as the traffic
- 🩺 **Per-core health checks**: WARP / Tor / Arman in the same format as the Psiphon check (menu 5 → 3)
- 🌍 **Recommended country set**: one command creates DE/NL/SE/SG (menu 3 → 9); the exact Xray patch lives in `docs/XRAY-PATCH.md`
- 🧪 **WARP + Tor are test-only**: run `docs/TEST-WARP-TOR.md` first — if either fails it moves to Phase before 6 or is dropped, never into rotation
- 🩹 **`multifon fix`**: runs the whole checklist — doctor sync, health check, rotate dirty IPs, DNS leak check, scoped blocks — then prints the client-side remainder
- 🔄 **Updater**: Psiphon core (pinned v2.0.43, per-instance copies refreshed, menu 10)
- 🕐 **Sandbox timezone per egress** (unit `Environment=TZ` + zoneinfo bind) — honest limit: this does not change the browser timezone IPFighter reads
- 🗺 **Per-service recommendations**: which egress for Gemini / Qwen / Muse / Flow / ChatGPT / Claude (`services.yaml`, `docs/SERVICES.md`)
- 🔁 **Systemd units per instance** (`multifon-<cc>.service`, enabled — autostart on boot)
- 🧹 **Clean slate** (menu 4 → 2, `multifon nuke`): deletes everything multifon owns — instances, units, users, rules, DoH forwarders, wrapper, old sandbox package — and keeps the verified core

---

## 🧭 Cores

| Core | Status | SOCKS | Notes |
| --- | --- | --- | --- |
| Psiphon | ready | 1081–1091 | pinned v2.0.43 |
| WARP (wireproxy) | test-only | 1091–1095 | no SOCKS5 UDP yet; needs `wgcf` setup; usually doesn't respond — see `docs/TEST-WARP-TOR.md` |
| Tor | test-only | 9050 | exits heavily blocked by Google/AI; fallback only |
| Geph | stub | 1096–1099 | upstream binary location not confirmed yet |
| Arman VPN | stub | 1110–1119 | Firefox Account, 50 GB/month; headless use verified feasible, wiring needs your sign-in |
| Workers VLESS | stub (planned) | — (Xray outbound) | Cloudflare Workers egress, free no-card; Phase before 6 |

Full details in `cores.yaml`.

---

## 📋 Phases

What is done and what comes next lives in [docs/PHASES.md](docs/PHASES.md).

---

## 🛠 Requirements

Linux (Debian/Ubuntu recommended)

bash, wget, git, curl

systemd (one unit per instance; units are enabled, so they autostart on boot)

---

## 📜 License

This project is open-source under the MIT License.
Uses the official Psiphon binaries from Psiphon-Labs (psiphon-tunnel-core-binaries, pinned v2.0.43).
