import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/data/sonos/soap_client.dart';
import 'package:sonority/data/sonos/sonos_repository.dart';
import 'package:sonority/state/sonos_controller.dart';

/// A failed write must NOT clobber the known topology. All write ops funnel
/// through `SonosController._commit`; on a non-cancel error (e.g. a
/// [SonosSoapException] from a bond/rename mid-reshuffle) it restores the
/// last-known system and rethrows, so the overview keeps showing the system
/// while the progress screen / snackbar surfaces the error. Driven here via the
/// leanest `_commit` caller (`renameRoom`).
const _uuid = 'RINCON_A01400';
const _ip = '192.168.1.10';

const _device =
    SonosDevice(uuid: _uuid, roomName: 'Living', modelName: 'Sonos One', ip: _ip);

const _system = SonosSystem(
  groups: [
    ZoneGroup(coordinatorUuid: _uuid, members: [
      ZoneGroupMember(uuid: _uuid, zoneName: 'Living'),
    ]),
  ],
  devicesByUuid: {_uuid: _device},
);

/// Discovers a fixed system but faults every write with a SOAP error.
class _FaultingRepo extends SonosRepository {
  @override
  Future<SonosSystem> discover() async => _system;

  @override
  Future<bool> setRoomName({required String ip, required String name}) =>
      throw SonosSoapException('SetZoneAttributes', statusCode: 500);
}

void main() {
  test('a SonosSoapException on a write keeps the topology, not an error state',
      () async {
    final container = ProviderContainer(
      overrides: [sonosRepositoryProvider.overrideWithValue(_FaultingRepo())],
    );
    addTearDown(container.dispose);

    // Force the initial discover so `state` holds the seeded system.
    final system = await container.read(sonosControllerProvider.future);
    expect(system, same(_system));

    // The write throws...
    await expectLater(
      container
          .read(sonosControllerProvider.notifier)
          .renameRoom(device: _device, name: 'Kitchen'),
      throwsA(isA<SonosSoapException>()),
    );

    // ...but the overview still sees the last-known system, not an AsyncError.
    final after = container.read(sonosControllerProvider);
    expect(after.hasError, isFalse);
    expect(after.value, same(_system));
  });
}
