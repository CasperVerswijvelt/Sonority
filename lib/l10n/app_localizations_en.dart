// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tabSystem => 'System';

  @override
  String get tabProfiles => 'Profiles';

  @override
  String get tabDiagnostics => 'Diagnostics';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDone => 'Done';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionRename => 'Rename';

  @override
  String get actionApply => 'Apply';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionSave => 'Save';

  @override
  String get actionClose => 'Close';

  @override
  String get actionBack => 'Back';

  @override
  String get actionNext => 'Next';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionOk => 'OK';

  @override
  String get actionAbort => 'Abort';

  @override
  String get actionAborting => 'Aborting…';

  @override
  String get actionMore => 'More';

  @override
  String get bondingCopyLogs => 'Copy logs';

  @override
  String get bondingShowSteps => 'Show steps';

  @override
  String get bondingShowRawLog => 'Show raw log';

  @override
  String get bondingLogsCopied => 'Logs copied to clipboard.';

  @override
  String get bondingNoLogOutput => 'No log output yet.';

  @override
  String get bondingSafeStateNote =>
      'It’s safe to retry — re-applying picks up where it left off and finishes the layout.';

  @override
  String get errSystemNotFound =>
      'Couldn’t find your Sonos system on the network.';

  @override
  String get errNoDevicesFound =>
      'No Sonos devices found. Check Wi-Fi and local network access.';

  @override
  String get errDescriptionsUnreadable =>
      'Found Sonos players but could not read their descriptions.';

  @override
  String get errTopologyUnreadable =>
      'Could not read the Sonos topology from any player.';

  @override
  String errEntityNotOnNetwork(String name) {
    return '“$name” isn’t on the network.';
  }

  @override
  String errCoordinatorNotOnNetwork(String name) {
    return '“$name” coordinator isn’t on the network.';
  }

  @override
  String errSpeakerInEntityNotOnNetwork(String name) {
    return 'A speaker in “$name” isn’t on the network.';
  }

  @override
  String errSubNotOnNetwork(String name) {
    return 'The Sub for “$name” isn’t on the network.';
  }

  @override
  String errSoundbarNotOnNetwork(String name) {
    return 'Soundbar for “$name” isn’t on the network.';
  }

  @override
  String errEntityMissingSpeakers(String name) {
    return '“$name” is missing speakers.';
  }

  @override
  String get errMalformedGroup => 'Stored group is malformed.';

  @override
  String get errMalformedHomeTheater => 'Stored home theater is malformed.';

  @override
  String errDidNotForm(String name) {
    return 'Sonos did not form “$name”.';
  }

  @override
  String get errDidNotCreateGroup =>
      'Sonos did not create the group — a speaker may be incompatible.';

  @override
  String get errDidNotSeparate =>
      'Sonos did not separate the group — try again.';

  @override
  String errDidNotRemove(String label) {
    return 'Sonos did not remove the $label — try again.';
  }

  @override
  String get errGroupNeedsTwo => 'A group needs at least 2 speakers.';

  @override
  String get errSpeakerIpUnknown => 'Speaker IP unknown; rescan and retry.';

  @override
  String get errSoundbarIpUnknown => 'Soundbar IP unknown; rescan and retry.';

  @override
  String get errCoordinatorIpUnknown =>
      'Coordinator IP unknown; rescan and retry.';

  @override
  String errBondingIncomplete(String channels) {
    return 'Bonding did not complete — these channels never joined: $channels. Try again, or finish in the Sonos app.';
  }

  @override
  String get errNoLanIpForChime => 'No LAN IP found to serve the chime from.';

  @override
  String get errCannotBlinkLight =>
      'Could not reach the speaker to blink its light.';

  @override
  String get errTimeout =>
      'The speaker didn’t respond in time. It may still be settling — try again in a moment.';

  @override
  String get errSonosBusy =>
      'Sonos is busy rearranging speakers right now. Wait a moment and try again.';

  @override
  String get errUnsupportedCombo =>
      'Sonos wouldn’t bond these speakers this way (unsupported combination).';

  @override
  String get errInvalidRequest => 'Sonos rejected the request as invalid.';

  @override
  String errSonosCode(String code) {
    return 'Sonos reported an error (code $code). See the raw log for details.';
  }

  @override
  String get errSonosGeneric =>
      'Sonos reported an error. See the raw log for details.';

  @override
  String get errAborted => 'Aborted';

  @override
  String get errChimeUnreachable =>
      'The speaker could not reach your phone to play the sound. Make sure your phone and speakers are on the same Wi‑Fi network. (Android emulators can’t reach speakers on your LAN — use a real device.)';

  @override
  String get entityKindHomeTheater => 'Home theater';

  @override
  String get entityKindStereoPair => 'Stereo pair';

  @override
  String get entityKindZone => 'Zone';

  @override
  String get entityKindCustom => 'Custom group';

  @override
  String get entityKindSpeaker => 'Speaker';

  @override
  String get entityKindGroup => 'Group';

  @override
  String get stepSetUpHomeTheater => 'Configure home theater';

  @override
  String get stepScanNetwork => 'Scan network for Sonos system';

  @override
  String get stepBondSpeakers => 'Bond speakers';

  @override
  String stepBondNSpeakers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bond $count speakers',
      one: 'Bond $count speaker',
    );
    return '$_temp0';
  }

  @override
  String stepBondNSpeakersWithSub(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bond $count speakers + sub',
      one: 'Bond $count speaker + sub',
    );
    return '$_temp0';
  }

  @override
  String stepRemoveUnused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remove $count speakers no longer used',
      one: 'Remove $count speaker no longer used',
    );
    return '$_temp0';
  }

  @override
  String stepUnbondN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Unbond $count speakers',
      one: 'Unbond $count speaker',
    );
    return '$_temp0';
  }

  @override
  String stepCreateGroupN(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Create group ($count speakers)',
      one: 'Create group ($count speaker)',
    );
    return '$_temp0';
  }

  @override
  String stepRemoveLabel(String label) {
    return 'Remove $label';
  }

  @override
  String get stepSpeakers => 'speakers';

  @override
  String get stepRestoreRoomName => 'Restore room name';

  @override
  String get stepRestoreSettings => 'Restore settings';

  @override
  String get stepNameGroup => 'Name the group';

  @override
  String get stepEditGroup => 'Update group';

  @override
  String get stepUpdateGroup => 'Apply changes';

  @override
  String get stepSeparateGroup => 'Separate group';

  @override
  String get stepSeparateRestore => 'Separate + restore room names';

  @override
  String get stepDetach => 'Detach from playback group';

  @override
  String get stepFreeFromBond => 'Free from its current bond';

  @override
  String get stepFreeConflicting => 'Free conflicting speakers';

  @override
  String stepFreeing(String name) {
    return 'Freeing $name';
  }

  @override
  String get stepWaitForSettle => 'Wait for Sonos to settle';

  @override
  String get stepWaitingSettle => 'waiting for Sonos to settle';

  @override
  String get stepWaitForConfirm => 'Wait for Sonos to confirm';

  @override
  String get stepWaitingConfirm => 'waiting for Sonos to confirm';

  @override
  String get stepApplyingSettle =>
      'Applying — Sonos can take up to a minute to settle.';

  @override
  String get stepNameUnchanged => 'name unchanged — nothing to do';

  @override
  String get stepAlreadyFormed => 'already formed — nothing to do';

  @override
  String get stepLayoutUnchanged => 'layout unchanged — nothing to do';

  @override
  String stepSkippedMissing(String names) {
    return 'skipped — $names not on the network';
  }

  @override
  String get stepSkippingSettingsOffline =>
      'Skipping settings — not on the network';

  @override
  String stepRestoring(String what, String type) {
    return 'Restoring $what — $type';
  }

  @override
  String get stepAudioSettings => 'audio settings';

  @override
  String get stepVolume => 'volume';

  @override
  String stepSettingsFailed(int count, String type) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count settings for $type could not be applied',
      one: '$count setting for $type could not be applied',
    );
    return '$_temp0';
  }

  @override
  String get widgetsSomethingWentWrong =>
      'Something went wrong — see the step below.';

  @override
  String get widgetsBondingTakesTime =>
      'Bonding can take ~15–20s per step while Sonos applies and re-reads the layout.';

  @override
  String get widgetsStepFailed => 'Failed.';

  @override
  String get widgetsStepWorking => 'Working…';

  @override
  String get widgetsUnreachableSpeakerHint =>
      'Couldn’t read this speaker’s details — check it’s powered on and on the same network.';

  @override
  String get widgetsUnreachable => 'Unreachable';

  @override
  String get widgetsSoundbar => 'Soundbar';

  @override
  String get widgetsFronts => 'Fronts';

  @override
  String get widgetsSurrounds => 'Surrounds';

  @override
  String get widgetsSub => 'Sub';

  @override
  String get widgetsStandaloneSpeaker => 'Standalone speaker';

  @override
  String get widgetsAmp => 'Amp';

  @override
  String get widgetsNoExtraSpeakers => 'No extra speakers';

  @override
  String widgetsNSpeakers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count speakers',
      one: '$count speaker',
    );
    return '$_temp0';
  }

  @override
  String get widgetsRoomNoLongerAvailable =>
      'This room is no longer available. Rescan to refresh.';

  @override
  String get widgetsBackToScan => 'Back to scan';

  @override
  String get widgetsSpeaker => 'Speaker';

  @override
  String get widgetsBlinkLightTooltip => 'Blink the light';

  @override
  String get widgetsChimeTooltip => 'Play a test chime';

  @override
  String widgetsBlinkingLight(String room) {
    return '💡 Blinking the light on $room…';
  }

  @override
  String widgetsPlayingChime(String room) {
    return '🔊 Playing a chime on $room…';
  }

  @override
  String widgetsNoAddressFor(String room) {
    return 'No address for $room.';
  }

  @override
  String widgetsCouldntIdentify(String room, String error) {
    return 'Couldn’t identify $room: $error';
  }

  @override
  String get widgetsRefresh => 'Refresh';

  @override
  String get widgetsRenameRoomTitle => 'Rename room';

  @override
  String get widgetsRoomNameLabel => 'Room name';

  @override
  String get widgetsTvSoundbar => 'TV / Soundbar';

  @override
  String get widgetsTrueplayChecking => 'Checking…';

  @override
  String get widgetsTrueplayNotTuned =>
      'Not tuned — run Trueplay once in the Sonos app (iOS).';

  @override
  String get widgetsTrueplayActive => 'Active';

  @override
  String get widgetsTrueplayTunedOff => 'Tuned · off';

  @override
  String widgetsTrueplayActiveCount(int enabled, int total) {
    return '$enabled/$total active';
  }

  @override
  String widgetsTrueplayTunedCount(int tuned, int total) {
    return '$tuned/$total tuned';
  }

  @override
  String get widgetsChangelog => 'Changelog';

  @override
  String profileLoadError(String error) {
    return 'Couldn’t load profiles: $error';
  }

  @override
  String get profileEdit => 'Edit';

  @override
  String get profileScanFirst => 'Scan your system first (System tab).';

  @override
  String get profileNew => 'New profile';

  @override
  String get profileReorder => 'Reorder';

  @override
  String profileDeleteConfirm(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get profileDeleteMessage =>
      'This removes the saved profile. Your speakers are not changed.';

  @override
  String profileApplying(String name) {
    return 'Applying “$name”';
  }

  @override
  String get profileEmptyTitle => 'No profiles yet';

  @override
  String get profileEmptyBody =>
      'A profile snapshots your current home theaters, stereo pairs and rooms so you can rebuild them in one tap — handy after moving speakers away. Tap “New profile” to capture your setup now.';

  @override
  String profileApplyConfirmTitle(String name) {
    return 'Apply “$name”?';
  }

  @override
  String get profileApplyConfirmBody =>
      'This re-bonds speakers on your live system and may take a while (each step waits for Sonos to settle). Trueplay may need re-tuning afterward.';

  @override
  String profileIssueMissing(String speakers) {
    return 'Missing: $speakers — will be skipped';
  }

  @override
  String profileIssueFree(String speakers) {
    return 'Will free: $speakers';
  }

  @override
  String get profileNothingApplicable =>
      'Nothing can be applied — all entities are missing speakers.';

  @override
  String profileApplySummary(int applicable, int total, int skipped) {
    return 'Will apply $applicable of $total entities; $skipped skipped.';
  }

  @override
  String get profileResnapshot => 'Re-snapshot';

  @override
  String get profileScanFirstCreate =>
      'Scan your system first (System tab), then create a profile from it.';

  @override
  String get profileReadingSettings => 'Reading settings…';

  @override
  String get profileUseSnapshot => 'Use snapshot';

  @override
  String get profileCreate => 'Create profile';

  @override
  String get profileResnapshotNote =>
      'Recapture your current setup, then review and save it on the profile screen.';

  @override
  String get profileApplyPrimer =>
      'Applying a profile later rebuilds these speakers into this layout. Any speaker that’s part of a different setup at that time is removed from it first — which can dissolve another stereo pair or zone and free its other speakers.';

  @override
  String get profileIncludeHeader => 'Include';

  @override
  String get profileIncludeHelper =>
      'Pick which of your current home theaters, pairs and rooms to capture in this profile.';

  @override
  String get profileSaveAudio => 'Save audio settings';

  @override
  String get profileSaveAudioSubtitle =>
      'EQ, night sound, speech enhancement, sub & surround levels, lip sync & more';

  @override
  String get profileSaveVolume => 'Save volume';

  @override
  String get profileSaveVolumeSubtitle =>
      'Applying the profile will change how loud each speaker plays';

  @override
  String get profileDefaultName => 'My setup';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileResnapshotTooltip => 'Re-snapshot from current setup';

  @override
  String get profileIncludedHeader => 'Included';

  @override
  String get profileRecapturedNote =>
      'Recaptured from your current setup — press Save to keep it.';

  @override
  String get profileCapturedNote => 'Captured when the profile was created.';

  @override
  String get profileResnapshotAction => 'Re-capture from current setup';

  @override
  String get profileSaved => 'Profile saved';

  @override
  String get profileNoSettingsSaved =>
      'No speaker settings saved in this profile.';

  @override
  String get profileRoleSoundbar => 'Soundbar';

  @override
  String get profileRoleFront => 'Front';

  @override
  String get profileRoleSurroundL => 'Surround L';

  @override
  String get profileRoleSurroundR => 'Surround R';

  @override
  String get profileNameLabel => 'Profile name';

  @override
  String get profileNameTaken => 'A profile with this name exists';

  @override
  String get profileNoEntities => 'No entities';

  @override
  String get profileBadgeAudio => 'Audio settings';

  @override
  String get profileBadgeVolume => 'Volume';

  @override
  String profileUpdatedAgo(String time) {
    return 'Updated $time';
  }

  @override
  String get profileChipLayoutNames => 'Layout + names';

  @override
  String get profileChipSettings => 'Settings';

  @override
  String get profileChipNoSettings => 'No settings';

  @override
  String get profileChipNoVolume => 'No volume';

  @override
  String get profileTimeJustNow => 'just now';

  @override
  String profileTimeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String profileTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String profileTimeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String profileTimeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weeks ago',
      one: '1 week ago',
    );
    return '$_temp0';
  }

  @override
  String profileTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months ago',
      one: '1 month ago',
    );
    return '$_temp0';
  }

  @override
  String profileTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years ago',
      one: '1 year ago',
    );
    return '$_temp0';
  }

  @override
  String get profileAppearance => 'Appearance';

  @override
  String get profileWidgetPickTitle => 'Pick profiles';

  @override
  String get profileWidgetEmpty =>
      'No profiles yet — create one in Sonority first.';

  @override
  String get profileWidgetPickHelper =>
      'Pick the profiles to show. Reorder them in the Profiles tab.';

  @override
  String get profileWidgetSelectAtLeastOne => 'Select at least one';

  @override
  String profileWidgetAddCount(int count) {
    return 'Add $count to widget';
  }

  @override
  String get discoveryDiagnostics => 'Diagnostics';

  @override
  String get discoveryRescan => 'Rescan';

  @override
  String get discoveryHomeTheaters => 'Home theaters';

  @override
  String get discoveryNoSoundbar =>
      'No soundbar found. Dedicated fronts need an Arc, Beam, Ray, Playbar or Playbase.';

  @override
  String get discoverySpeakerGroups => 'Speaker groups';

  @override
  String get discoveryGroupSpeakers => 'Group speakers';

  @override
  String get discoveryNoGroups => 'No speaker groups yet';

  @override
  String get discoverySingleRooms => 'Single speaker rooms';

  @override
  String get discoveryOtherDevices => 'Other devices';

  @override
  String get discoverySubwoofer => 'Subwoofer';

  @override
  String get discoverySubUnbondedNote =>
      'This Sub isn’t bonded to anything yet. Add it to a home theater (Configure home theater) or a speaker group to use it.';

  @override
  String get discoveryScanning => 'Scanning your network…';

  @override
  String get discoveryErrorTitle => 'Couldn’t find your system';

  @override
  String get discoveryTryAgain => 'Try again';

  @override
  String get roomTitle => 'Room';

  @override
  String get roomRenameTooltip => 'Rename room';

  @override
  String roomRenamedTo(String name) {
    return 'Renamed to “$name”.';
  }

  @override
  String roomRenameFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get roomGroupWith => 'Group with another speaker';

  @override
  String get roomGroupWithSubtitle =>
      'Stereo pair, full-range zone, or custom L/R';

  @override
  String get roomAddToHomeTheater => 'Add to a home theater';

  @override
  String get roomAddToHomeTheaterSubtitle => 'As a front, surround, or sub';

  @override
  String get roomAddToWhichHomeTheater => 'Add to which home theater?';

  @override
  String get sectionSpeakers => 'Speakers';

  @override
  String get groupSheetTitle => 'Speaker group';

  @override
  String get groupUpdating => 'Updating…';

  @override
  String get groupRenameTooltip => 'Rename group';

  @override
  String get groupSeparate => 'Separate';

  @override
  String groupRenamedTo(String name) {
    return 'Renamed to “$name”.';
  }

  @override
  String groupRenameFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get groupSeparateConfirmTitle => 'Separate group?';

  @override
  String get groupSeparateConfirmMessage =>
      'The speakers become standalone rooms again. Their original room names will be restored.';

  @override
  String get groupSeparateProgressTitle => 'Separate group';

  @override
  String get groupFlowTitle => 'Group speakers';

  @override
  String get groupEditTitle => 'Configure group';

  @override
  String get groupConfigure => 'Configure';

  @override
  String get groupSaveChanges => 'Save changes';

  @override
  String get groupNeedTwoSpeakers =>
      'Need at least two standalone speakers (not soundbars, subs, amps, or already bonded).';

  @override
  String get groupModeStereo => 'Stereo';

  @override
  String get groupModeZone => 'Zone';

  @override
  String get groupModeCustom => 'Custom';

  @override
  String get groupStepSelect => 'Select speakers';

  @override
  String get groupStepAddSub => 'Add a Sub';

  @override
  String get groupOptional => 'Optional';

  @override
  String get groupStepName => 'Name';

  @override
  String get groupNameLabel => 'Group name (optional)';

  @override
  String get groupNameHint => 'e.g. Downstairs';

  @override
  String get groupStepReview => 'Review & create';

  @override
  String get groupCreateStereo => 'Create stereo pair';

  @override
  String get groupCreateZone => 'Create zone';

  @override
  String get groupCreateCustom => 'Create custom group';

  @override
  String get groupCreateFailed =>
      'Couldn’t create the group — Sonos may not allow one of these speakers. See the log for details.';

  @override
  String get groupHintStereo =>
      'Pick two speakers — one plays left, the other right (swap below). Mismatched models are fine.';

  @override
  String get groupHintZone =>
      'Pick 2–16 speakers. They all play full stereo (L+R) as one room.';

  @override
  String get groupHintCustom =>
      'Pick 2–16 speakers and set each to Left, Right, or Both.';

  @override
  String get groupChannelLeft => 'Left';

  @override
  String get groupChannelBoth => 'Both';

  @override
  String get groupChannelRight => 'Right';

  @override
  String get groupNoSub =>
      'No standalone Sub available. A Sub bonded to a home theater must be removed there first.';

  @override
  String get groupAddSubHint => 'Optionally add a Sub to the group.';

  @override
  String get groupSubwoofer => 'Subwoofer';

  @override
  String get groupKindStereo => 'Stereo pair';

  @override
  String groupKindZone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zone ($count speakers)',
      one: 'Zone ($count speaker)',
    );
    return '$_temp0';
  }

  @override
  String groupKindCustom(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Custom group ($count speakers)',
      one: 'Custom group ($count speaker)',
    );
    return '$_temp0';
  }

  @override
  String groupReviewMemberLine(String room, String channel) {
    return '$room — $channel';
  }

  @override
  String groupReviewName(String name) {
    return 'Name: $name';
  }

  @override
  String groupReviewSub(String type) {
    return 'Sub: $type';
  }

  @override
  String get groupReviewNote =>
      'Bonded speakers play as one room. Larger or mixed-model groups can drop out briefly — play something to confirm it works for you. Original room names are restored when you separate the group.';

  @override
  String get htHomeTheater => 'Home theater';

  @override
  String get htRenameRoomTooltip => 'Rename room';

  @override
  String get htUpdatingTitle => 'Updating your home theater…';

  @override
  String get htUpdatingSubtitle =>
      'This can take up to ~20 seconds while Sonos reconfigures and re-reads the layout.';

  @override
  String htRenamedTo(String name) {
    return 'Renamed to “$name”.';
  }

  @override
  String htRenameFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get htSeparateConfirmTitle => 'Separate home theater?';

  @override
  String htRemoveConfirmTitle(String label) {
    return 'Remove $label?';
  }

  @override
  String get htSeparateMessage =>
      'All extra speakers will be un-bonded and become standalone rooms again, leaving just the soundbar.';

  @override
  String get htRemoveMessage =>
      'These speakers will be un-bonded and become standalone rooms again. The rest of your home theater stays as it is.';

  @override
  String get htSeparate => 'Separate';

  @override
  String get htSeparateProgressTitle => 'Separate home theater';

  @override
  String htRemoveProgressTitle(String label) {
    return 'Remove $label';
  }

  @override
  String get htGroupFronts => 'Fronts';

  @override
  String get htGroupSurrounds => 'Surrounds';

  @override
  String get htGroupSubwoofer => 'Subwoofer';

  @override
  String get htConfigure => 'Configure';

  @override
  String get htBondedSpeakers => 'Bonded speakers';

  @override
  String get htNoBonded =>
      'Just the soundbar — no fronts, surrounds or sub bonded yet. Tap “Configure” to add some.';

  @override
  String get htSpeakerFallback => 'Speaker';

  @override
  String get htTrueplayNote =>
      'Trueplay can only be measured from the Sonos app on iOS — tune the home theater, and the fronts separately as a stereo pair. Heads-up: Sonos often clears a tuning when speakers are bonded/unbonded, so you may see “Not tuned” after changing the layout and have to redo it. Sonority only toggles a stored tuning.';

  @override
  String get htAllExtraSpeakers => 'all extra speakers';

  @override
  String get htBonded => 'Bonded';

  @override
  String get frontSurroundsTitle => 'Configure home theater';

  @override
  String get frontSurroundsStepFronts => 'Front speakers';

  @override
  String get frontSurroundsOptional => 'Optional';

  @override
  String get frontSurroundsFrontsHint =>
      'Pick two speakers (or a single Amp) for the front left & right, then set which is which.';

  @override
  String get frontSurroundsStepSurrounds => 'Rear surrounds';

  @override
  String get frontSurroundsSurroundsHint =>
      'Pick two speakers for the rear left & right surrounds.';

  @override
  String get frontSurroundsStepSub => 'Subwoofer';

  @override
  String get frontSurroundsStepReview => 'Review & apply';

  @override
  String frontSurroundsUnbondTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Unbond $count speakers?',
      one: 'Unbond $count speaker?',
    );
    return '$_temp0';
  }

  @override
  String frontSurroundsUnbondMessage(String types) {
    return '$types will be removed from this home theater and become standalone rooms again. The rest of your layout stays as it is.';
  }

  @override
  String get frontSurroundsUnbond => 'Unbond';

  @override
  String get frontSurroundsNoFreeSpeakers =>
      'No free speakers available. They must be standalone (not already part of a home theater or stereo pair).';

  @override
  String get frontSurroundsPickWithAmp =>
      'Pick two speakers (ideally identical), or a single Sonos Amp that drives both front speakers.';

  @override
  String get frontSurroundsPickExactlyTwo =>
      'Pick exactly two — ideally an identical pair.';

  @override
  String frontSurroundsAmpSubtitle(String type) {
    return '$type — drives both fronts (L + R)';
  }

  @override
  String get frontSurroundsNoFreeSub =>
      'No free subwoofer found. A Sonos Sub must be standalone (not already bonded to another home theater).';

  @override
  String get frontSurroundsSubHint =>
      'Pick one or two subwoofers to add as low-frequency channels.';

  @override
  String frontSurroundsAmpWiring(String amp) {
    return 'The $amp drives both front channels. Wire your left & right speakers to its L/R speaker outputs — there’s nothing to assign here.';
  }

  @override
  String get frontSurroundsChooseTwoFirst => 'Choose two speakers first.';

  @override
  String get frontSurroundsTapSwap => 'Tap swap if the sides are reversed.';

  @override
  String get frontSurroundsNothingSelected =>
      'Nothing selected yet — choose speakers above.';

  @override
  String get frontSurroundsReviewNote =>
      'The chosen speakers become hidden satellites of the soundbar (which stays the center channel). Bonding runs in steps and can take a little while; Trueplay may need re-tuning afterward. You can change this anytime.';

  @override
  String get diagNoSystemToCollect => 'No system to collect — scan first.';

  @override
  String diagBuildFailed(String error) {
    return 'Could not build the diagnostics bundle: $error';
  }

  @override
  String diagActionFailed(String error) {
    return 'Could not complete the action: $error';
  }

  @override
  String diagSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get diagTitle => 'Diagnostics';

  @override
  String get diagNoSystem => 'No system discovered yet.';

  @override
  String get diagIncludeLogs => 'Include app logs';

  @override
  String get diagIncludeLogsSubtitle =>
      'SOAP faults, bond retries, discovery, errors (logs.txt)';

  @override
  String get diagIncludeNetwork => 'Include phone network info';

  @override
  String get diagIncludeNetworkSubtitle =>
      'This device’s network interface addresses (network.txt)';

  @override
  String get diagAlwaysIncluded =>
      'Always included: topology (room names, IPs, MACs, models), raw device descriptions, and your saved profiles/room names.';

  @override
  String get diagCollecting => 'Collecting…';

  @override
  String get diagEmailToDeveloper => 'Email to developer';

  @override
  String get diagShareDiagnostics => 'Share diagnostics';

  @override
  String get diagEmailBody =>
      'Describe what went wrong (what you tried, what you expected, what happened):\n\n\n——— the diagnostics bundle is attached below ———';
}
