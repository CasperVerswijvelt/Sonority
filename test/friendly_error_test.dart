import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/cancellation.dart';
import 'package:sonority/data/sonos/friendly_error.dart';
import 'package:sonority/data/sonos/identify_errors.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonority_error.dart';

void main() {
  group('friendlyError', () {
    test('an abort keeps its terse reason verbatim', () {
      expect(friendlyError(const OperationCancelled()), 'Aborted');
    });

    test('a timeout reads as a plain sentence', () {
      expect(friendlyError(TimeoutException('x')),
          contains('didn’t respond in time'));
    });

    test('SpeakerUnreachable passes through its own friendly message', () {
      expect(friendlyError(const SpeakerUnreachable()),
          const SpeakerUnreachable().toString());
    });

    test('known Sonos fault codes map to sentences (no raw exception text)', () {
      final busy =
          friendlyError(SonosSoapException('AddHTSatellite', faultCode: '800'));
      expect(busy, contains('busy rearranging'));
      expect(busy, isNot(contains('SonosSoapException')));

      expect(friendlyError(SonosSoapException('AddHTSatellite', faultCode: '401')),
          contains('unsupported'));
      expect(friendlyError(SonosSoapException('SetZoneAttributes', faultCode: '402')),
          contains('invalid'));
    });

    test('an unknown fault code still names the code and points at the log', () {
      final msg =
          friendlyError(SonosSoapException('Foo', statusCode: 500, faultCode: '701'));
      expect(msg, contains('701'));
      expect(msg, contains('raw log'));
    });

    test('a bare exception drops the noisy "Exception: " prefix', () {
      expect(friendlyError(Exception('Sonos did not remove the Surrounds — try again.')),
          'Sonos did not remove the Surrounds — try again.');
    });

    test('a coded SonorityError renders its English message', () {
      expect(friendlyError(const SonorityError(SonorityErrorCode.groupNeedsTwo)),
          'A group needs at least 2 speakers.');
      expect(
          friendlyError(
              const SonorityError(SonorityErrorCode.didNotRemove, 'Surrounds')),
          'Sonos did not remove the Surrounds — try again.');
      expect(
          friendlyError(
              const SonorityError(SonorityErrorCode.entityNotOnNetwork, 'Den')),
          '“Den” isn’t on the network.');
    });
  });
}
