# App Store listing copy — Sonority

Paste these into App Store Connect. Character limits noted; stay under them.
Support email + the hosted privacy/support URLs are filled in below. The only
remaining placeholder is `DEMO_VIDEO_URL` (in the review notes) — record the demo
first, then paste its link.

> **Trademark note (important for review):** "Sonos" is deliberately kept out of
> the **app name, subtitle, and icon**. It appears only descriptively in the
> body + keywords, always with the disclaimer. This is what keeps the listing on
> the right side of Guideline 5.2.1. Don't move "Sonos" into the name/subtitle.

---

## App name (≤30)

```
Sonority
```

## Subtitle (≤30)

```
Advanced home-theater setups
```

## Promotional text (≤170, editable anytime without review)

```
Create the speaker layouts the standard app won’t: dedicated front speakers on your soundbar, mismatched stereo pairs, and more. Your speakers, your rules.
```

## Keywords (≤100, comma-separated, not shown publicly)

```
sonos,home theater,surround,stereo pair,speakers,soundbar,satellite,front,5.1,trueplay,amp,wifi
```

(Trim to fit 100 chars. "sonos" as a keyword for an app that controls Sonos is
common but carries a small rejection risk — drop it first if asked.)

## Description (≤4000)

```
Sonority configures your speakers in ways the standard controller app doesn’t allow — using only the local network connection on your home Wi-Fi. It does no audio processing of its own; all the sound comes from your real speakers. The configurations it creates are standard, supported speaker bondings — just ones the official app chooses not to expose.

WHAT YOU CAN DO

• Dedicated front speakers on a soundbar — add a discrete left/right pair so your bar acts as the center channel, for a true three-speaker front stage.
• Use a single amplifier to drive both passive front speakers.
• Stereo pairs the standard app won’t create — including mismatched models.
• Identify which physical speaker is which by blinking its status light (or playing a short chime on iPhone/iPad).
• Toggle a speaker’s room-calibration tuning on or off.

Every change is made over your local network, is shown to you before it’s applied, and is fully reversible from within the app.

PRIVACY

No account. No sign-in. No analytics, no tracking, and no data collected. Sonority talks only to the speakers on your own Wi-Fi network — nothing leaves your home.

REQUIREMENTS

Compatible speakers on the same Wi-Fi network as your device. Room-calibration tuning, where supported, is measured in the manufacturer’s own app; Sonority only switches an existing tuning on or off.

—

Sonority is an independent app and is not affiliated with, authorized, maintained, sponsored, or endorsed by Sonos, Inc. “Sonos” is a trademark of Sonos, Inc., used here only to describe compatibility.
```

## What's New (first release)

```
First release of Sonority:
• Dedicated front speakers on a soundbar
• Stereo pairs, including mismatched models
• Identify speakers by blinking their light
• Toggle room-calibration tuning
```

## Support / marketing URLs

- Support URL: `https://casperverswijvelt.be/Sonority/support.html`
- Marketing URL (optional): `https://casperverswijvelt.be/Sonority/`
- Privacy Policy URL: `https://casperverswijvelt.be/Sonority/privacy-policy.html` ← **required**

(Canonical custom domain; the `casperverswijvelt.github.io/Sonority/…` URLs
301-redirect here, so either works — but App Store Connect prefers the final URL.)

## Category & rating

- Primary category: **Utilities** (alt: Music)
- Age rating: 4+ (no objectionable content)
- Price: **$1.49 / €1.49** tier

---

## App Review notes (paste into "Notes for Review") — READ THIS

App Review almost certainly does **not** have compatible speakers on their test
network, so the app will look empty to them. Pre-empt a "can't evaluate / app
incomplete" rejection:

```
Sonority controls third-party speakers over the LOCAL network (UPnP on the LAN);
it uses no private Apple APIs and requires no login. It needs compatible speakers
on the same Wi-Fi to do anything, which a test device likely won't have, so the
discovery screen will appear empty in review.

A short demo video showing the full flow on real hardware is here: DEMO_VIDEO_URL

All configurations the app creates are standard, supported speaker bondings made
via the manufacturer's documented local network service, are previewed before
being applied, and are fully reversible in-app. The app is independent and not
affiliated with the speaker manufacturer; this is stated in the description.

Contact for any questions: casperverswijveltdev@gmail.com
```

Record a ~60s screen capture of discovery → adding fronts → identify → undo, and
host it (unlisted YouTube/Vimeo or a direct link); put the URL in `DEMO_VIDEO_URL`.

```

```
