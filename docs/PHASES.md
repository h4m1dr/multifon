# multifon v2 — Phases

Work ahead, in order. Phase 1–2 ship in this PR (the v2 refactor).
Phases 3–5 are the plan, not promises — each one lands as its own
reviewed change on `codr1`.

## v2.1 — shipped on `codr1` (on top of the v2 PR)
- [x] Scoped port-53 + STUN block: the v2.0 server-wide OUTPUT block is
  replaced by iptables owner-match rules on a dedicated `multifon` uid
  (bootstrap DNS to 1.1.1.1/8.8.8.8/9.9.9.9 still allowed, everything
  else on 53 + STUN 3478/5349/19302 REJECTed). Xray, apt and dig keep
  working. Legacy server-wide rules are removed on enable.
  `lib/firewall.sh`, `lib/dns.sh`.
- [x] Updaters: `update_psiphon_core` (pinned binary + per-instance
  copies + restart) and `update_firejail` (apt upgrade), menu 10.
  `lib/psiphon.sh`.
- [x] Sandbox timezone per egress (firejail `--env=TZ` + bind of the
  zoneinfo file). Honest limit in the code: this does NOT fix the
  browser timezone IPFighter reads. `lib/psiphon.sh`.
- [x] Per-service locations + checklist + fixer: `services.yaml`,
  `docs/SERVICES.md`, `lib/fixer.sh` (`multifon fix`, menu 11).
- [x] Arman VPN core added to `cores.yaml` as a stub (Firefox Account,
  50 GB/month). Headless/server use unverified — see the stub note.
- [x] Phase 6 designed below (design only — no bot code, no token).

## Phase 1 — Bug fixes (this PR)
- [x] YES prompt: accept `y` / `yes` / `YES` (lowercase + trim, default no).
  `lib/common.sh` → `confirm_yes`; delete now uses it.
- [x] Doctor/sync command: prune registry + INFO orphans whose folder is
  gone, re-register folders that lost their entry, verify ports.
  `lib/doctor.sh` → `doctor_sync` (menu 5).
- [x] Pidfile reconciliation: state is read from the LIVE process
  (`pgrep` + `/proc/<pid>/cwd`, firejail `--private=` fallback), not only
  from `psiphon.firejail.pid`. Stale pidfiles are removed; missing ones are
  re-written. Root cause fixed too: v1 never wrote the pidfile anywhere —
  the generated launchers now record `$!` after launching firejail.
  `lib/doctor.sh` → `psiphon_live_pid`; `lib/psiphon.sh` → `stop_psiphon_in_dir`.
- [x] One canonical cleanup path: every delete (menu + doctor) goes through
  `delete_one_instance` — stop, registry removal, INFO block removal,
  firewall rule removal, folder wipe. `lib/psiphon.sh`.
- [x] Core download pins Psiphon library release v2.0.43 (2026-11-17,
  commit `66e249d`) and verifies the binary (ELF magic, non-empty,
  SHA-256 recorded locally in `~/psiphon/.core-sha256`). Upstream publishes
  no checksum file for the console binary — see `cores.yaml`.

## Phase 2 — Menu / PATH / firewall (this PR)
- [x] Modular layout: thin `multifon.sh` entrypoint + `lib/*.sh`
  (`common`, `ports`, `info`, `psiphon`, `firewall`, `doctor`, `cores`,
  `dns`, `menu`). Same folders, same `.allocated_ports` and INFO.txt
  formats — the existing CZ instance keeps working.
- [x] `multifon` command on PATH: menu 9 symlinks the entrypoint into
  `/usr/local/bin/multifon`, so the menu opens from anywhere.
- [x] iptables port open/block in the menu (menu 6): rules are tagged
  `multifon:<name>`, listed and removed again; nft is a best-effort
  fallback. `lib/firewall.sh`.

## Phase 3 — IP rotation + health check
- [x] Rotate IP (menu 3 → 7): restart one instance for a fresh exit IP,
  show old vs new IP. Change region (menu 3 → 8): delete + recreate.
  `lib/psiphon.sh` → `rotate_ip`, `change_region`.
- [x] Health check (menu 3 → 9, menu 5 → 2): exit IP + latency through the
  instance's SOCKS port + DNSBL status (zen.spamhaus.org,
  cb1.abuseat.org — the two lists IPFighter deducts for).
  `lib/doctor.sh` → `health_check_all`.
- [~] Auto-rotate on dirty IP: `multifon fix` (menu 11) offers a
  rotation on a listed IP, with confirmation. Fully automatic rotation
  (no prompt) is still pending.
- [ ] Rank countries by measured latency + blacklist + score instead of
  guessing: log health-check results per country and sort by them.

## Phase 4 — New cores + Force DNS
- [ ] WARP core: finish `core_install_warp` — register WARP with `wgcf`,
  generate `wireproxy.conf`, start/stop via the cores loader. Remember
  wireproxy has no SOCKS5 UDP yet: TCP + DoH only.
- [ ] Tor core: wire start/stop (tor on 9050) into the cores loader.
  Document clearly that Tor exits are bad for Google/AI scores.
- [ ] Geph core: confirm the upstream repo/binary, then wire it in.
  Do not download from a guessed URL.
- [ ] Arman VPN core: verify headless/server use from the upstream
  project first (its docs read did not pass a safety check, so nothing
  about its server install, proxy port or CLI is claimed here), then
  wire the SOCKS endpoint into the cores loader. Needs a Firefox
  Account (50 GB/month per account — no token in this repo).
- [ ] Force DNS, full version: per-egress DoH forwarder (one local DNS
  listener per SOCKS port, e.g. via `socat` or a small DoH client) so DNS
  for each core leaves through that core — this is also what finally
  removes the bootstrap allow-list from the scoped port-53 block
  (the local forwarder answers the core's DNS via DoH instead).
  The foundation is already here: `dns_doh_query`, `dns_leak_check`,
  and the scoped port-53 + STUN block (menu 8, v2.1). `lib/dns.sh`.
- [ ] Per-core health checks (latency + DNSBL) for WARP/Tor/Geph/Arman,
  same format as the Psiphon one.

## Phase 5 — Multi-country Psiphon + Xray (separate reviewed step)
- [ ] Psiphon instances for DE / NL / SE / US (menu 3 → 1 already supports
  any allowed code; this phase is about choosing and verifying them).
- [ ] Xray outbounds patch: add `Psiphon-DE` / `Psiphon-NL` / `Psiphon-SE` /
  `Psiphon-US` outbounds + routing rules, blackhole UDP/STUN on proxy
  inbounds, route DNS through the proxy outbound. This touches the server
  config — it lands as its own reviewed step, NOT inside this PR.
- [ ] A/B test the countries against IPFighter and keep the best two
  (one European, one Asian) as the defaults.

## Phase 6 — Telegram bot + Mini App control plane (DESIGN ONLY — not built)
Hamidr's request, designed here so the build has a fixed target. No bot
code, no token, no webhook is set up in this patch.

### The control file: `control.yaml` (source of truth, on the server)
One file the bot and the server both read/write. `multifon` never takes
orders from anywhere else.

```yaml
version: 1
updated_at: "2026-11-24T00:00:00Z"   # last writer + time
instances:
  - name: psiphon-cz
    core: psiphon
    country: CZ
    http_port: 8081
    socks_port: 1081
    desired_state: running            # running | stopped
    last_health:
      checked_at: "2026-11-24T00:00:00Z"
      exit_ip: 5.254.60.106
      exit_country: CZ
      latency_ms: 142
      blacklist: clean                # clean | listed:<list>
    last_score:
      checked_at: "2026-11-24T00:00:00Z"
      source: ipfighter               # measured in the browser, typed in or pasted
      score: 60
```

### The applier: `multifon apply` (to be built)
- Reads `control.yaml`, compares `desired_state` with reality
  (live process per folder, same reconcile logic as `doctor_sync`),
  and converges: create/delete instance, start/stop/restart, switch
  core, change region.
- Flags: `multifon apply --dry-run` (print the plan, change nothing),
  `multifon apply` (apply it). Every run writes back `last_health`
  and the real state into `control.yaml`.
- Only `multifon` itself writes `control.yaml` on the server side; the
  bot writes it through the same file, never by running shell commands.

### The Telegram bot + Mini App (to be built)
- **Bot (polling first):** long-polling against Telegram — no public
  URL needed. Webhook later, only if he wants it (needs public HTTPS;
  he has Nginx + ykno.ir domains, so it is possible, not required).
- **Mini App:** a small web page served from the server (or a static
  page) that calls the bot backend; it reads `control.yaml` and shows
  one card per instance (core, country, exit IP, ports, state,
  last health + score).
- **Actions (each maps to one `control.yaml` edit + one `multifon apply`):**
  - Test IP — health check for one/all instances, writes `last_health`.
  - Change/rotate IP — restart for a fresh exit IP (or change region).
  - Manage ports — show the allocated ports; change = delete + recreate
    (ports are bound to the instance folder, they are not edited live).
  - Manage cores — install a core, delete an instance, switch an
    instance's core (delete + recreate with the new core), stop / start /
    restart, read status.
- **Safety:** the bot only ever edits `control.yaml` and triggers
  `multifon apply`. It never runs arbitrary shell, never touches Xray,
  never sees tokens. The applier refuses a `control.yaml` that fails
  validation (bad country code, port collision, unknown core).

### What hamidr must supply later (nothing to do now)
- A bot token from [@BotFather](https://t.me/BotFather) (`/newbot`).
- Polling vs webhook choice (polling = simplest, recommended first).
- Where the bot runs: on mere-cat alongside multifon (recommended —
  it needs local access to `control.yaml`), or elsewhere with a sync.
- The Mini App URL/hosting choice (served from mere-cat's Nginx, or
  a static host).
