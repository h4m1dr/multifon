# multifon v2 — Phases

Work ahead, in order. Phase 1–2 ship in this PR (the v2 refactor).
Phases 3–5 are the plan, not promises — each one lands as its own
reviewed change on `codr1`.

## Where we are now (2026-11-24, from the menu screenshot)
- **Installed on the server: v2.0.0** (PR #1 merged to main, merge
  commit 69a72744). That is the menu in the screenshot: options 1–9.
  Phases 1 + 2 are installed, Phase 3 mostly installed (rotate + health
  check live under menu 3 → 7/8/9 and menu 5 → 2; fully automatic
  rotation and country ranking are still pending).
- **Not installed yet: v2.1** (PR #2 open, commit 1e8a0302 on `codr1`).
  That is where the updaters (menu 10), `multifon fix` (menu 11), the
  scoped port-53 + STUN block, sandbox TZ and the Arman stub live.
  The screenshot menu has no 10/11 because it is v2.0, not v2.1.
- **Research is done** (2026-11-24, `~/workspace/multifon-research/`):
  DoH forwarder, WARP headless, Tor, Geph, Arman headless, Xray patch,
  Telegram control plane, Windows client. Its verdicts are folded into
  Phases 4–5 below.

## v2.2 — Phase 4/5 main parts (on `codr1`, on top of v2.1)
- [x] Per-egress DoH forwarder (dnscrypt-proxy): config generator +
  installer + start/stop/status in `lib/dns.sh`, menu 8 → 4/5/6. One
  toml per egress (listen 5353+, upstream = that egress's SOCKS port,
  `proxy = 'socks5://…'` + `force_tcp = true`), bootstrap resolvers
  1.1.1.1/8.8.8.8 only (matches the v2.1 scoped-block exception).
  OPEN: the bootstrap-lookup path still needs a tcpdump test on the
  server (see the note in `lib/dns.sh`).
- [x] Per-core health checks (WARP/Tor/Arman) in the same format as the
  Psiphon check (exit IP + latency + DNSBL): `health_check_socks` in
  `lib/doctor.sh`, menu 5 → 3. Arman reports port status only — its
  SOCKS credentials are needed for a full check.
- [x] Phase 5: recommended country set helper (`create_recommended_country_set`,
  menu 3 → 10: DE/NL/SE/SG, skips existing, prints real ports) and
  `docs/XRAY-PATCH.md` (exact JSON + 3x-ui panel steps + TO-CONFIRM list).
- [x] WARP + Tor test procedure: `docs/TEST-WARP-TOR.md` (exact server
  steps, checks, expected outcomes, verdict rule). WARP/Tor marked
  `test-only` in `cores.yaml` — if either fails it moves to Phase
  before 6 or is dropped, never into rotation.
- [x] "Phase before 6" section added below (the patch + test round).
- [x] Arman core: headless use VERIFIED feasible by research
  (server variant, SOCKS5 127.0.0.1:10810, panel 10820) — the v2.1 stub
  text updated; wiring still needs hamidr's one-time sign-in + backup
  move and the unverified config.json credential key.
- [x] Cloudflare Workers VLESS core added to `cores.yaml` as a planned
  stub (from the serverless research 2026-11-24) — implementation is
  Phase before 6, not here.

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
  50 GB/month). Headless/server use has since been VERIFIED by research
  (2026-11-24, `~/workspace/multifon-research/05-arman-vpn-headless.md`):
  server variant, SOCKS5 127.0.0.1:10810 — see Phase 4.
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
- [ ] Rank countries by measured results: moved to Phase 5 — it needs
  the multi-country instances first.

## Phase 4 — New cores + Force DNS

### Suggested cores (researched 2026-11-24 — see `~/workspace/multifon-research/`)
| Core | What it is | Status | SOCKS port | Notes |
|---|---|---|---|---|
| Psiphon (official v2.0.43) | psiphon-tunnel-core, Psiphon-Labs | Ready — default core | per instance (1081+) | Pinned in `cores.yaml`. His current /usr/bin/psiphon is from SpherionOS/PsiphonLinux, not the official release — the updater replaces it with the official binary. |
| WARP (Cloudflare) | wgcf + wireproxy (windtf/wireproxy) | Ready to implement | per core (1091+) | `wgcf register --accept-tos` (no account/browser) → `wgcf generate` → `[Socks5]` in wgcf-profile.conf → `wireproxy -c`. TCP-only SOCKS5 (no UDP yet). Best core for muse.ai (Cloudflare IPs least flagged). |
| Arman VPN (Firefox VPN) | armanlife/arman-vpn-client, server variant | Ready to implement (verified 2026-11-24) | 127.0.0.1:10810 | SOCKS5 + CLI + web panel (10820), multi-account rotation at 95%. Needs his one-time browser sign-in (Windows/Android app) + backup zip moved to the server via scp. 50 GB/month per Firefox Account. One instance = one active country. |
| Tor | tor, SocksPort 9050 | Fallback only | 9050 | Exits heavily blocked by Google/AI — scores worse, not better. Only as a last-resort core. |
| Geph | geph4-client | BLOCKED | — | No verified prebuilt linux-amd64 binary (no GitHub Release; install is `cargo install`, last crate Feb 2025). Check geph4 releases, then geph5, before writing any installer. Do NOT download from a guessed URL. |

### Remaining problems in Phase 4
- [x] Per-egress DoH forwarder: **wired in v2.2** (dnscrypt-proxy,
  `lib/dns.sh`, menu 8 → 4/5/6). OPEN: bootstrap-lookup path needs a
  tcpdump test on the server — if it leaks, it moves to Phase before 6.
- [~] WARP core: wireproxy installer fixed (canonical repo windtf/wireproxy).
  Full wiring (wgcf register + wireproxy.conf + start/stop) is **test-only**:
  run `docs/TEST-WARP-TOR.md` first. If it fails, WARP moves to Phase
  before 6. Fix to try first: WARP-over-MASQUE over HTTP/2 (TCP:443).
- [~] Tor core: installer notes the deb.torproject.org question (needs
  his review); start/stop is `systemctl start/stop tor@default`.
  **Test-only**: run `docs/TEST-WARP-TOR.md` — the expected outcome is
  that Gemini refuses it; Tor stays a fallback core only.
- [ ] Geph core: BLOCKED (see table). No installer until a prebuilt binary is verified.
- [~] Arman VPN core: headless use VERIFIED feasible (research 2026-11-24:
  server variant, SOCKS5 127.0.0.1:10810, panel 10820, multi-account
  rotation at 95%). Still to wire: the config.json key for the SOCKS
  credentials, whether the proxy/panel ports are configurable (two
  instances side by side), and hamidr's one-time sign-in + backup move
  (panel first; fallback: browser sign-in on Windows/Android + backup
  zip via scp). No token/credential in this repo.
- [x] Per-core health checks (latency + DNSBL) for WARP/Tor/Arman, same
  format as the Psiphon one: **wired in v2.2** (`lib/doctor.sh`, menu 5 → 3).

## Phase 5 — Multi-country Psiphon + Xray (separate reviewed step)

### Suggested cores per service (from `services.yaml` + research)
| Service | First choice | Second choice | Why |
|---|---|---|---|
| Gemini | Psiphon DE / NL / SE | Psiphon SG | EU exits are in Gemini's 150+ supported countries, lowest ping from the server. |
| Qwen | Any clean core | Psiphon SG / JP / DE | Least picky; international API works from US/EU IPs without a proxy. |
| Muse (muse.ai) | WARP core | Clean Psiphon DE / NL | Cloudflare-fronted: WARP (Cloudflare IPs) least flagged. Note: his muse.ai failure was a local Chrome extension block, not the IP. |
| Google Flow | Psiphon DE / NL / SE + AI Flow Bypasser extension in the browser | — | The extension flips Flow's country boolean client-side; the IP only needs to be a supported country. |
| ChatGPT / Claude | Psiphon US, then DE / NL | WARP | US first for feature availability, but more CAPTCHAs. |

### Remaining problems in Phase 5
- [x] Psiphon instances for DE / NL / SE / US: the **recommended set
  helper is wired in v2.2** (menu 3 → 10: DE/NL/SE/SG, skips existing).
  US is not in the set — add it with menu 3 → 1 when a US egress is
  needed (ChatGPT/Claude). Asian backup: SG.
- [x] Xray outbounds patch: **documented in v2.2** (`docs/XRAY-PATCH.md`:
  exact JSON + 3x-ui panel steps + TO-CONFIRM list). The patch itself
  is still to be APPLIED by hamidr in the panel (it touches the server
  config — it lands as its own reviewed step, NOT inside this PR).
  TO-CONFIRM: real inbound tags, and the `"3478,5349,19302"` port-list
  form (validate with `xray run -test`). Also fix the lying `Psiphon-SE`
  tag: 1081 is really CZ.
- [ ] A/B test the countries against IPFighter and keep the best two (one European, one Asian) as the defaults.
- [ ] Rank countries by measured latency + blacklist + score instead of guessing: log health-check results per country and sort by them. (Moved here from Phase 3 — it needs the multi-country instances first.)

## Phase before 6 — patch + test round (after Phases 4–5, before Phase 6)
Hamidr's idea (2026-11-24): a general patch + test round AFTER Phases
4–5. Anything from 4/5 that failed or is unverified goes here, gets
fixed, and is tested in several places before Phase 6 is built. **Rule:
nothing from Phase 4/5 is silently dropped — it moves here with its
failure reason written down.**

### What goes here
- [ ] WARP verdict after the test (`docs/TEST-WARP-TOR.md`): if it fails,
  first try WARP-over-MASQUE over HTTP/2 (TCP:443); if that fails too,
  WARP is dropped or kept as a documented fallback only.
- [ ] Tor verdict after the test: expected to stay fallback-only (Gemini
  refuses publicly-listed exits by design). Only the "Tor doesn't even
  connect" case needs a fix here.
- [ ] DoH forwarder bootstrap-lookup tcpdump test (open from v2.2): if
  the bootstrap lookup leaks direct UDP/53, fix it here (e.g. pin the
  server stamp that embeds 1.1.1.1, or run the forwarder as the sandbox
  user so the scoped block constrains it).
- [ ] Geph, if a prebuilt linux-amd64 binary appears (check geph4
  releases, then geph5). Until then it stays BLOCKED.
- [ ] Arman wiring leftovers: config.json credential key, whether the
  proxy/panel ports are configurable (two instances side by side).
- [ ] Xray patch application leftovers: anything from the TO-CONFIRM list
  in `docs/XRAY-PATCH.md` that failed validation, and the A/B test
  results (best two countries as defaults).

### New cores — from the serverless research (2026-11-24, `~/workspace/multifon-research/09-serverless-egress.md`)
The research splits the problem into two legs — **leg 1: Iran → server**
(how he reaches mere-cat) vs **leg 2: server → internet** (what IP the
site sees). Most protocols solve only one. "Masket" is MASQUE (a
protocol, not a GitHub project). Deno Deploy is shutting down and Lambda
needs a card — both out. Vercel is backup-only (10 GB cap → HTTP 402).
- [ ] **Cloudflare Workers VLESS egress (edgetunnel, cmliu/edgetunnel)
  — TOP recommendation #1, new leg-2 core.** A Worker fetches as a
  Cloudflare edge IP: free, no card, 100k requests/day, zero server
  load. Deploy one Worker (UUID secret, custom domain on his Cloudflare
  — `*.workers.dev` reachability from Iran is unverified), add an Xray
  VLESS WS+TLS outbound on mere-cat, test Gemini/Qwen/muse.ai/Flow/
  ChatGPT through it + ipfighter. UNVERIFIED whether Gemini opens
  through it (Google mis-geolocates some Cloudflare egress IPs as
  Iran/Russia — BardErrorInfo 1060). If Gemini refuses it, it still
  serves Qwen/muse.ai/general browsing. Listed as a planned stub in
  `cores.yaml` (`workers-vless`). Cloudflare can disable a Worker at
  any time — keep it as one egress among several, never the only one.
- [ ] **VLESS + REALITY inbound on the existing Xray (3x-ui panel) —
  cheapest leg-1 win.** Best DPI resistance; no new software on the
  server. It fixes reaching the server, not the egress IP.
- [ ] **AmneziaWG inbound — second leg-1 option.** Obfuscated WireGuard
  (Jc/Jmin/Jmax, junk packets); PPA or one-command installer; fits the
  2 GB server easily. Also leg 1 only (same exit IP as now).
- [ ] **Hysteria2 inbound test** (single binary, QUIC/UDP 443, Brutal
  congestion control) as the second leg-1 inbound. ShadowTLS v3 +
  SS-2022 as a third option. TUIC last.
- [ ] **WARP-over-MASQUE (h2)** as the WARP fix attempt (see above).
  MASQUE self-hosted (sing-box 1.15 alpha) is a watch item, not a build
  item — a self-hosted MASQUE server egresses with the server's own IP,
  so it gives no new foreign IP by itself.

### Test matrix (before Phase 6)
Every cell is a real test on his Windows client (TUN on, or the
Chromium flag pair — otherwise the WebRTC cell is meaningless):

| Service | DE | NL | SE | SG | US | WARP | Tor | Workers-VLESS |
|---|---|---|---|---|---|---|---|---|
| Gemini | | | | | | | | |
| Qwen | | | | | | | | |
| Muse (muse.ai) | | | | | | | | |
| Google Flow | | | | | | | | |
| ChatGPT / Claude | | | | | | | | |

Each cell: opens? (yes/no/CAPTCHA) + ipfighter score where it applies.
The matrix decides the defaults in `services.yaml` — no guessing.

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
