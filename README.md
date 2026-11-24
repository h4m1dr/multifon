# Multifon — Multi-instance Psiphon Manager (v2.3)

> 🔐 Run multiple isolated Psiphon tunnels in parallel with systemd-unit sandboxing, smart port allocation, and region selection — now modular, with more cores and a real cleanup/doctor flow.

---

## 🧩 About

**Multifon** is a Bash-based manager for [Psiphon](https://github.com/SpherionOS/PsiphonLinux).
It installs Psiphon, manages multiple isolated instances, and runs them simultaneously in different regions.
Each instance runs as its own systemd unit (`multifon-<cc>.service`) under its own system user (`multifon-<cc>`, home = the instance folder, mode 700) in the shared group `multifon` — Unix permissions replace the old Firejail mount namespace, so instances cannot see each other's folders, and one client still gets one exit IP.

v2 keeps the v1 behaviour (same folders, same port registry, same INFO.txt) and adds:
- a modular layout (`multifon.sh` + `lib/*.sh`)
- a `doctor` command that repairs registry/INFO/unit drift
- IP rotation and health checks (exit IP, latency, blacklist)
- iptables port open/block in the menu
- a cores system (Psiphon, WARP, Tor, Geph, Arman — see `cores.yaml`)
- Force DNS: DNS leaves through the same SOCKS as the traffic

v2.1 (on `codr1`, on top of v2) fixes the v2.0 server-wide port-53 block
(replaced by a scoped owner-match block on a dedicated `multifon` uid,
so Xray keeps working), adds a scoped STUN block, updaters for the
Psiphon core and Firejail (the Firejail updater is gone again in v2.3 —
Firejail itself is), per-egress sandbox timezones, per-service
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

v2.3 (on `codr1`, on top of v2.2) removes Firejail entirely and replaces
it with systemd units: one user + one unit per instance
(`multifon-<cc>`, `multifon-<cc>.service`, `Environment=TZ` per egress),
lifecycle via `systemctl` (this also kills the pidfile-desync bug class —
there is no pidfile any more), the scoped port-53 + STUN block switches
from `--uid-owner multifon` to `--gid-owner multifon` (one rule set for
all instances), and menu 2 becomes the systemd-units entry with a
one-time Firejail removal that also offers `apt autoremove --purge` for
the ~1 GB of Recommends junk Firejail dragged in (xpra + GTK/GL dev
stack). The folder submenu renumbered (old item 2, "no Firejail", is
gone); `multifon start-all` / `stop-all` / `status` work from the CLI.

---

## 🚀 Installation

```bash
git clone https://github.com/h4m1dr/multifon.git
cd multifon
bash multifon.sh
```

Or install the `multifon` command on PATH (menu 9), then run it from anywhere:

```bash
multifon
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
  systemd.sh           per-instance users + units, lifecycle (systemctl),
                       Firejail removal (one-time, with autoremove dry-run)
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
- 🧹 **Cleanup tools** for removing Psiphon instances or Firejail leftovers (menu 2 / menu 4 → 2, one-time)

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
Uses Psiphon binaries from SpherionOS/PsiphonLinux and Psiphon-Labs.
