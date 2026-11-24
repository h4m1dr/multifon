# Services — what is fixed, what is not, and where to exit from

This is the honest scoreboard for the IPFighter work. Nothing here is
a promise: the numbers are hamidr's own measurements, and flagging is
per-IP reputation, not per-country. Verify the actual exit IP with
`multifon fix` (menu 11) instead of trusting a country code.

## The checklist — every IPFighter deduction

| Deduction | Points | Status in v2.1 | What fixes it |
| --- | --- | --- | --- |
| WebRTC leak | −20% | **Partial** | Scoped STUN block (UDP 3478/5349/19302, REJECT) catches traffic that reaches the server. In proxy-only client mode the browser's STUN UDP never reaches the server, so the client still needs TUN mode or Chromium `--force-webrtc-ip-handling-policy=disable_non_proxied_udp`. |
| DNS leak | −5% | **Mostly fixed** | DoH through the same SOCKS works (`dns_doh_query`); the scoped port-53 block (v2.3, `multifon` group only) stops leaks to arbitrary resolvers. The per-egress DoH listener is still Phase 4. |
| Timezone mismatch | −15% | **NOT fixable server-side** | IPFighter compares the exact IANA zone name of the *browser*. The sandbox TZ set per egress (v2.1, now a systemd unit `Environment=TZ` + zoneinfo bind since v2.3) only affects the psiphon process inside its unit. The browser/OS timezone must be set to the exit country. |
| Non-residential IP | −10% | **NOT fixable** | Psiphon, WARP and Tor exits are datacenter IPs. No server-side trick makes one residential. |
| IP blacklisted (2/10) | −10% | **Detected, rotation on request** | Health check covers the two lists IPFighter deducts for (zen.spamhaus.org, cb1.abuseat.org). `multifon fix` offers to rotate a listed IP (with confirmation). Fully automatic rotation is still pending (Phase 3). |

## The ceiling — no invented numbers

- Good IP measured: **60%** (Sweden IPv6 exit, 4 deductions).
- Bad IP measured: **45%** (Japan proxied exit, WebRTC leak included).
- With everything server-side fixed, the good IP goes **60% → 75%**
  (100 − 15 timezone − 10 non-residential). The bad IP goes
  45% → 65% with the WebRTC fix, → 75% if its IP also becomes clean.
- The target agreed with hamidr is **above 70, ideally above 80, not
  100** — 75% is the server-side ceiling, so the last points can only
  come from the client side (browser timezone).

## Where to exit, per service

From `services.yaml` (same file the menu will read in Phase 4):

| Service | Try in this order | Why |
| --- | --- | --- |
| Gemini | DE, NL, SE, SG | Available in 150+ countries incl. these; Sweden exit opened it normally; EU exits showed the least friction. |
| Qwen | SG, JP, DE | Opens without a VPN in most regions; Alibaba international endpoints are Singapore / US / Frankfurt. |
| Muse | WARP, DE, NL | Behind Cloudflare — WARP (Phase 4) is Cloudflare's own network; otherwise a clean DE/NL IP. His muse.ai failure was a local Chrome extension block, not the exit IP. |
| Flow | DE, NL, SE, SG | Google Flow — same infra and availability as Gemini. |
| ChatGPT | US, DE, NL | US-first; EU works but some features are US-only, US exits see more CAPTCHA. |
| Claude | US, DE, NL | Available in US/EU; same trade-off as ChatGPT. |

## How to use this

1. `multifon fix` (or menu 11) — runs the checklist: doctor sync,
   health check, rotate dirty IPs, DNS leak check, scoped blocks.
2. Pick the country from the table above for the service you need
   (`menu 3 → 8` changes a location's region).
3. Re-test on IPFighter from the client, with the browser timezone set
   to the exit country — that is the only way the −15% moves.
