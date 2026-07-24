import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @tabSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get tabSystem;

  /// No description provided for @tabProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get tabProfiles;

  /// No description provided for @tabDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get tabDiagnostics;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get actionRename;

  /// No description provided for @actionApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get actionApply;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get actionNext;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get actionOk;

  /// No description provided for @actionAbort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get actionAbort;

  /// No description provided for @actionAborting.
  ///
  /// In en, this message translates to:
  /// **'Aborting…'**
  String get actionAborting;

  /// No description provided for @actionMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get actionMore;

  /// No description provided for @bondingCopyLogs.
  ///
  /// In en, this message translates to:
  /// **'Copy logs'**
  String get bondingCopyLogs;

  /// No description provided for @bondingShowSteps.
  ///
  /// In en, this message translates to:
  /// **'Show steps'**
  String get bondingShowSteps;

  /// No description provided for @bondingShowRawLog.
  ///
  /// In en, this message translates to:
  /// **'Show raw log'**
  String get bondingShowRawLog;

  /// No description provided for @bondingLogsCopied.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard.'**
  String get bondingLogsCopied;

  /// No description provided for @bondingNoLogOutput.
  ///
  /// In en, this message translates to:
  /// **'No log output yet.'**
  String get bondingNoLogOutput;

  /// No description provided for @bondingSafeStateNote.
  ///
  /// In en, this message translates to:
  /// **'It’s safe to retry — re-applying picks up where it left off and finishes the layout.'**
  String get bondingSafeStateNote;

  /// No description provided for @errSystemNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t find your Sonos system on the network.'**
  String get errSystemNotFound;

  /// No description provided for @errNoDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No Sonos devices found. Check Wi-Fi and local network access.'**
  String get errNoDevicesFound;

  /// No description provided for @errDescriptionsUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Found Sonos players but could not read their descriptions.'**
  String get errDescriptionsUnreadable;

  /// No description provided for @errTopologyUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the Sonos topology from any player.'**
  String get errTopologyUnreadable;

  /// No description provided for @errEntityNotOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'“{name}” isn’t on the network.'**
  String errEntityNotOnNetwork(String name);

  /// No description provided for @errCoordinatorNotOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'“{name}” coordinator isn’t on the network.'**
  String errCoordinatorNotOnNetwork(String name);

  /// No description provided for @errSpeakerInEntityNotOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'A speaker in “{name}” isn’t on the network.'**
  String errSpeakerInEntityNotOnNetwork(String name);

  /// No description provided for @errSubNotOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'The Sub for “{name}” isn’t on the network.'**
  String errSubNotOnNetwork(String name);

  /// No description provided for @errSoundbarNotOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'Soundbar for “{name}” isn’t on the network.'**
  String errSoundbarNotOnNetwork(String name);

  /// No description provided for @errEntityMissingSpeakers.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is missing speakers.'**
  String errEntityMissingSpeakers(String name);

  /// No description provided for @errMalformedGroup.
  ///
  /// In en, this message translates to:
  /// **'Stored group is malformed.'**
  String get errMalformedGroup;

  /// No description provided for @errMalformedHomeTheater.
  ///
  /// In en, this message translates to:
  /// **'Stored home theater is malformed.'**
  String get errMalformedHomeTheater;

  /// No description provided for @errDidNotForm.
  ///
  /// In en, this message translates to:
  /// **'Sonos did not form “{name}”.'**
  String errDidNotForm(String name);

  /// No description provided for @errDidNotCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'Sonos did not create the group — a speaker may be incompatible.'**
  String get errDidNotCreateGroup;

  /// No description provided for @errDidNotSeparate.
  ///
  /// In en, this message translates to:
  /// **'Sonos did not separate the group — try again.'**
  String get errDidNotSeparate;

  /// No description provided for @errDidNotRemove.
  ///
  /// In en, this message translates to:
  /// **'Sonos did not remove the {label} — try again.'**
  String errDidNotRemove(String label);

  /// No description provided for @errGroupNeedsTwo.
  ///
  /// In en, this message translates to:
  /// **'A group needs at least 2 speakers.'**
  String get errGroupNeedsTwo;

  /// No description provided for @errSpeakerIpUnknown.
  ///
  /// In en, this message translates to:
  /// **'Speaker IP unknown; rescan and retry.'**
  String get errSpeakerIpUnknown;

  /// No description provided for @errSoundbarIpUnknown.
  ///
  /// In en, this message translates to:
  /// **'Soundbar IP unknown; rescan and retry.'**
  String get errSoundbarIpUnknown;

  /// No description provided for @errCoordinatorIpUnknown.
  ///
  /// In en, this message translates to:
  /// **'Coordinator IP unknown; rescan and retry.'**
  String get errCoordinatorIpUnknown;

  /// No description provided for @errBondingIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Bonding did not complete — these channels never joined: {channels}. Try again, or finish in the Sonos app.'**
  String errBondingIncomplete(String channels);

  /// No description provided for @errNoLanIpForChime.
  ///
  /// In en, this message translates to:
  /// **'No LAN IP found to serve the chime from.'**
  String get errNoLanIpForChime;

  /// No description provided for @errCannotBlinkLight.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the speaker to blink its light.'**
  String get errCannotBlinkLight;

  /// No description provided for @errTimeout.
  ///
  /// In en, this message translates to:
  /// **'The speaker didn’t respond in time. It may still be settling — try again in a moment.'**
  String get errTimeout;

  /// No description provided for @errSonosBusy.
  ///
  /// In en, this message translates to:
  /// **'Sonos is busy rearranging speakers right now. Wait a moment and try again.'**
  String get errSonosBusy;

  /// No description provided for @errUnsupportedCombo.
  ///
  /// In en, this message translates to:
  /// **'Sonos wouldn’t bond these speakers this way (unsupported combination).'**
  String get errUnsupportedCombo;

  /// No description provided for @errInvalidRequest.
  ///
  /// In en, this message translates to:
  /// **'Sonos rejected the request as invalid.'**
  String get errInvalidRequest;

  /// No description provided for @errSonosCode.
  ///
  /// In en, this message translates to:
  /// **'Sonos reported an error (code {code}). See the raw log for details.'**
  String errSonosCode(String code);

  /// No description provided for @errSonosGeneric.
  ///
  /// In en, this message translates to:
  /// **'Sonos reported an error. See the raw log for details.'**
  String get errSonosGeneric;

  /// No description provided for @errAborted.
  ///
  /// In en, this message translates to:
  /// **'Aborted'**
  String get errAborted;

  /// No description provided for @errChimeUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The speaker could not reach your phone to play the sound. Make sure your phone and speakers are on the same Wi‑Fi network. (Android emulators can’t reach speakers on your LAN — use a real device.)'**
  String get errChimeUnreachable;

  /// No description provided for @entityKindHomeTheater.
  ///
  /// In en, this message translates to:
  /// **'Home theater'**
  String get entityKindHomeTheater;

  /// No description provided for @entityKindStereoPair.
  ///
  /// In en, this message translates to:
  /// **'Stereo pair'**
  String get entityKindStereoPair;

  /// No description provided for @entityKindZone.
  ///
  /// In en, this message translates to:
  /// **'Zone'**
  String get entityKindZone;

  /// No description provided for @entityKindCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom group'**
  String get entityKindCustom;

  /// No description provided for @entityKindSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get entityKindSpeaker;

  /// No description provided for @entityKindGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get entityKindGroup;

  /// No description provided for @stepSetUpHomeTheater.
  ///
  /// In en, this message translates to:
  /// **'Configure home theater'**
  String get stepSetUpHomeTheater;

  /// No description provided for @stepScanNetwork.
  ///
  /// In en, this message translates to:
  /// **'Scan network for Sonos system'**
  String get stepScanNetwork;

  /// No description provided for @stepBondSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Bond speakers'**
  String get stepBondSpeakers;

  /// No description provided for @stepBondNSpeakers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Bond {count} speaker} other{Bond {count} speakers}}'**
  String stepBondNSpeakers(int count);

  /// No description provided for @stepBondNSpeakersWithSub.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Bond {count} speaker + sub} other{Bond {count} speakers + sub}}'**
  String stepBondNSpeakersWithSub(int count);

  /// No description provided for @stepRemoveUnused.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Remove {count} speaker no longer used} other{Remove {count} speakers no longer used}}'**
  String stepRemoveUnused(int count);

  /// No description provided for @stepUnbondN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Unbond {count} speaker} other{Unbond {count} speakers}}'**
  String stepUnbondN(int count);

  /// No description provided for @stepCreateGroupN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Create group ({count} speaker)} other{Create group ({count} speakers)}}'**
  String stepCreateGroupN(int count);

  /// No description provided for @stepRemoveLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove {label}'**
  String stepRemoveLabel(String label);

  /// No description provided for @stepSpeakers.
  ///
  /// In en, this message translates to:
  /// **'speakers'**
  String get stepSpeakers;

  /// No description provided for @stepRestoreRoomName.
  ///
  /// In en, this message translates to:
  /// **'Restore room name'**
  String get stepRestoreRoomName;

  /// No description provided for @stepRestoreSettings.
  ///
  /// In en, this message translates to:
  /// **'Restore settings'**
  String get stepRestoreSettings;

  /// No description provided for @stepNameGroup.
  ///
  /// In en, this message translates to:
  /// **'Name the group'**
  String get stepNameGroup;

  /// No description provided for @stepEditGroup.
  ///
  /// In en, this message translates to:
  /// **'Update group'**
  String get stepEditGroup;

  /// No description provided for @stepUpdateGroup.
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get stepUpdateGroup;

  /// No description provided for @stepSeparateGroup.
  ///
  /// In en, this message translates to:
  /// **'Separate group'**
  String get stepSeparateGroup;

  /// No description provided for @stepSeparateRestore.
  ///
  /// In en, this message translates to:
  /// **'Separate + restore room names'**
  String get stepSeparateRestore;

  /// No description provided for @stepDetach.
  ///
  /// In en, this message translates to:
  /// **'Detach from playback group'**
  String get stepDetach;

  /// No description provided for @stepFreeFromBond.
  ///
  /// In en, this message translates to:
  /// **'Free from its current bond'**
  String get stepFreeFromBond;

  /// No description provided for @stepFreeConflicting.
  ///
  /// In en, this message translates to:
  /// **'Free conflicting speakers'**
  String get stepFreeConflicting;

  /// No description provided for @stepFreeing.
  ///
  /// In en, this message translates to:
  /// **'Freeing {name}'**
  String stepFreeing(String name);

  /// No description provided for @stepWaitForSettle.
  ///
  /// In en, this message translates to:
  /// **'Wait for Sonos to settle'**
  String get stepWaitForSettle;

  /// No description provided for @stepWaitingSettle.
  ///
  /// In en, this message translates to:
  /// **'waiting for Sonos to settle'**
  String get stepWaitingSettle;

  /// No description provided for @stepWaitForConfirm.
  ///
  /// In en, this message translates to:
  /// **'Wait for Sonos to confirm'**
  String get stepWaitForConfirm;

  /// No description provided for @stepWaitingConfirm.
  ///
  /// In en, this message translates to:
  /// **'waiting for Sonos to confirm'**
  String get stepWaitingConfirm;

  /// No description provided for @stepApplyingSettle.
  ///
  /// In en, this message translates to:
  /// **'Applying — Sonos can take up to a minute to settle.'**
  String get stepApplyingSettle;

  /// No description provided for @stepNameUnchanged.
  ///
  /// In en, this message translates to:
  /// **'name unchanged — nothing to do'**
  String get stepNameUnchanged;

  /// No description provided for @stepAlreadyFormed.
  ///
  /// In en, this message translates to:
  /// **'already formed — nothing to do'**
  String get stepAlreadyFormed;

  /// No description provided for @stepLayoutUnchanged.
  ///
  /// In en, this message translates to:
  /// **'layout unchanged — nothing to do'**
  String get stepLayoutUnchanged;

  /// No description provided for @stepSkippedMissing.
  ///
  /// In en, this message translates to:
  /// **'skipped — {names} not on the network'**
  String stepSkippedMissing(String names);

  /// No description provided for @stepSkippingSettingsOffline.
  ///
  /// In en, this message translates to:
  /// **'Skipping settings — not on the network'**
  String get stepSkippingSettingsOffline;

  /// No description provided for @stepRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring {what} — {type}'**
  String stepRestoring(String what, String type);

  /// No description provided for @stepAudioSettings.
  ///
  /// In en, this message translates to:
  /// **'audio settings'**
  String get stepAudioSettings;

  /// No description provided for @stepVolume.
  ///
  /// In en, this message translates to:
  /// **'volume'**
  String get stepVolume;

  /// No description provided for @stepSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} setting for {type} could not be applied} other{{count} settings for {type} could not be applied}}'**
  String stepSettingsFailed(int count, String type);

  /// No description provided for @widgetsSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong — see the step below.'**
  String get widgetsSomethingWentWrong;

  /// No description provided for @widgetsBondingTakesTime.
  ///
  /// In en, this message translates to:
  /// **'Bonding can take ~15–20s per step while Sonos applies and re-reads the layout.'**
  String get widgetsBondingTakesTime;

  /// No description provided for @widgetsStepFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed.'**
  String get widgetsStepFailed;

  /// No description provided for @widgetsStepWorking.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get widgetsStepWorking;

  /// No description provided for @widgetsUnreachableSpeakerHint.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t read this speaker’s details — check it’s powered on and on the same network.'**
  String get widgetsUnreachableSpeakerHint;

  /// No description provided for @widgetsUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get widgetsUnreachable;

  /// No description provided for @widgetsSoundbar.
  ///
  /// In en, this message translates to:
  /// **'Soundbar'**
  String get widgetsSoundbar;

  /// No description provided for @widgetsFronts.
  ///
  /// In en, this message translates to:
  /// **'Fronts'**
  String get widgetsFronts;

  /// No description provided for @widgetsSurrounds.
  ///
  /// In en, this message translates to:
  /// **'Surrounds'**
  String get widgetsSurrounds;

  /// No description provided for @widgetsSub.
  ///
  /// In en, this message translates to:
  /// **'Sub'**
  String get widgetsSub;

  /// No description provided for @widgetsStandaloneSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Standalone speaker'**
  String get widgetsStandaloneSpeaker;

  /// No description provided for @widgetsAmp.
  ///
  /// In en, this message translates to:
  /// **'Amp'**
  String get widgetsAmp;

  /// No description provided for @widgetsNoExtraSpeakers.
  ///
  /// In en, this message translates to:
  /// **'No extra speakers'**
  String get widgetsNoExtraSpeakers;

  /// No description provided for @widgetsNSpeakers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} speaker} other{{count} speakers}}'**
  String widgetsNSpeakers(int count);

  /// No description provided for @widgetsRoomNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'This room is no longer available. Rescan to refresh.'**
  String get widgetsRoomNoLongerAvailable;

  /// No description provided for @widgetsBackToScan.
  ///
  /// In en, this message translates to:
  /// **'Back to scan'**
  String get widgetsBackToScan;

  /// No description provided for @widgetsSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get widgetsSpeaker;

  /// No description provided for @widgetsBlinkLightTooltip.
  ///
  /// In en, this message translates to:
  /// **'Blink the light'**
  String get widgetsBlinkLightTooltip;

  /// No description provided for @widgetsChimeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Play a test chime'**
  String get widgetsChimeTooltip;

  /// No description provided for @widgetsBlinkingLight.
  ///
  /// In en, this message translates to:
  /// **'💡 Blinking the light on {room}…'**
  String widgetsBlinkingLight(String room);

  /// No description provided for @widgetsPlayingChime.
  ///
  /// In en, this message translates to:
  /// **'🔊 Playing a chime on {room}…'**
  String widgetsPlayingChime(String room);

  /// No description provided for @widgetsNoAddressFor.
  ///
  /// In en, this message translates to:
  /// **'No address for {room}.'**
  String widgetsNoAddressFor(String room);

  /// No description provided for @widgetsCouldntIdentify.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t identify {room}: {error}'**
  String widgetsCouldntIdentify(String room, String error);

  /// No description provided for @widgetsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get widgetsRefresh;

  /// No description provided for @widgetsRenameRoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename room'**
  String get widgetsRenameRoomTitle;

  /// No description provided for @widgetsRoomNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Room name'**
  String get widgetsRoomNameLabel;

  /// No description provided for @widgetsTvSoundbar.
  ///
  /// In en, this message translates to:
  /// **'TV / Soundbar'**
  String get widgetsTvSoundbar;

  /// No description provided for @widgetsTrueplayChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get widgetsTrueplayChecking;

  /// No description provided for @widgetsTrueplayNotTuned.
  ///
  /// In en, this message translates to:
  /// **'Not tuned — run Trueplay once in the Sonos app (iOS).'**
  String get widgetsTrueplayNotTuned;

  /// No description provided for @widgetsTrueplayActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get widgetsTrueplayActive;

  /// No description provided for @widgetsTrueplayTunedOff.
  ///
  /// In en, this message translates to:
  /// **'Tuned · off'**
  String get widgetsTrueplayTunedOff;

  /// No description provided for @widgetsTrueplayActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{enabled}/{total} active'**
  String widgetsTrueplayActiveCount(int enabled, int total);

  /// No description provided for @widgetsTrueplayTunedCount.
  ///
  /// In en, this message translates to:
  /// **'{tuned}/{total} tuned'**
  String widgetsTrueplayTunedCount(int tuned, int total);

  /// No description provided for @widgetsChangelog.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get widgetsChangelog;

  /// No description provided for @profileLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load profiles: {error}'**
  String profileLoadError(String error);

  /// No description provided for @profileEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get profileEdit;

  /// No description provided for @profileScanFirst.
  ///
  /// In en, this message translates to:
  /// **'Scan your system first (System tab).'**
  String get profileScanFirst;

  /// No description provided for @profileNew.
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get profileNew;

  /// No description provided for @profileReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get profileReorder;

  /// No description provided for @profileDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String profileDeleteConfirm(String name);

  /// No description provided for @profileDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes the saved profile. Your speakers are not changed.'**
  String get profileDeleteMessage;

  /// No description provided for @profileApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying “{name}”'**
  String profileApplying(String name);

  /// No description provided for @profileEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No profiles yet'**
  String get profileEmptyTitle;

  /// No description provided for @profileEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'A profile snapshots your current home theaters, stereo pairs and rooms so you can rebuild them in one tap — handy after moving speakers away. Tap “New profile” to capture your setup now.'**
  String get profileEmptyBody;

  /// No description provided for @profileApplyConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply “{name}”?'**
  String profileApplyConfirmTitle(String name);

  /// No description provided for @profileApplyConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This re-bonds speakers on your live system and may take a while (each step waits for Sonos to settle). Trueplay may need re-tuning afterward.'**
  String get profileApplyConfirmBody;

  /// No description provided for @profileIssueMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing: {speakers} — will be skipped'**
  String profileIssueMissing(String speakers);

  /// No description provided for @profileIssueFree.
  ///
  /// In en, this message translates to:
  /// **'Will free: {speakers}'**
  String profileIssueFree(String speakers);

  /// No description provided for @profileNothingApplicable.
  ///
  /// In en, this message translates to:
  /// **'Nothing can be applied — all entities are missing speakers.'**
  String get profileNothingApplicable;

  /// No description provided for @profileApplySummary.
  ///
  /// In en, this message translates to:
  /// **'Will apply {applicable} of {total} entities; {skipped} skipped.'**
  String profileApplySummary(int applicable, int total, int skipped);

  /// No description provided for @profileResnapshot.
  ///
  /// In en, this message translates to:
  /// **'Re-snapshot'**
  String get profileResnapshot;

  /// No description provided for @profileScanFirstCreate.
  ///
  /// In en, this message translates to:
  /// **'Scan your system first (System tab), then create a profile from it.'**
  String get profileScanFirstCreate;

  /// No description provided for @profileReadingSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading settings…'**
  String get profileReadingSettings;

  /// No description provided for @profileUseSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Use snapshot'**
  String get profileUseSnapshot;

  /// No description provided for @profileCreate.
  ///
  /// In en, this message translates to:
  /// **'Create profile'**
  String get profileCreate;

  /// No description provided for @profileResnapshotNote.
  ///
  /// In en, this message translates to:
  /// **'Recapture your current setup, then review and save it on the profile screen.'**
  String get profileResnapshotNote;

  /// No description provided for @profileApplyPrimer.
  ///
  /// In en, this message translates to:
  /// **'Applying a profile later rebuilds these speakers into this layout. Any speaker that’s part of a different setup at that time is removed from it first — which can dissolve another stereo pair or zone and free its other speakers.'**
  String get profileApplyPrimer;

  /// No description provided for @profileIncludeHeader.
  ///
  /// In en, this message translates to:
  /// **'Include'**
  String get profileIncludeHeader;

  /// No description provided for @profileIncludeHelper.
  ///
  /// In en, this message translates to:
  /// **'Pick which of your current home theaters, pairs and rooms to capture in this profile.'**
  String get profileIncludeHelper;

  /// No description provided for @profileSaveAudio.
  ///
  /// In en, this message translates to:
  /// **'Save audio settings'**
  String get profileSaveAudio;

  /// No description provided for @profileSaveAudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'EQ, night sound, speech enhancement, sub & surround levels, lip sync & more'**
  String get profileSaveAudioSubtitle;

  /// No description provided for @profileSaveVolume.
  ///
  /// In en, this message translates to:
  /// **'Save volume'**
  String get profileSaveVolume;

  /// No description provided for @profileSaveVolumeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Applying the profile will change how loud each speaker plays'**
  String get profileSaveVolumeSubtitle;

  /// No description provided for @profileDefaultName.
  ///
  /// In en, this message translates to:
  /// **'My setup'**
  String get profileDefaultName;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileResnapshotTooltip.
  ///
  /// In en, this message translates to:
  /// **'Re-snapshot from current setup'**
  String get profileResnapshotTooltip;

  /// No description provided for @profileIncludedHeader.
  ///
  /// In en, this message translates to:
  /// **'Included'**
  String get profileIncludedHeader;

  /// No description provided for @profileRecapturedNote.
  ///
  /// In en, this message translates to:
  /// **'Recaptured from your current setup — press Save to keep it.'**
  String get profileRecapturedNote;

  /// No description provided for @profileCapturedNote.
  ///
  /// In en, this message translates to:
  /// **'Captured when the profile was created.'**
  String get profileCapturedNote;

  /// No description provided for @profileResnapshotAction.
  ///
  /// In en, this message translates to:
  /// **'Re-capture from current setup'**
  String get profileResnapshotAction;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSaved;

  /// No description provided for @profileNoSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'No speaker settings saved in this profile.'**
  String get profileNoSettingsSaved;

  /// No description provided for @profileRoleSoundbar.
  ///
  /// In en, this message translates to:
  /// **'Soundbar'**
  String get profileRoleSoundbar;

  /// No description provided for @profileRoleFront.
  ///
  /// In en, this message translates to:
  /// **'Front'**
  String get profileRoleFront;

  /// No description provided for @profileRoleSurroundL.
  ///
  /// In en, this message translates to:
  /// **'Surround L'**
  String get profileRoleSurroundL;

  /// No description provided for @profileRoleSurroundR.
  ///
  /// In en, this message translates to:
  /// **'Surround R'**
  String get profileRoleSurroundR;

  /// No description provided for @settingBass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get settingBass;

  /// No description provided for @settingTreble.
  ///
  /// In en, this message translates to:
  /// **'Treble'**
  String get settingTreble;

  /// No description provided for @settingLoudness.
  ///
  /// In en, this message translates to:
  /// **'Loudness'**
  String get settingLoudness;

  /// No description provided for @settingVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get settingVolume;

  /// No description provided for @settingMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get settingMuted;

  /// No description provided for @settingNightMode.
  ///
  /// In en, this message translates to:
  /// **'Night sound'**
  String get settingNightMode;

  /// No description provided for @settingDialogLevel.
  ///
  /// In en, this message translates to:
  /// **'Speech enhancement'**
  String get settingDialogLevel;

  /// No description provided for @settingSubGain.
  ///
  /// In en, this message translates to:
  /// **'Sub level'**
  String get settingSubGain;

  /// No description provided for @settingSubEnable.
  ///
  /// In en, this message translates to:
  /// **'Sub'**
  String get settingSubEnable;

  /// No description provided for @settingSubPolarity.
  ///
  /// In en, this message translates to:
  /// **'Sub phase'**
  String get settingSubPolarity;

  /// No description provided for @settingSubCrossover.
  ///
  /// In en, this message translates to:
  /// **'Sub crossover'**
  String get settingSubCrossover;

  /// No description provided for @settingSurroundLevel.
  ///
  /// In en, this message translates to:
  /// **'Surround level (TV)'**
  String get settingSurroundLevel;

  /// No description provided for @settingSurroundEnable.
  ///
  /// In en, this message translates to:
  /// **'Surround'**
  String get settingSurroundEnable;

  /// No description provided for @settingSurroundMode.
  ///
  /// In en, this message translates to:
  /// **'Surround mode'**
  String get settingSurroundMode;

  /// No description provided for @settingMusicSurroundLevel.
  ///
  /// In en, this message translates to:
  /// **'Surround level (music)'**
  String get settingMusicSurroundLevel;

  /// No description provided for @settingAudioDelay.
  ///
  /// In en, this message translates to:
  /// **'Audio delay (lip sync)'**
  String get settingAudioDelay;

  /// No description provided for @settingAudioDelayLeftRear.
  ///
  /// In en, this message translates to:
  /// **'Surround distance L'**
  String get settingAudioDelayLeftRear;

  /// No description provided for @settingAudioDelayRightRear.
  ///
  /// In en, this message translates to:
  /// **'Surround distance R'**
  String get settingAudioDelayRightRear;

  /// No description provided for @settingHeightChannelLevel.
  ///
  /// In en, this message translates to:
  /// **'Height level'**
  String get settingHeightChannelLevel;

  /// No description provided for @settingOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settingOn;

  /// No description provided for @settingOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingOff;

  /// No description provided for @settingSurroundAmbient.
  ///
  /// In en, this message translates to:
  /// **'Ambient'**
  String get settingSurroundAmbient;

  /// No description provided for @settingSurroundFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get settingSurroundFull;

  /// No description provided for @profileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get profileNameLabel;

  /// No description provided for @profileNameTaken.
  ///
  /// In en, this message translates to:
  /// **'A profile with this name exists'**
  String get profileNameTaken;

  /// No description provided for @profileNoEntities.
  ///
  /// In en, this message translates to:
  /// **'No entities'**
  String get profileNoEntities;

  /// No description provided for @profileBadgeAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio settings'**
  String get profileBadgeAudio;

  /// No description provided for @profileBadgeVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get profileBadgeVolume;

  /// No description provided for @profileUpdatedAgo.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String profileUpdatedAgo(String time);

  /// No description provided for @profileChipLayoutNames.
  ///
  /// In en, this message translates to:
  /// **'Layout + names'**
  String get profileChipLayoutNames;

  /// No description provided for @profileChipSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileChipSettings;

  /// No description provided for @profileChipNoSettings.
  ///
  /// In en, this message translates to:
  /// **'No settings'**
  String get profileChipNoSettings;

  /// No description provided for @profileChipNoVolume.
  ///
  /// In en, this message translates to:
  /// **'No volume'**
  String get profileChipNoVolume;

  /// No description provided for @profileTimeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get profileTimeJustNow;

  /// No description provided for @profileTimeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 minute ago} other{{count} minutes ago}}'**
  String profileTimeMinutesAgo(int count);

  /// No description provided for @profileTimeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 hour ago} other{{count} hours ago}}'**
  String profileTimeHoursAgo(int count);

  /// No description provided for @profileTimeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 day ago} other{{count} days ago}}'**
  String profileTimeDaysAgo(int count);

  /// No description provided for @profileTimeWeeksAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 week ago} other{{count} weeks ago}}'**
  String profileTimeWeeksAgo(int count);

  /// No description provided for @profileTimeMonthsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 month ago} other{{count} months ago}}'**
  String profileTimeMonthsAgo(int count);

  /// No description provided for @profileTimeYearsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 year ago} other{{count} years ago}}'**
  String profileTimeYearsAgo(int count);

  /// No description provided for @profileAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get profileAppearance;

  /// No description provided for @profileWidgetPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick profiles'**
  String get profileWidgetPickTitle;

  /// No description provided for @profileWidgetEmpty.
  ///
  /// In en, this message translates to:
  /// **'No profiles yet — create one in Sonority first.'**
  String get profileWidgetEmpty;

  /// No description provided for @profileWidgetPickHelper.
  ///
  /// In en, this message translates to:
  /// **'Pick the profiles to show. Reorder them in the Profiles tab.'**
  String get profileWidgetPickHelper;

  /// No description provided for @profileWidgetSelectAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Select at least one'**
  String get profileWidgetSelectAtLeastOne;

  /// No description provided for @profileWidgetAddCount.
  ///
  /// In en, this message translates to:
  /// **'Add {count} to widget'**
  String profileWidgetAddCount(int count);

  /// No description provided for @discoveryDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get discoveryDiagnostics;

  /// No description provided for @discoveryRescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get discoveryRescan;

  /// No description provided for @discoveryHomeTheaters.
  ///
  /// In en, this message translates to:
  /// **'Home theaters'**
  String get discoveryHomeTheaters;

  /// No description provided for @discoveryNoSoundbar.
  ///
  /// In en, this message translates to:
  /// **'No soundbar found. Dedicated fronts need an Arc, Beam, Ray, Playbar or Playbase.'**
  String get discoveryNoSoundbar;

  /// No description provided for @discoverySpeakerGroups.
  ///
  /// In en, this message translates to:
  /// **'Speaker groups'**
  String get discoverySpeakerGroups;

  /// No description provided for @discoveryGroupSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Group speakers'**
  String get discoveryGroupSpeakers;

  /// No description provided for @discoveryNoGroups.
  ///
  /// In en, this message translates to:
  /// **'No speaker groups yet'**
  String get discoveryNoGroups;

  /// No description provided for @discoverySingleRooms.
  ///
  /// In en, this message translates to:
  /// **'Single speaker rooms'**
  String get discoverySingleRooms;

  /// No description provided for @discoveryOtherDevices.
  ///
  /// In en, this message translates to:
  /// **'Other devices'**
  String get discoveryOtherDevices;

  /// No description provided for @discoverySubwoofer.
  ///
  /// In en, this message translates to:
  /// **'Subwoofer'**
  String get discoverySubwoofer;

  /// No description provided for @discoverySubUnbondedNote.
  ///
  /// In en, this message translates to:
  /// **'This Sub isn’t bonded to anything yet. Add it to a home theater (Configure home theater) or a speaker group to use it.'**
  String get discoverySubUnbondedNote;

  /// No description provided for @discoveryScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning your network…'**
  String get discoveryScanning;

  /// No description provided for @discoveryErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t find your system'**
  String get discoveryErrorTitle;

  /// No description provided for @discoveryTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get discoveryTryAgain;

  /// No description provided for @roomTitle.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get roomTitle;

  /// No description provided for @roomRenameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename room'**
  String get roomRenameTooltip;

  /// No description provided for @roomRenamedTo.
  ///
  /// In en, this message translates to:
  /// **'Renamed to “{name}”.'**
  String roomRenamedTo(String name);

  /// No description provided for @roomRenameFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String roomRenameFailed(String error);

  /// No description provided for @roomGroupWith.
  ///
  /// In en, this message translates to:
  /// **'Group with another speaker'**
  String get roomGroupWith;

  /// No description provided for @roomGroupWithSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stereo pair, full-range zone, or custom L/R'**
  String get roomGroupWithSubtitle;

  /// No description provided for @roomAddToHomeTheater.
  ///
  /// In en, this message translates to:
  /// **'Add to a home theater'**
  String get roomAddToHomeTheater;

  /// No description provided for @roomAddToHomeTheaterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'As a front or surround'**
  String get roomAddToHomeTheaterSubtitle;

  /// No description provided for @roomAddToWhichHomeTheater.
  ///
  /// In en, this message translates to:
  /// **'Add to which home theater?'**
  String get roomAddToWhichHomeTheater;

  /// No description provided for @subAddToGroup.
  ///
  /// In en, this message translates to:
  /// **'Add to a speaker group'**
  String get subAddToGroup;

  /// No description provided for @subAddToGroupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add this sub to a new group'**
  String get subAddToGroupSubtitle;

  /// No description provided for @subAddToHomeTheaterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'As the subwoofer'**
  String get subAddToHomeTheaterSubtitle;

  /// No description provided for @sectionSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Speakers'**
  String get sectionSpeakers;

  /// No description provided for @groupSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Speaker group'**
  String get groupSheetTitle;

  /// No description provided for @groupUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating…'**
  String get groupUpdating;

  /// No description provided for @groupRenameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get groupRenameTooltip;

  /// No description provided for @groupSeparate.
  ///
  /// In en, this message translates to:
  /// **'Separate'**
  String get groupSeparate;

  /// No description provided for @groupRenamedTo.
  ///
  /// In en, this message translates to:
  /// **'Renamed to “{name}”.'**
  String groupRenamedTo(String name);

  /// No description provided for @groupRenameFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String groupRenameFailed(String error);

  /// No description provided for @groupSeparateConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Separate group?'**
  String get groupSeparateConfirmTitle;

  /// No description provided for @groupSeparateConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The speakers become standalone rooms again. Their original room names will be restored.'**
  String get groupSeparateConfirmMessage;

  /// No description provided for @groupSeparateProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Separate group'**
  String get groupSeparateProgressTitle;

  /// No description provided for @groupFlowTitle.
  ///
  /// In en, this message translates to:
  /// **'Group speakers'**
  String get groupFlowTitle;

  /// No description provided for @groupEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure group'**
  String get groupEditTitle;

  /// No description provided for @groupConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get groupConfigure;

  /// No description provided for @groupSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get groupSaveChanges;

  /// No description provided for @groupNeedTwoSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Need at least two standalone speakers (not soundbars, subs, amps, or already bonded).'**
  String get groupNeedTwoSpeakers;

  /// No description provided for @groupModeStereo.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get groupModeStereo;

  /// No description provided for @groupModeZone.
  ///
  /// In en, this message translates to:
  /// **'Zone'**
  String get groupModeZone;

  /// No description provided for @groupModeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get groupModeCustom;

  /// No description provided for @groupStepSelect.
  ///
  /// In en, this message translates to:
  /// **'Select speakers'**
  String get groupStepSelect;

  /// No description provided for @groupStepAddSub.
  ///
  /// In en, this message translates to:
  /// **'Add a Sub'**
  String get groupStepAddSub;

  /// No description provided for @groupOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get groupOptional;

  /// No description provided for @groupStepName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get groupStepName;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name (optional)'**
  String get groupNameLabel;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Downstairs'**
  String get groupNameHint;

  /// No description provided for @groupStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review & create'**
  String get groupStepReview;

  /// No description provided for @groupCreateStereo.
  ///
  /// In en, this message translates to:
  /// **'Create stereo pair'**
  String get groupCreateStereo;

  /// No description provided for @groupCreateZone.
  ///
  /// In en, this message translates to:
  /// **'Create zone'**
  String get groupCreateZone;

  /// No description provided for @groupCreateCustom.
  ///
  /// In en, this message translates to:
  /// **'Create custom group'**
  String get groupCreateCustom;

  /// No description provided for @groupCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t create the group — Sonos may not allow one of these speakers. See the log for details.'**
  String get groupCreateFailed;

  /// No description provided for @groupHintStereo.
  ///
  /// In en, this message translates to:
  /// **'Pick two speakers — one plays left, the other right (swap below). Mismatched models are fine.'**
  String get groupHintStereo;

  /// No description provided for @groupHintZone.
  ///
  /// In en, this message translates to:
  /// **'Pick 2–16 speakers. They all play full stereo (L+R) as one room.'**
  String get groupHintZone;

  /// No description provided for @groupHintCustom.
  ///
  /// In en, this message translates to:
  /// **'Pick 2–16 speakers and set each to Left, Right, or Both.'**
  String get groupHintCustom;

  /// No description provided for @groupChannelLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get groupChannelLeft;

  /// No description provided for @groupChannelBoth.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get groupChannelBoth;

  /// No description provided for @groupChannelRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get groupChannelRight;

  /// No description provided for @groupNoSub.
  ///
  /// In en, this message translates to:
  /// **'No standalone Sub available. A Sub bonded to a home theater must be removed there first.'**
  String get groupNoSub;

  /// No description provided for @groupAddSubHint.
  ///
  /// In en, this message translates to:
  /// **'Optionally add a Sub to the group.'**
  String get groupAddSubHint;

  /// No description provided for @groupSubwoofer.
  ///
  /// In en, this message translates to:
  /// **'Subwoofer'**
  String get groupSubwoofer;

  /// No description provided for @groupKindStereo.
  ///
  /// In en, this message translates to:
  /// **'Stereo pair'**
  String get groupKindStereo;

  /// No description provided for @groupKindZone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Zone ({count} speaker)} other{Zone ({count} speakers)}}'**
  String groupKindZone(int count);

  /// No description provided for @groupKindCustom.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Custom group ({count} speaker)} other{Custom group ({count} speakers)}}'**
  String groupKindCustom(int count);

  /// No description provided for @groupReviewMemberLine.
  ///
  /// In en, this message translates to:
  /// **'{room} — {channel}'**
  String groupReviewMemberLine(String room, String channel);

  /// No description provided for @groupReviewName.
  ///
  /// In en, this message translates to:
  /// **'Name: {name}'**
  String groupReviewName(String name);

  /// No description provided for @groupReviewSub.
  ///
  /// In en, this message translates to:
  /// **'Sub: {type}'**
  String groupReviewSub(String type);

  /// No description provided for @groupReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Bonded speakers play as one room. Larger or mixed-model groups can drop out briefly — play something to confirm it works for you. Original room names are restored when you separate the group.'**
  String get groupReviewNote;

  /// No description provided for @htHomeTheater.
  ///
  /// In en, this message translates to:
  /// **'Home theater'**
  String get htHomeTheater;

  /// No description provided for @htRenameRoomTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename room'**
  String get htRenameRoomTooltip;

  /// No description provided for @htUpdatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Updating your home theater…'**
  String get htUpdatingTitle;

  /// No description provided for @htUpdatingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This can take up to ~20 seconds while Sonos reconfigures and re-reads the layout.'**
  String get htUpdatingSubtitle;

  /// No description provided for @htRenamedTo.
  ///
  /// In en, this message translates to:
  /// **'Renamed to “{name}”.'**
  String htRenamedTo(String name);

  /// No description provided for @htRenameFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String htRenameFailed(String error);

  /// No description provided for @htSeparateConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Separate home theater?'**
  String get htSeparateConfirmTitle;

  /// No description provided for @htRemoveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {label}?'**
  String htRemoveConfirmTitle(String label);

  /// No description provided for @htSeparateMessage.
  ///
  /// In en, this message translates to:
  /// **'All extra speakers will be un-bonded and become standalone rooms again, leaving just the soundbar.'**
  String get htSeparateMessage;

  /// No description provided for @htRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'These speakers will be un-bonded and become standalone rooms again. The rest of your home theater stays as it is.'**
  String get htRemoveMessage;

  /// No description provided for @htSeparate.
  ///
  /// In en, this message translates to:
  /// **'Separate'**
  String get htSeparate;

  /// No description provided for @htSeparateProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Separate home theater'**
  String get htSeparateProgressTitle;

  /// No description provided for @htRemoveProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {label}'**
  String htRemoveProgressTitle(String label);

  /// No description provided for @htGroupFronts.
  ///
  /// In en, this message translates to:
  /// **'Fronts'**
  String get htGroupFronts;

  /// No description provided for @htGroupSurrounds.
  ///
  /// In en, this message translates to:
  /// **'Surrounds'**
  String get htGroupSurrounds;

  /// No description provided for @htGroupSubwoofer.
  ///
  /// In en, this message translates to:
  /// **'Subwoofer'**
  String get htGroupSubwoofer;

  /// No description provided for @htConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get htConfigure;

  /// No description provided for @htBondedSpeakers.
  ///
  /// In en, this message translates to:
  /// **'Bonded speakers'**
  String get htBondedSpeakers;

  /// No description provided for @htNoBonded.
  ///
  /// In en, this message translates to:
  /// **'Just the soundbar — no fronts, surrounds or sub bonded yet. Tap “Configure” to add some.'**
  String get htNoBonded;

  /// No description provided for @htSpeakerFallback.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get htSpeakerFallback;

  /// No description provided for @htTrueplayNote.
  ///
  /// In en, this message translates to:
  /// **'Trueplay can only be measured from the Sonos app on iOS — tune the home theater, and the fronts separately as a stereo pair. Heads-up: Sonos often clears a tuning when speakers are bonded/unbonded, so you may see “Not tuned” after changing the layout and have to redo it. Sonority only toggles a stored tuning.'**
  String get htTrueplayNote;

  /// No description provided for @htAllExtraSpeakers.
  ///
  /// In en, this message translates to:
  /// **'all extra speakers'**
  String get htAllExtraSpeakers;

  /// No description provided for @htBonded.
  ///
  /// In en, this message translates to:
  /// **'Bonded'**
  String get htBonded;

  /// No description provided for @frontSurroundsTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure home theater'**
  String get frontSurroundsTitle;

  /// No description provided for @frontSurroundsStepFronts.
  ///
  /// In en, this message translates to:
  /// **'Front speakers'**
  String get frontSurroundsStepFronts;

  /// No description provided for @frontSurroundsOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get frontSurroundsOptional;

  /// No description provided for @frontSurroundsFrontsHint.
  ///
  /// In en, this message translates to:
  /// **'Pick two speakers (or a single Amp) for the front left & right, then set which is which.'**
  String get frontSurroundsFrontsHint;

  /// No description provided for @frontSurroundsStepSurrounds.
  ///
  /// In en, this message translates to:
  /// **'Rear surrounds'**
  String get frontSurroundsStepSurrounds;

  /// No description provided for @frontSurroundsSurroundsHint.
  ///
  /// In en, this message translates to:
  /// **'Pick two speakers for the rear left & right surrounds.'**
  String get frontSurroundsSurroundsHint;

  /// No description provided for @frontSurroundsStepSub.
  ///
  /// In en, this message translates to:
  /// **'Subwoofer'**
  String get frontSurroundsStepSub;

  /// No description provided for @frontSurroundsStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review & apply'**
  String get frontSurroundsStepReview;

  /// No description provided for @frontSurroundsUnbondTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Unbond {count} speaker?} other{Unbond {count} speakers?}}'**
  String frontSurroundsUnbondTitle(int count);

  /// No description provided for @frontSurroundsUnbondMessage.
  ///
  /// In en, this message translates to:
  /// **'{types} will be removed from this home theater and become standalone rooms again. The rest of your layout stays as it is.'**
  String frontSurroundsUnbondMessage(String types);

  /// No description provided for @frontSurroundsUnbond.
  ///
  /// In en, this message translates to:
  /// **'Unbond'**
  String get frontSurroundsUnbond;

  /// No description provided for @frontSurroundsNoFreeSpeakers.
  ///
  /// In en, this message translates to:
  /// **'No free speakers available. They must be standalone (not already part of a home theater or stereo pair).'**
  String get frontSurroundsNoFreeSpeakers;

  /// No description provided for @frontSurroundsPickWithAmp.
  ///
  /// In en, this message translates to:
  /// **'Pick two speakers (ideally identical), or a single Sonos Amp that drives both front speakers.'**
  String get frontSurroundsPickWithAmp;

  /// No description provided for @frontSurroundsPickExactlyTwo.
  ///
  /// In en, this message translates to:
  /// **'Pick exactly two — ideally an identical pair.'**
  String get frontSurroundsPickExactlyTwo;

  /// No description provided for @frontSurroundsAmpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{type} — drives both fronts (L + R)'**
  String frontSurroundsAmpSubtitle(String type);

  /// No description provided for @frontSurroundsNoFreeSub.
  ///
  /// In en, this message translates to:
  /// **'No free subwoofer found. A Sonos Sub must be standalone (not already bonded to another home theater).'**
  String get frontSurroundsNoFreeSub;

  /// No description provided for @frontSurroundsSubHint.
  ///
  /// In en, this message translates to:
  /// **'Pick one or two subwoofers to add as low-frequency channels.'**
  String get frontSurroundsSubHint;

  /// No description provided for @frontSurroundsAmpWiring.
  ///
  /// In en, this message translates to:
  /// **'The {amp} drives both front channels. Wire your left & right speakers to its L/R speaker outputs — there’s nothing to assign here.'**
  String frontSurroundsAmpWiring(String amp);

  /// No description provided for @frontSurroundsChooseTwoFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose two speakers first.'**
  String get frontSurroundsChooseTwoFirst;

  /// No description provided for @frontSurroundsTapSwap.
  ///
  /// In en, this message translates to:
  /// **'Tap swap if the sides are reversed.'**
  String get frontSurroundsTapSwap;

  /// No description provided for @frontSurroundsNothingSelected.
  ///
  /// In en, this message translates to:
  /// **'Nothing selected yet — choose speakers above.'**
  String get frontSurroundsNothingSelected;

  /// No description provided for @frontSurroundsReviewNote.
  ///
  /// In en, this message translates to:
  /// **'The chosen speakers become hidden satellites of the soundbar (which stays the center channel). Bonding runs in steps and can take a little while; Trueplay may need re-tuning afterward. You can change this anytime.'**
  String get frontSurroundsReviewNote;

  /// No description provided for @diagNoSystemToCollect.
  ///
  /// In en, this message translates to:
  /// **'No system to collect — scan first.'**
  String get diagNoSystemToCollect;

  /// No description provided for @diagBuildFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not build the diagnostics bundle: {error}'**
  String diagBuildFailed(String error);

  /// No description provided for @diagActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the action: {error}'**
  String diagActionFailed(String error);

  /// No description provided for @diagSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String diagSavedTo(String path);

  /// No description provided for @diagTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagTitle;

  /// No description provided for @diagNoSystem.
  ///
  /// In en, this message translates to:
  /// **'No system discovered yet.'**
  String get diagNoSystem;

  /// No description provided for @diagIncludeLogs.
  ///
  /// In en, this message translates to:
  /// **'Include app logs'**
  String get diagIncludeLogs;

  /// No description provided for @diagIncludeLogsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SOAP faults, bond retries, discovery, errors (logs.txt)'**
  String get diagIncludeLogsSubtitle;

  /// No description provided for @diagIncludeNetwork.
  ///
  /// In en, this message translates to:
  /// **'Include phone network info'**
  String get diagIncludeNetwork;

  /// No description provided for @diagIncludeNetworkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This device’s network interface addresses (network.txt)'**
  String get diagIncludeNetworkSubtitle;

  /// No description provided for @diagAlwaysIncluded.
  ///
  /// In en, this message translates to:
  /// **'Always included: topology (room names, IPs, MACs, models), raw device descriptions, and your saved profiles/room names.'**
  String get diagAlwaysIncluded;

  /// No description provided for @diagCollecting.
  ///
  /// In en, this message translates to:
  /// **'Collecting…'**
  String get diagCollecting;

  /// No description provided for @diagEmailToDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Email to developer'**
  String get diagEmailToDeveloper;

  /// No description provided for @diagShareDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Share diagnostics'**
  String get diagShareDiagnostics;

  /// No description provided for @diagEmailBody.
  ///
  /// In en, this message translates to:
  /// **'Describe what went wrong (what you tried, what you expected, what happened):\n\n\n——— the diagnostics bundle is attached below ———'**
  String get diagEmailBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
