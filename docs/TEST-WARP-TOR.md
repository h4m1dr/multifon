# Test procedure — WARP + Tor (Phase 4, test-only)

Both cores are marked **test-only** in `cores.yaml`. Hamidr's experience is
that WARP usually does not respond and Tor never opens Gemini — this test
exists to check that properly, once, with numbers. **If either fails, it
moves to Phase before 6 or is dropped — it does not go into rotation.**

The verified reasons they fail are already known (research 2026-11-24,
`~/workspace/multifon-research/09-serverless-egress.md` §8), so a failure
here is the expected outcome, not a surprise:

- **WARP:** (1) the tunnel itself doesn't connect — WARP is WireGuard over
  UDP; Iranian ISPs block/throttle UDP, fingerprint WireGuard packets, and
  blacklist the default endpoint `engage.cloudflareclient.com:2408`.
  (2) Even when it connects, Google mis-geolocates some Cloudflare egress
  IPs as Iran/Russia, so Gemini answers "not supported in your country"
  (BardErrorInfo 1060). Fix to try before dropping WARP: **WARP-over-MASQUE
  over HTTP/2 (TCP:443)** instead of WireGuard-UDP.
- **Tor:** exit IPs are **publicly listed**, so Google and AI services block
  or heavily challenge all of them at once. Shared dirty IPs + anti-abuse
  + regional compliance = 403/CAPTCHA/account flags. Tor is also slow
  (three hops) — bad for ping.

## 0. Before the test — the Windows side decides the WebRTC result

The server-side part of this test cannot show the WebRTC fix on its own:
in proxy-only mode WebRTC UDP bypasses the server entirely. Do the test
**with TUN on** in the Windows client (v2rayN/NekoRay, run as
administrator, sing-box core), or with the Chromium flag pair as the
fallback:

```
--webrtc-ip-handling-policy=disable_non_proxied_udp --force-webrtc-ip-handling-policy=disable_non_proxied_udp
```

(Both flags together — the single flag alone changed nothing in one
Chrome 154 test.) If TUN is off and the flag is off, the WebRTC result
below will show the real IP no matter what the server does — that is a
client-side result, not a WARP/Tor result.

## 1. WARP test

On the server (mere-cat), as root:

```bash
# 1) Install wireproxy (or menu 7 -> 1)
#    Canonical repo is windtf/wireproxy (transferred home of pufferffish/wireproxy).
# 2) Register with wgcf — no account, no browser, non-interactive.
#    Check the releases page for the newest version; v2.2.31 was newest seen.
curl -L -o wgcf https://github.com/ViRb3/wgcf/releases/download/v2.2.31/wgcf_2.2.31_linux_amd64
chmod +x wgcf
./wgcf register --accept-tos   # writes wgcf-account.toml (device key)
./wgcf generate                # writes wgcf-profile.conf (WireGuard config)
# wgcf-profile.conf contains a PRIVATE KEY — treat it as a secret, never commit it.

# 3) Append the SOCKS section to the generated config and run it:
printf '\n[Socks5]\nBindAddress = 127.0.0.1:1091\n' >> wgcf-profile.conf
wireproxy -c wgcf-profile.conf

# 4) Test through it (socks5h = remote DNS through the proxy):
curl -x socks5h://127.0.0.1:1091 https://ifconfig.me
# expect a Cloudflare IP, not 89.22.230.122
```

Then on Windows, point the client at SOCKS `127.0.0.1:1091` (via the
server's proxy config, same as the Psiphon egress) and check:

| Check | How | Pass looks like | Expected outcome (honest) |
|---|---|---|---|
| Exit IP | `curl` above / ifconfig.me | Cloudflare IP, not the server IP | Often fails: `wgcf register` or the tunnel hangs (UDP blocked) |
| WebRTC leak | browserleaks.com/webrtc | 37.153.186.3 appears nowhere | Passes only with TUN/flag on (§0) |
| Gemini | gemini.google.com | Opens, no "not supported" | Often fails: geo mislabel (BardErrorInfo 1060) |
| IPFighter | ipfighter.com | Score vs the 45% Psiphon baseline | Datacenter −10% stays; WARP is not a residential IP |
| Health check | menu 5 → 2, or `multifon` menu 5 → 3 | `warp IP: … latency: …ms blacklist: …` | Only if the tunnel is up |

If WARP fails at step 2 or 4, try **WARP-over-MASQUE (h2)** before
dropping it: sing-box `masque` outbound / `warp` endpoint with
`mode: masque`, transport `h2` (TCP:443) — see research 09 §3/§8. If
that also fails, WARP moves to Phase before 6.

## 2. Tor test

On the server:

```bash
# 1) Install (or menu 7 -> 2). Ubuntu package first; deb.torproject.org
#    is the newer source but adding a third-party apt source needs hamidr's review.
sudo apt update && sudo apt install -y tor

# 2) torrc (/etc/tor/torrc) — one instance:
#    SocksPort 127.0.0.1:9050
#    ControlPort 127.0.0.1:9051
#    DataDirectory /var/lib/tor
#    RunAsDaemon 1
sudo -u debian-tor tor --verify-config -f /etc/tor/torrc

# 3) Start / stop (tor@default is the unit; tor.service is only a wrapper):
systemctl start tor@default
systemctl status tor@default

# 4) Test through it:
curl -x socks5h://127.0.0.1:9050 https://check.torproject.org/
curl -x socks5h://127.0.0.1:9050 https://ifconfig.me
```

Then on Windows, point the client at SOCKS `127.0.0.1:9050` and check:

| Check | How | Pass looks like | Expected outcome (honest) |
|---|---|---|---|
| Exit IP | `curl` above | A Tor exit IP | Usually works (Tor itself is fine) |
| WebRTC leak | browserleaks.com/webrtc | 37.153.186.3 appears nowhere | Passes only with TUN/flag on (§0) |
| Gemini | gemini.google.com | Opens | **Expected to fail** — exits are publicly listed; Google blocks/challenges them |
| IPFighter | ipfighter.com | Score vs the 45% baseline | **Expected worse** — exits are datacenter-flagged and widely blacklisted |
| Health check | menu 5 → 3 | `tor IP: … latency: …ms blacklist: …` | High latency (three hops) is normal |

## 3. Verdict rule

| Result | What happens |
|---|---|
| WARP connects + Gemini opens | WARP becomes a real core (status `experimental` → `ready` for muse.ai/Qwen; still datacenter for IPFighter). Wire its start/stop into `lib/cores.sh`. |
| WARP connects, Gemini refuses | WARP-over-MASQUE (h2) attempt; if that fails too, WARP → Phase before 6. |
| WARP doesn't connect at all | WARP → Phase before 6 (with the failure reason: UDP blocked / endpoint blacklisted). |
| Tor works but Gemini refuses | Expected. Tor stays a **fallback core only** — never in IP rotation for scoring. |
| Tor doesn't even connect | Tor → Phase before 6 (with the failure reason). |

**Nothing is silently dropped.** A failed core moves to Phase before 6
with its failure reason written down, and only then is it removed from
the rotation — see `docs/PHASES.md`.

## 4. Results (fill in after the test)

| Core | Exit IP | Latency | Gemini | Qwen | muse.ai | IPFighter | Verdict |
|---|---|---|---|---|---|---|---|
| WARP | | | | | | | |
| Tor | | | | | | | |

## Sources

- wgcf register/generate flow, `--accept-tos`, append-`[Socks5]` shortcut:
  https://gist.github.com/adasThePrime/c804c3ad65b8da6956e1ea75d50ff46f
- wireproxy canonical repo (windtf/wireproxy, transferred home):
  https://github.com/ottoboop/sinestesiamusical/commit/523ea8099ea97a02f9b28f9ffe558f1c5c650056
- Tor on Debian/Ubuntu (`tor@default`, `tor-instance-create`,
  `tor --verify-config`): https://support.torproject.org/apt/tor-deb-repo/
- Google mis-geolocates Cloudflare WARP egress IPs:
  https://community.cloudflare.com/t/google-incorrectly-geolocates-cloudflare-warp-egress-ips/948888
- Tor exits blocked — NDSS '16 (3.67% of top-1,000 Alexa sites):
  https://www.theregister.com/security/2016/02/25/tor-users-are-actively-discriminated-against-by-website-operators/1140645
- WARP-over-MASQUE (h2): https://pkg.go.dev/github.com/hiddify/ray2sing/ray2sing
