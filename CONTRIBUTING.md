# Contributing to Sonority

Bug reports, hardware findings and pull requests are all welcome — especially reports
from Sonos models I don't own, since most of what this app knows was derived by testing
against real speakers (see [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)).

## Licensing of contributions — please read before opening a PR

Sonority is **source-available, not open source**: the code is under the
[PolyForm Perimeter License 1.0.1](LICENSE), which lets you read, build, run, modify and
contribute to it, but not ship other people a product that competes with it. Paid builds
on the App Store and Google Play are published by the copyright holder.

Because of that, accepting a contribution needs the right to use it in those builds — so
your PR carries a grant:

> By submitting a pull request, you grant Casper Verswijvelt a perpetual, irrevocable,
> worldwide, royalty-free, non-exclusive license to use, reproduce, modify, distribute,
> sublicense and **relicense** your contribution, including under proprietary terms and
> in binaries distributed through app stores. You keep the copyright in your
> contribution and may use it however you like elsewhere.

Confirm this by signing off each commit, which also certifies you wrote the code and
have the right to submit it (the [Developer Certificate of Origin][dco]):

```
git commit -s -m "your message"     # adds: Signed-off-by: Your Name <you@example.com>
```

If you'd rather not grant that, please open an issue describing the change instead of a
PR — a described fix is genuinely useful and costs you nothing.

## Before you open the PR

- `~/fvm/versions/3.44.6/bin/flutter analyze` and `flutter test` must be green.
- Add a `CHANGELOG.md` entry under `## [Unreleased]` — one line.
- Don't bump `version:` in `pubspec.yaml`; that happens on `main` when a release is cut.
- Anything with a visible result: include a screenshot. Capture it on an **emulator**,
  never a personal device — a real phone's status bar leaks notification icons and
  contact avatars into a public PR.
- Read [CLAUDE.md](CLAUDE.md) first. It documents the product principle (don't duplicate
  features the official Sonos app already has), the pure-Dart engine vs. UI split, and
  the gotchas that cost real debugging — the ≈15s topology lag, poll-until-settled after
  every write, and reading state from the authoritative channel-map attributes.

## Writes hit somebody's real living room

Bonding calls reconfigure hardware that people watch films on, and some of them fail in
ways that need a manual recovery. Keep the existing patterns: snapshot before you write,
gate destructive actions behind an explicit confirmation, make it self-reverting where
you can, and verify by re-reading rather than trusting a `200 OK`. Validate against real
speakers if you have them — the `tool/` CLI spikes exist for exactly that, and most are
read-only or self-restoring.

[dco]: https://developercertificate.org/
