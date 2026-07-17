# Hardware compatibility — unofficial layouts

What real hardware has been confirmed to **work** (or **not work**) for the
bonding configs Sonority unlocks. Recorded so we don't re-derive it from user
reports every time.

## The core caveat: a clean bond ≠ audio

The Sonos local API accepts almost any channel map and stores it verbatim — it
does essentially no validation (see the zone-probe findings in `CLAUDE.md`). But
whether the **soundbar firmware actually routes audio** to an unofficially-bonded
speaker is **per-model / per-firmware and is NOT discoverable from the API**. A
bond can:

- apply with zero SOAP faults,
- read back with the exact channel map you wrote,
- be confirmed by the official Sonos app,

…and still produce **no sound**. So "it configured" is not evidence it works —
only heard audio is. This is why we track confirmed combos here.

> **Privacy:** this file records **model + channel-role only**. No room names,
> UUIDs, IPs, MACs, serials, households, or any personal detail — none of that is
> needed to capture a compatibility finding.

Firmware is recorded because audio routing is per-model **and** per-firmware —
though so far the differentiator has been the *model*, not the firmware (the
working Beam and the silent Arc Ultra are on near-identical `96.x` builds).

## Dedicated fronts (soundbar becomes center, external speakers take L/R)

Fronts can be either **two discrete speakers** (one `LF`, one `RF`) or **one Amp
on both** (`AMP:LF,RF`). Both are tracked below.

| Soundbar          | Soundbar fw  | Fronts device        | Result       | Source         |
|-------------------|--------------|----------------------|--------------|----------------|
| Beam (Gen 2, S31) | 96.1-78270   | 2× One SL (S22), discrete | ✅ audio | developer (live) |
| Playbase          | (unknown)    | Connect:Amp (Gen 2)  | ✅ audio     | user-confirmed |
| Arc Ultra (S45)   | 96.0-78270   | Amp (S16), fw 96.0-78270 | ❌ silent | user-confirmed |

### ✅ Beam (Gen 2, S31) + 2× One SL (discrete fronts) — works

The developer's live, daily-use home theater. Full layout:

- Beam (Gen 2, S31) — center (`CC`)
- 2× One SL (S22) — dedicated fronts (`LF` / `RF`)
- 2× Play:1 (S1) — surrounds (`LR` / `RR`)
- Sub — sub (`SW`)

Confirms **discrete-speaker dedicated fronts work on a Beam**. (The S1-generation
Play:1s and Sub sit on the older `86.8` firmware track; the Beam/One SL on `96.1`
— a mixed-firmware HT bonds and plays fine.) This is also the bonding engine's
primary test rig — `AddHTSatellite` re-assertion, the diff-based apply, one-call
full-layout rebuild, and remove/rebond are all validated here (see `CLAUDE.md`).

### ✅ Playbase + Sonos Connect:Amp (Gen 2) — works (amp fronts)

- Audio confirmed by the user (front L/R come out of the passive speakers on the Amp).
- Both devices wired (LAN, Wi-Fi off). Wired vs Wi-Fi made no difference.
- The Amp drives both fronts as one device: `AMP:LF,RF` (amp-mode, exclusive selection).

### ❌ Arc Ultra (S45) + Sonos Amp (S16) — configures but silent (amp fronts)

The bond applies perfectly and the map reads back correct, but **no sound comes
from the Amp's passive speakers**. Extensively tested by the user:

- Full 5.1.2 HT (Era 100 surrounds `LR,LTR`/`RR,RTR` + Sub Mini `SW`) with the Amp added as fronts — silent.
- **Bare bar + Amp fronts only** (`BAR:CC;AMP:LF,RF`, nothing else bonded) — still silent.
- Tried on **both iPad (iOS) and Android**, and with the Amp on **both LAN and Wi-Fi** — all silent.

Sonority did everything right: clean bond, minimal correct map — the **same map
shape that works on the Playbase above**. The failure is downstream in Sonos
firmware.

**Ruled out:** app apply bug · additive-vs-rebuild apply path (bare bar fails
too) · platform (iPad + Android) · wired vs Wi-Fi · map correctness.

**Remaining suspects (unconfirmed):**
1. The Arc Ultra (Atmos bar) does not route front L/R to a *satellite* speaker
   the way older bars (Playbase/Playbar/Beam) do.
2. The newer Sonos Amp (S16) does not render front-channel content when bonded to
   an Arc Ultra.

**Pending test that would decide it:** play music **directly on the Amp as a
standalone room** (ungrouped) in the official Sonos app.
- Passive speakers play → Amp/wiring is fine; the Arc Ultra isn't routing fronts (suspect #1) — nothing Sonority can fix.
- Still silent → the Amp's own setup/wiring, unrelated to Sonority.

## Notes / recurring gotchas

- **"Needs attention" + phantom "not connected" products in the official Sonos
  app are benign.** They appear on *working* setups too (confirmed on the Beam
  rig). Not a signal that a bond failed.
- **Unverified community reports are weak evidence.** A r/SonoSequencr post
  claiming "Arc Ultra + Amp works" is not confirmation — the poster may have hit
  the same *bond-applies-but-silent* false positive (which two users here hit
  before verifying audio). Only treat a combo as ✅ once someone reports **heard
  audio**.
- **Amp as fronts is one device on both channels** (`AMP:LF,RF`), exclusive
  selection — not two separate front speakers. The passive speakers wired to the
  Amp are not network devices and correctly never appear in the app.

## Adding a finding

One row in the table + a short subsection. Record: soundbar model, bonded
device + channel role, **result (audio heard? yes/no)**, and how it was verified.
Model + role only — no private info.
