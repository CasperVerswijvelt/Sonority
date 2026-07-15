# App Store listing copy — Sonority

Paste these into App Store Connect. Character limits noted; stay under them.
Support email + the hosted privacy/support URLs are filled in below. The only
remaining placeholder is `DEMO_VIDEO_URL` (in the review notes) — record the demo
first, then paste its link.

> **Trademark note (important for review):** the intended-safe listing keeps
> "Sonos" out of the **app name, subtitle, and icon** — it appears only
> descriptively in the body + keywords, always with the disclaimer, to stay on
> the right side of Guideline 5.2.1 / 4.1(a). **Current state (Jul 2026):** the
> App Store Connect app record is titled **"Sonority for Sonos"** and that name is
> being *contested* after a 4.1(a) rejection (see Review history at the bottom).
> If Apple holds the rejection, the fallback is to rename the record to the plain
> **"Sonority"** used here. Don't add "Sonos" to the name/subtitle beyond the
> record title already under review.

---

## App name (≤30)

```
Sonority
```

## Subtitle (≤30)

```
Home theater, pairs & profiles
```

## Promotional text (≤170, editable anytime without review)

```
Create the speaker setups the standard app won’t: dedicated front speakers, stereo pairs and zones, full surround sound — then save your layout as a one-tap profile.
```

## Keywords (≤100, comma-separated, not shown publicly)

```
sonos,home theater,surround,stereo pair,zone,profile,speakers,soundbar,5.1,trueplay,front,widget
```

(Trim to fit 100 chars. "sonos" as a keyword for an app that controls Sonos is
common but carries a small rejection risk — drop it first if asked.)

## Description (≤4000)

```
Sonority configures your speakers in ways the standard controller app doesn’t allow — using only the local network connection on your home Wi-Fi. It does no audio processing of its own; all the sound comes from your real speakers. The configurations it creates are standard, supported speaker bondings — just ones the official app chooses not to expose.

WHAT YOU CAN DO

• Dedicated front speakers on a soundbar — add a discrete left/right pair so your bar becomes the center channel, for a true three-speaker front stage.
• Build a complete home theater in one guided flow — fronts, rear surrounds and one or two subs, each optional.
• Use a single amplifier to drive both passive front speakers.
• Speaker groups the standard app won’t make — full-range zones of 2–16 speakers, stereo pairs (including mismatched models), or a custom per-speaker left/right/both layout, each with an optional sub.
• Config profiles — snapshot your whole layout and rebuild it in one tap after moving speakers around. Each profile gets its own icon and colour, and can also capture and restore per-speaker audio settings (bass, treble, loudness, night sound, speech enhancement, sub and surround levels, lip-sync) and, optionally, volume.
• Apply a profile without opening the app — from a home-screen widget (small, medium or large) or a long-press on the app icon.
• Rename rooms, identify which physical speaker is which by blinking its status light (or a short chime on iPhone/iPad), and toggle a speaker’s room-calibration tuning.
• Diagnostics — a technical, hide-nothing view of your system when something isn’t working, which you can share with support or email to the developer to get help.

Every change is made over your local network, is shown to you before it’s applied, and is fully reversible from within the app.

PRIVACY

No account. No sign-in. No analytics, no tracking, and no data collected. Sonority talks only to the speakers on your own Wi-Fi network — nothing leaves your home.

REQUIREMENTS

Compatible speakers on the same Wi-Fi network as your device. Room-calibration tuning, where supported, is measured in the manufacturer’s own app; Sonority only switches an existing tuning on or off.

—

Sonority is an independent app and is not affiliated with, authorized, maintained, sponsored, or endorsed by Sonos, Inc. “Sonos” is a trademark of Sonos, Inc., used here only to describe compatibility.
```

## What's New

```
• Speaker groups: full-range zones (2–16), stereo pairs and custom per-speaker layouts
• Complete in-app home-theater setup — fronts, rear surrounds and one or two subs
• Config profiles: save a layout and reapply it in one tap, each with its own icon and colour
• Apply a profile from a home-screen widget or a long-press on the app icon
• Profiles can now capture and restore per-speaker audio settings and volume
• Rename rooms; toggle room-calibration tuning
• Dedicated front speakers on a soundbar (a single Amp works too)
• Diagnostics: a technical system view you can share for help when something’s wrong
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

Record a ~60s screen capture of discovery → building a home theater → saving a
profile → identify → undo, and host it (unlisted YouTube/Vimeo or a direct link);
put the URL in `DEMO_VIDEO_URL`.

---

## Review history

### 0.5 (50008) — iOS — rejected Jul 10 2026 (Submission ID `ee2688b7-5ae8-4039-9580-97a72c2ee25e`)

Two issues, reviewed on iPad Air 11" (M3):

1. **Guideline 4.1(a) — Copycats.** Flagged the App Store Connect app-record name
   **"Sonority for Sonos"** as a misleading third-party reference. **Decision:
   contest** (keep the name). Reply sent argues nominative/descriptive use, no
   Sonos logos/imagery/"Works with Sonos" wording, the in-description disclaimer,
   and live precedents **"SonoPhone for Sonos"** (id815251931) and **"SonoPad for
   Sonos"** (id579984303). Draft reply text:

   > Hi, thanks for the review.
   >
   > The word "Sonos" is in our metadata only to say which speakers the app works
   > with. There is no way to describe what the app does without naming the
   > speakers it configures. We do not use any Sonos logos, product photos, or the
   > "Works with Sonos" certification wording anywhere in the app, the icon, or the
   > screenshots.
   >
   > We also make the relationship clear in the app description: "Sonority is an
   > independent app and is not affiliated with, authorized, maintained, sponsored,
   > or endorsed by Sonos, Inc. 'Sonos' is a trademark of Sonos, Inc., used here
   > only to describe compatibility."
   >
   > Naming an independent controller this way is already common on the App Store.
   > Two live examples that use the same "for Sonos" wording are "SonoPhone for
   > Sonos" (id815251931) and "SonoPad for Sonos" (id579984303).
   >
   > If there is one specific field you would like us to change, please let us
   > know and we will be glad to update it.

   **Fallback if held:** rename the ASC record to plain **"Sonority"**.

2. **Guideline 2.1 — Information Needed.** Wanted a demo video on a physical
   device showing pairing + the full workflow. The reviewer's screenshots (added
   to the rejection) show the empty state — they granted local-network access but
   had no speakers on the test LAN, so discovery showed "No Sonos devices found."
   Resolution: film the demo (shot list in the plan) and paste the link into
   `DEMO_VIDEO_URL` above + reply in the ASC thread. No demo account needed.

Follow-up shipped in the next build: the discovery empty state no longer prints an
"Exception:" prefix and centers its wrapped title (both visible-looking-broken in
the reviewer screenshots).

```

```
