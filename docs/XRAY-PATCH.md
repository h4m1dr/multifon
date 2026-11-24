# Xray patch — multi-country Psiphon outbounds + STUN blackhole + DNS routing (Phase 5)

Apply this in the **3x-ui panel's Xray template editor**, not by hand-editing
the running config (3x-ui regenerates it). After every edit, validate before
restarting:

```bash
xray run -test -c /path/to/config.json   # must print "Configuration OK"
```

## 0. Base facts (the actual template, as pasted 2026-11-24)

- DNS servers: `["1.1.1.1", "9.9.9.9", "localhost"]`, `queryStrategy: UseIPv4`.
- Outbounds, only three: `direct` (freedom), `Psiphon-SE` (socks,
  `127.0.0.1:1081`), `blocked` (blackhole).
- No routing section was in the pasted fragment.
- **Tag mismatch:** the outbound is tagged `Psiphon-SE` but the instance on
  1081 is really EgressRegion **CZ**. Rename the tag — routing rules match
  on tags, so a lying tag causes real mistakes later.

## 1. Before you start — get the real ports and inbound tags

1. Create the country set first: menu 3 → 10 (recommended set DE/NL/SE/SG)
   or menu 3 → 1 (any codes). Note the **actual** SOCKS ports it prints —
   use those below, not the numbers in the examples. The examples assume
   CZ is on 1081 and DE/NL/US were created in that order (1082/1083/1084).
2. Read the real `tag` values of the proxy inbounds from the template's
   `inbounds` array. The patch below uses placeholder tags
   `proxy-cz` / `proxy-de` / `proxy-nl` / `proxy-us` — replace them with
   the actual values. If the proxy inbounds have no tags, add them first.

## 2. New outbounds — Psiphon DE / NL / US (+ fix the CZ tag)

SOCKS outbound, simplified shape (verified from the Xray docs — only
SOCKS5 servers are supported). Keep `direct` **first** in the outbounds
array: the first outbound is the default for traffic no rule matches.
Fix the existing tag (`Psiphon-SE` → `Psiphon-CZ`, port 1081 stays).

```json
{ "tag": "Psiphon-CZ", "protocol": "socks",
  "settings": { "address": "127.0.0.1", "port": 1081 } },
{ "tag": "Psiphon-DE", "protocol": "socks",
  "settings": { "address": "127.0.0.1", "port": 1082 } },
{ "tag": "Psiphon-NL", "protocol": "socks",
  "settings": { "address": "127.0.0.1", "port": 1083 } },
{ "tag": "Psiphon-US", "protocol": "socks",
  "settings": { "address": "127.0.0.1", "port": 1084 } }
```

## 3. Routing rules — inbound → outbound, STUN blackholed first

Rules are evaluated top to bottom; **first match wins**. The STUN block
must come first, so STUN UDP is blackholed even when it arrives on a
proxy inbound:

```json
"routing": {
  "domainStrategy": "AsIs",
  "rules": [
    { "type": "field", "port": "3478,5349,19302", "network": "udp",
      "outboundTag": "blocked" },
    { "type": "field", "inboundTag": ["proxy-cz"],
      "outboundTag": "Psiphon-CZ" },
    { "type": "field", "inboundTag": ["proxy-de"],
      "outboundTag": "Psiphon-DE" },
    { "type": "field", "inboundTag": ["proxy-nl"],
      "outboundTag": "Psiphon-NL" },
    { "type": "field", "inboundTag": ["proxy-us"],
      "outboundTag": "Psiphon-US" },
    { "type": "field", "ip": ["1.1.1.1", "9.9.9.9"],
      "outboundTag": "Psiphon-CZ" }
  ]
}
```

Notes on the rules:

- **STUN rule.** Ports 3478 (STUN), 5349 (TURN), 19302 (Google STUN), UDP
  only → `blocked`. Validate the `"3478,5349,19302"` port-list form with
  `xray run -test`; if rejected, split into three rules (one port each).
- **InboundTag rules.** Each proxy inbound's traffic goes to the matching
  Psiphon outbound. Without these rules everything falls through to the
  default (`direct`) — the outbounds alone change nothing.
- **DNS rule (last).** The Xray docs state it explicitly: *"DNS queries
  sent by the built-in DNS server are automatically forwarded based on
  the routing configuration."* So a rule matching the DNS server IPs
  routes Xray's own DNS lookups through the proxy outbound — DNS egress
  then matches TCP egress. This rule points DNS at **one** egress (here
  CZ, the active one); when the active egress changes, this rule must
  change with it — or move to the per-egress DoH forwarder
  (menu 8 → 4) with a `tcp://127.0.0.1:53xx` server entry.
- **Drop `"localhost"` from the DNS servers list** once the proxy routing
  is in: `localhost` means the system resolver (`/etc/resolv.conf`),
  which bypasses the proxy. Keep only the proxied servers.

### Optional: point Xray's DNS at the per-egress DoH forwarders

Instead of the DNS-IP routing rule above, point the built-in DNS at the
listener of the **active** egress (menu 8 → 4 starts them):

```json
"dns": {
  "servers": ["tcp://127.0.0.1:5353", "tcp://127.0.0.1:5354"],
  "queryStrategy": "UseIPv4"
}
```

Validate the exact server-string form with `xray run -test` — if the
string form is rejected, use the object form
`{ "address": "tcp://127.0.0.1", "port": 5353 }`.

## 4. What the STUN rule can and cannot do

- It blackholes **only UDP that reaches Xray**. In proxy-only client mode
  (browser → SOCKS proxy, no TUN), WebRTC UDP goes direct from Windows
  to the internet and never touches the server — the rule cannot see it.
  That is why the −20% WebRTC deduction survives a server-side-only fix,
  and why the Windows side (TUN, or the Chromium flag — see
  docs/TEST-WARP-TOR.md §3) is decisive.
- With TUN on (or a client that sends UDP through the proxy), the rule
  does its job: STUN candidates get no answer, the leak closes at the
  server.

## 5. What breaks if the port-53 block is enabled at the same time

Two different blocks — do not confuse them:

- **Server-wide port-53 block (the original v2 bug): BREAKS EVERYTHING.**
  Xray's DNS servers are plain `1.1.1.1:53` / `9.9.9.9:53` (UDP/53).
  Block outbound UDP/53 host-wide and Xray cannot resolve any hostname:
  domain routing fails, the `freedom` outbound cannot resolve, and every
  config that depends on a name breaks. `apt`/`dig` break too. **Never
  enable a host-wide port-53 block.**
- **v2.1 scoped block (what actually shipped, PR #2): SAFE for Xray.** It
  uses an iptables owner-match on the dedicated `multifon` user, and Xray
  / `apt` / `dig` run as root, so they never match the rule. One
  documented exception: the sandbox uid may still query 1.1.1.1 /
  8.8.8.8 / 9.9.9.9, which Psiphon needs for bootstrap DNS.
- **The one way the scoped block still breaks Xray:** if Xray itself were
  ever run as the `multifon` user, its UDP/53 would match the rule. Never
  run Xray under that uid — keep it as root (as it is now).
- **Order of operations:** (1) add outbounds + routing, test with
  `xray run -test`, restart, verify IP/DNS on the client; (2) only then
  consider any further DNS tightening. If Xray DNS is ever switched to
  DoH (`https://dns.google/dns-query`, port 443), a port-53 block becomes
  safe for Xray even in principle — but still scope it, because
  `apt`/`dig` need port 53.

## 6. TO-CONFIRM (before applying)

- [ ] The real inbound tags in the template (placeholders above must be
      replaced with the actual values).
- [ ] Whether `"3478,5349,19302"` is accepted as one port-list value
      (validate with `xray run -test`; split into three rules if not).
- [ ] The exact server-string form for a `tcp://127.0.0.1:53xx` DNS entry
      (validate the same way; object form is the fallback).
- [ ] The actual SOCKS ports of the created instances (menu 3 → 10 prints
      them) — the 1082/1083/1084 numbers above are examples, not facts.

## Sources

- Xray DNS docs (server address forms, `queryStrategy`, and the TIP that
  built-in DNS queries follow the routing config):
  https://xtls.github.io/Xray-docs-next/config/dns.html
- Xray SOCKS outbound (simplified `address`/`port` shape, "Only
  connections to Socks 5 servers are supported"):
  https://xtls.github.io/Xray-docs-next/config/outbounds/socks.html
- Xray routing (first match wins; `inboundTag`, `port`, `network`, `ip`
  rule fields): https://xtls.github.io/Xray-docs-next/config/routing.html
