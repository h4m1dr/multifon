# Multifon — Multi-instance Psiphon Manager (v2)

> 🔐 Run multiple isolated Psiphon tunnels in parallel with Firejail sandboxing, smart port allocation, and region selection — now modular, with more cores and a real cleanup/doctor flow.

---

## 🧩 About

**Multifon** is a Bash-based manager for [Psiphon](https://github.com/SpherionOS/PsiphonLinux).
It installs Psiphon, manages multiple isolated instances, and runs them simultaneously in different regions.
Each instance is sandboxed with **Firejail**, preventing conflicts and ensuring separation of configs and ports.

v2 keeps the v1 behaviour (same folders, same port registry, same INFO.txt) and adds:
- a modular layout (`multifon.sh` + `lib/*.sh`)
- a `doctor` command that repairs registry/INFO/pidfile drift
- IP rotation and health checks (exit IP, latency, blacklist)
- iptables port open/block in the menu
- a cores system (Psiphon, WARP, Tor, Geph, Arman — see `cores.yaml`)
- Force DNS: DNS leaves through the same SOCKS as the traffic

v2.1 (on `codr1`, on top of v2) fixes the v2.0 server-wide port-53 block
(replaced by a scoped owner-match block on a dedicated `multifon` uid,
so Xray keeps working), adds a scoped STUN block, updaters for the
Psiphon core and Firejail, per-egress sandbox timezones, per-service
egress recommendations (`services.yaml`, `docs/SERVICES.md`) and
`multifon fix` — one command that runs the whole checklist.

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
                       updaters (Psiphon core + Firejail), sandbox timezone
  firewall.sh          iptables open/block ports, scoped port-53 + STUN block
  doctor.sh            doctor/sync, live-process reconcile, health check
  cores.sh             core loader (Psiphon / WARP / Tor / Geph / Arman)
  dns.sh               Force DNS: DoH through SOCKS, leak check
  fixer.sh             `multifon fix` — the SERVICES.md checklist, automated
  menu.sh              main menu + submenus + PATH install
cores.yaml             cores manifest (versions, ports, status)
services.yaml          per-service egress recommendations (Gemini, Qwen, Muse, …)
docs/PHASES.md          phase list for the work ahead (incl. Phase 6 bot design)
docs/SERVICES.md        the IPFighter checklist: what is fixed and what is not
```

Each configured instance lives under:

```text
~/psiphon/psiphon-<cc>/
 ├─ config.json
 ├─ psiphon-tunnel-core-x86_64
 ├─ start.sh
 └─ log.txt
```

---

## ✨ Features

- 📦 **Install & update Psiphon** (automatic, manual, or latest binary — pinned to library release v2.0.43, SHA-256 recorded locally)
- 🛡 **Firejail integration** for sandboxed execution
- 🌍 **Multi-region support** with per-country folders (`psiphon-us`, `psiphon-de`, etc.)
- 🔀 **Smart port management** (avoids collisions across runs)
- ⚡ **Bulk operations**: start, stop, restart all tunnels
- 🩺 **Doctor**: repairs orphan registry/INFO entries and stale pidfiles
- 🔁 **Rotate IP** per location, **health check** (exit IP, latency, blacklist)
- 🧱 **Firewall menu**: open/block ports with iptables (nft fallback)
- 🔒 **Force DNS**: DoH through the same SOCKS, leak check, **scoped** port-53 + STUN block (sandbox user only — Xray keeps working)
- 🩹 **`multifon fix`**: runs the whole checklist — doctor sync, health check, rotate dirty IPs, DNS leak check, scoped blocks — then prints the client-side remainder
- 🔄 **Updaters**: Psiphon core (pinned v2.0.43, per-instance copies refreshed) and Firejail (menu 10)
- 🕐 **Sandbox timezone per egress** (firejail `--env=TZ` + zoneinfo bind) — honest limit: this does not change the browser timezone IPFighter reads
- 🗺 **Per-service recommendations**: which egress for Gemini / Qwen / Muse / Flow / ChatGPT / Claude (`services.yaml`, `docs/SERVICES.md`)
- 🔁 **Systemd autostart service** (`multifon-psiphon.service`)
- 🧹 **Cleanup tools** for removing Psiphon instances or Firejail

---

## 🧭 Cores

| Core | Status | SOCKS | Notes |
| --- | --- | --- | --- |
| Psiphon | ready | 1081–1091 | pinned v2.0.43 |
| WARP (wireproxy) | experimental | 1091–1095 | no SOCKS5 UDP yet; needs `wgcf` setup |
| Tor | experimental | 9050 | exits heavily blocked by Google/AI |
| Geph | stub | 1096–1099 | upstream binary location not confirmed yet |
| Arman VPN | stub | 1110–1119 | Firefox Account, 50 GB/month; headless use unverified |

Full details in `cores.yaml`.

---

## 📋 Phases

What is done and what comes next lives in [docs/PHASES.md](docs/PHASES.md).

---

## 🛠 Requirements

Linux (Debian/Ubuntu recommended)

bash, wget, git, curl

firejail (auto-installable from menu)

systemd (for autostart service)

---

## 📜 License

This project is open-source under the MIT License.
Uses Psiphon binaries from SpherionOS/PsiphonLinux and Psiphon-Labs.
