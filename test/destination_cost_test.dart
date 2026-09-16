import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/room_calibration.dart';
import 'package:sonority/features/widgets/speaker_picker.dart';
import 'package:sonority/l10n/app_localizations.dart';

/// What the DESTINATION of a bond costs — the half no source bond knows about.
///
/// A bonding change costs the bond it CREATES, not only the ones it empties
/// (CLAUDE.md, Q20/Q8a). Pricing only stolen speakers left the most ordinary
/// destructive action in the app — pair two tuned speakers — priced at zero.
void main() {
  const a = 'RINCON_A01400';
  const b = 'RINCON_B01400';
  const c = 'RINCON_C01400';

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  SonosDevice dev(String uuid, String room) => SonosDevice(
      uuid: uuid, roomName: room, modelName: 'Sonos One SL', ip: '1.2.3.4');

  const tuned = RoomCalibration(available: true, enabled: true);
  const untuned = RoomCalibration(available: false, enabled: false);

  // Three standalone speakers, nothing bonded anywhere.
  final free = SonosSystem(
    groups: [
      for (final u in [a, b, c])
        ZoneGroup(coordinatorUuid: u, members: [
          ZoneGroupMember(uuid: u, zoneName: 'Room $u'),
        ]),
    ],
    devicesByUuid: {a: dev(a, 'Keuken'), b: dev(b, 'Bureau'), c: dev(c, 'Hal')},
  );

  PickerContext ctx({required bool writes, Map<String, RoomCalibration>? cal}) =>
      PickerContext(
        system: free,
        calibration: cal ?? {a: tuned, b: tuned, c: tuned},
        writes: writes,
      );

  test('pairing two tuned standalone speakers names BOTH of them', () {
    final cost = ctx(writes: true).tuningCost(l10n, {a, b});
    expect(cost.count, 2);
    expect(cost.names, ['Bureau', 'Keuken']);
    expect(ctx(writes: true).warning(l10n, {a, b}), isNotNull,
        reason: 'the flagship destructive action used to warn about nothing');
  });

  test('only the speakers actually in the selection are charged', () {
    expect(ctx(writes: true).tuningCost(l10n, {a, b}).names,
        isNot(contains('Hal')));
  });

  test('an untuned speaker is not named — there is nothing to lose', () {
    final cost = ctx(writes: true, cal: {a: tuned, b: untuned})
        .tuningCost(l10n, {a, b});
    expect(cost.names, ['Keuken']);
    expect(cost.count, 1);
  });

  test('a no-op apply still costs nothing', () {
    expect(ctx(writes: false).tuningCost(l10n, {a, b}).names, isEmpty);
    expect(ctx(writes: false).warning(l10n, {a, b}), isNull);
  });

  group('a dissolve is stated even when nothing is tuned', () {
    // The review step is the only gate before Apply — the removal confirm
    // dialog was deleted in favour of it — and an UNTUNED group priced nothing,
    // so the card said nothing destructive about a dissolve it was causing.
    // Untuned is the common case: Trueplay can't be measured from Android.
    const x = 'RINCON_X01400';
    const y = 'RINCON_Y01400';
    const z = 'RINCON_Z01400';

    final withGroups = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: x, members: const [
          ZoneGroupMember(
            uuid: x,
            zoneName: 'Keuken',
            channelMapSet: '$x:LF,RF;$y:LF,RF;$z:LF,RF',
          ),
        ]),
        ZoneGroup(coordinatorUuid: a, members: const [
          ZoneGroupMember(
            uuid: a,
            zoneName: 'Eetkamer',
            channelMapSet: '$a:LF,LF;$b:RF,RF',
          ),
        ]),
      ],
      devicesByUuid: {
        x: dev(x, 'Keuken'),
        y: dev(y, 'Keuken'),
        z: dev(z, 'Keuken'),
        a: dev(a, 'Eetkamer'),
        b: dev(b, 'Eetkamer'),
      },
    );

    // Every speaker read, and read as UNTUNED — so tuningCost names nobody.
    PickerContext untunedCtx() => PickerContext(
          system: withGroups,
          calibration: {for (final u in [x, y, z, a, b]) u: untuned},
          writes: true,
        );

    test('taking a member of a multi-speaker group names the group', () {
      final c = untunedCtx();
      expect(c.tuningCost(l10n, {y}).names, isEmpty,
          reason: 'nothing tuned — this is the case that went silent');
      expect(c.dissolveNote(l10n, {y}), contains('Keuken'));
    });

    test('a stereo pair is exempt — half a pair is self-evidently not a pair',
        () {
      expect(untunedCtx().dissolveNote(l10n, {b}), isNull);
    });

    test('nothing bonded, nothing dissolves', () {
      expect(untunedCtx().dissolveNote(l10n, {}), isNull);
    });

    test('two source groups are both named, once each', () {
      final note = untunedCtx().dissolveNote(l10n, {y, z})!;
      expect(note, contains('Keuken'));
      expect('Keuken'.allMatches(note).length, 1,
          reason: 'one group, not one line per member taken');
    });
  });

  test('a line-out box is never named as losing a tuning it cannot hold', () {
    // An Amp / Port / Connect has no drivers of its own, so Sonos never tunes
    // it — "re-tune it in the Sonos app" is advice that cannot be followed.
    const amp = 'RINCON_AMP01400';
    final withAmp = SonosSystem(
      groups: [
        ZoneGroup(coordinatorUuid: amp, members: const [
          ZoneGroupMember(uuid: amp, zoneName: 'Salon'),
        ]),
      ],
      devicesByUuid: {
        amp: SonosDevice(
            uuid: amp,
            roomName: 'Salon',
            modelName: 'Sonos Amp',
            ip: '1.2.3.4'),
      },
    );
    final c = PickerContext(
        system: withAmp, calibration: const {}, writes: true);
    // Unread would otherwise count it as at-risk, which is the safe default
    // everywhere else — but not for a box that cannot hold a tuning at all.
    expect(c.tuningCost(l10n, {amp}).names, isEmpty);
    expect(c.warning(l10n, {amp}), isNull);
  });

  group('the Apply gate and the engine agree about what a write is', () {
    const zone = ZoneGroupMember(
      uuid: a,
      zoneName: 'Keuken',
      channelMapSet: '$a:LF,RF;$b:LF,RF;$c:LF,RF',
    );
    const target = {
      a: GroupChannel.both,
      b: GroupChannel.both,
      c: GroupChannel.both,
    };

    test('re-picking the same members in another order is NOT a change', () {
      // The map is built coordinator-first, then in selection order; only the
      // coordinator position is meaningful. An ordered-signature compare read
      // {a,c,b} as a rewrite, so the review card warned and the apply wrote
      // nothing.
      expect(zone.matchesGroupLayout(target, coordUuid: a), isTrue);
    });

    test('moving the coordinator IS a change — it cannot apply in place', () {
      expect(zone.matchesGroupLayout(target, coordUuid: b), isFalse);
    });

    test('a channel change is still a change', () {
      expect(
          zone.matchesGroupLayout(
              {a: GroupChannel.left, b: GroupChannel.both, c: GroupChannel.both},
              coordUuid: a),
          isFalse);
    });

    test('dropping a member is still a change', () {
      expect(
          zone.matchesGroupLayout(
              {a: GroupChannel.both, b: GroupChannel.both},
              coordUuid: a),
          isFalse);
    });

    test('callers that do not care about the coordinator are unaffected', () {
      // The profile active-match check passes no coordUuid.
      expect(zone.matchesGroupLayout(target), isTrue);
    });
  });
}
