# multifon v2 — Phases

Work ahead, in order. Phase 1–2 ship in this PR (the v2 refactor).
Phases 3–5 are the plan, not promises — each one lands as its own
reviewed change on `codr1`.

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
- [ ] Auto-rotate on dirty IP: when the health check finds a listed IP,
  offer (or, if enabled, run) a rotation automatically.
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
- [ ] Force DNS, full version: per-egress DoH forwarder (one local DNS
  listener per SOCKS port, e.g. via `socat` or a small DoH client) so DNS
  for each core leaves through that core. The foundation is already here:
  `dns_doh_query`, `dns_leak_check`, and the port-53 OUTPUT block
  (menu 8). `lib/dns.sh`.
- [ ] Per-core health checks (latency + DNSBL) for WARP/Tor/Geph, same
  format as the Psiphon one.

## Phase 5 — Multi-country Psiphon + Xray (separate reviewed step)
- [ ] Psiphon instances for DE / NL / SE / US (menu 3 → 1 already supports
  any allowed code; this phase is about choosing and verifying them).
- [ ] Xray outbounds patch: add `Psiphon-DE` / `Psiphon-NL` / `Psiphon-SE` /
  `Psiphon-US` outbounds + routing rules, blackhole UDP/STUN on proxy
  inbounds, route DNS through the proxy outbound. This touches the server
  config — it lands as its own reviewed step, NOT inside this PR.
- [ ] A/B test the countries against IPFighter and keep the best two
  (one European, one Asian) as the defaults.
