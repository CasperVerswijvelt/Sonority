import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/zone_api.dart';
import 'package:sonority/data/sonos/zone_layout.dart';

const a = 'RINCON_AAA01400';
const b = 'RINCON_BBB01400';
const c = 'RINCON_CCC01400';
const sub = 'RINCON_SUB01400';

void main() {
  group('groupEditIsPureDrop', () {
    // The whole point of the predicate: this is the shape
    // `zones.updateZoneDefinition` accepts and `AddBondedZones` faults on.
    test('dropping a member, coordinator and channels unchanged', () {
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,RF;$b:LF,RF;$c:LF,RF',
          targetMap: '$a:LF,RF;$b:LF,RF',
        ),
        isTrue,
      );
    });

    test('dropping a sub counts as a pure drop', () {
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,LF;$b:RF,RF;$sub:SW',
          targetMap: '$a:LF,LF;$b:RF,RF',
        ),
        isTrue,
      );
    });

    test('adding a member is not a drop', () {
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,RF;$b:LF,RF',
          targetMap: '$a:LF,RF;$b:LF,RF;$c:LF,RF',
        ),
        isFalse,
      );
    });

    // The namespace refuses add+remove together ("update only allows add or
    // remove, not both"), so a swap must not take the in-place path.
    test('swapping one member for another is not a pure drop', () {
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,RF;$b:LF,RF',
          targetMap: '$a:LF,RF;$c:LF,RF',
        ),
        isFalse,
      );
    });

    // Also refused: a channel reassignment, even alongside a genuine removal.
    test('dropping a member AND reassigning channels is not a pure drop', () {
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,RF;$b:LF,RF;$c:LF,RF',
          targetMap: '$a:LF,LF;$b:RF,RF',
        ),
        isFalse,
      );
    });

    test('a coordinator change is not a pure drop', () {
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,RF;$b:LF,RF;$c:LF,RF',
          targetMap: '$b:LF,RF;$c:LF,RF',
        ),
        isFalse,
      );
    });

    test('an unchanged membership is not a drop (nothing to do)', () {
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,RF;$b:LF,RF',
          targetMap: '$a:LF,RF;$b:LF,RF',
        ),
        isFalse,
      );
    });

    test('token ORDER does not matter, only the set', () {
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,RF;$b:RF,LF;$c:LF,RF',
          targetMap: '$a:RF,LF;$b:LF,RF',
        ),
        isTrue,
      );
    });

    test('empty maps are never a pure drop', () {
      expect(
        groupEditIsPureDrop(currentMap: '', targetMap: '$a:LF,RF'),
        isFalse,
      );
      expect(
        groupEditIsPureDrop(currentMap: '$a:LF,RF', targetMap: ''),
        isFalse,
      );
    });
  });

  group('sameChannelMap', () {
    // Definition reuse hangs off this: the namespace does no dedupe, so a false
    // negative here means a new stored definition on every single apply.
    test('identical maps match', () {
      expect(sameChannelMap('$a:LF,RF;$b:LF,RF', '$a:LF,RF;$b:LF,RF'), isTrue);
    });

    test('token order within an entry is irrelevant', () {
      expect(sameChannelMap('$a:LF,RF;$b:LF,RF', '$a:RF,LF;$b:LF,RF'), isTrue);
    });

    // The first entry is the coordinator, so entry order IS significant.
    test('a different entry order is a different bond', () {
      expect(sameChannelMap('$a:LF,RF;$b:LF,RF', '$b:LF,RF;$a:LF,RF'), isFalse);
    });

    test('different channels do not match', () {
      expect(sameChannelMap('$a:LF,LF;$b:RF,RF', '$a:LF,RF;$b:LF,RF'), isFalse);
    });

    test('a different membership does not match', () {
      expect(sameChannelMap('$a:LF,RF;$b:LF,RF', '$a:LF,RF;$c:LF,RF'), isFalse);
      expect(sameChannelMap('$a:LF,RF;$b:LF,RF', '$a:LF,RF'), isFalse);
    });

    test('empty maps never match (nothing to reuse)', () {
      expect(sameChannelMap('', ''), isFalse);
    });
  });

  group('sameChannelMap token multiplicity', () {
    // `LF,LF` (a stereo pair's single-sided left) is a DIFFERENT assignment from
    // `LF` (a home theater's front-left). A set compare calls them equal, which
    // would reuse a stored definition that isn't the map we asked for.
    test('a repeated token is not the same as a single one', () {
      expect(sameChannelMap('$a:LF,LF;$b:RF,RF', '$a:LF;$b:RF'), isFalse);
      expect(
        groupEditIsPureDrop(
          currentMap: '$a:LF,LF;$b:RF,RF;$c:LF,RF',
          targetMap: '$a:LF;$b:RF',
        ),
        isFalse,
      );
    });
  });

  group('zoneMembersFromMap', () {
    // The engine's `UUID:CH;…` recipes have to feed the namespace verbatim —
    // same assignments, JSON-shaped.
    test('converts an engine channel map to the namespace shape', () {
      expect(zoneMembersFromMap('$a:LF,LF;$b:RF,RF;$sub:SW'), [
        {
          'id': a,
          'channels': ['LF', 'LF'],
        },
        {
          'id': b,
          'channels': ['RF', 'RF'],
        },
        {
          'id': sub,
          'channels': ['SW'],
        },
      ]);
    });

    test('an empty map yields no members', () {
      expect(zoneMembersFromMap(''), isEmpty);
    });
  });

  group('ZoneApiClient', () {
    // Nothing may write by accident: the live gate is the only thing standing
    // between a refresh and a real bonding change on someone's living room.
    test('updateDefinition refuses to write without live: true', () {
      expect(
        () => const ZoneApiClient().updateDefinition(
          ip: '192.0.2.1',
          zoneId: 'zone-1',
          rawMap: '$a:LF,RF;$b:LF,RF',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
