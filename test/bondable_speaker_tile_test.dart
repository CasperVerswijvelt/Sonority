import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/models/sonos_models.dart';
import 'package:sonority/features/widgets/bondable_speaker_tile.dart';
import 'package:sonority/l10n/app_localizations.dart';

/// An unreachable speaker is one whose `device_description.xml` we couldn't
/// read. It may still be bonded — the group edit flow merges a group's own
/// members back into the picker — so the tile has to tell the truth about
/// whether it's in the selection, while refusing to let a new one be added.
const _unreachable = SonosDevice(
    uuid: 'U', roomName: 'Attic', modelName: '', reachable: false);

Future<CheckboxListTile> _pump(WidgetTester tester,
    {required bool selected}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BondableSpeakerTile(
        device: _unreachable,
        selected: selected,
        onChanged: (_) {},
        subtitle: 'unused',
      ),
    ),
  ));
  return tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
}

void main() {
  testWidgets('an unreachable speaker that IS bonded shows ticked',
      (tester) async {
    final tile = await _pump(tester, selected: true);
    // Drawing this unticked claimed the speaker was out of the bond, while
    // saving would have re-asserted it straight back in.
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNull, reason: 'still not editable here');
  });

  testWidgets('an unreachable speaker that is NOT bonded shows unticked',
      (tester) async {
    final tile = await _pump(tester, selected: false);
    expect(tile.value, isFalse);
    expect(tile.onChanged, isNull,
        reason: "we don't know its model, so we can't safely bond it");
  });
}
