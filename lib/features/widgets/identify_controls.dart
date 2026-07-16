import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sonos_models.dart';
import '../../data/sonos/identify_service.dart';
import '../../state/sonos_controller.dart';

/// The standard "identify this speaker" controls: a lightbulb button that blinks
/// the status LED (works on every platform), and — when [onChime] is non-null
/// (mobile only) — a separate speaker button that plays an audio chime.
class IdentifyButtons extends StatelessWidget {
  final bool busy;
  final VoidCallback onBlink;
  final VoidCallback? onChime;
  const IdentifyButtons({
    super.key,
    required this.busy,
    required this.onBlink,
    this.onChime,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Blink the light',
          onPressed: busy ? null : onBlink,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lightbulb_outline),
        ),
        if (onChime != null)
          IconButton(
            tooltip: 'Play a test chime',
            onPressed: busy ? null : onChime,
            icon: const Icon(Icons.volume_up_outlined),
          ),
      ],
    );
  }
}

/// Shared speaker-identify behaviour for the flows that let the user pick
/// physical speakers (front surrounds, stereo pair). Mix into a [ConsumerState]
/// to get the blink/chime actions, the per-speaker busy state, and a ready-made
/// [identifyButtons] builder — so the logic lives in exactly one place.
mixin IdentifyMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String? _identifyingUuid;

  /// The uuid currently being identified (for showing a spinner), or null.
  String? get identifyingUuid => _identifyingUuid;

  /// Whether the audio chime can run here. It needs an inbound LAN connection
  /// the macOS sandbox blocks, so it's mobile-only; LED blink works everywhere.
  bool get _chimeSupported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  /// The chime callback to wire to a button, or null where the chime can't run
  /// (so the UI hides it).
  Future<void> Function(SonosDevice)? get onChime =>
      _chimeSupported ? playChime : null;

  /// Blinks a speaker's status LED so the user can tell which physical box it
  /// is. The default identify action — silent and works on every platform.
  Future<void> identify(SonosDevice device) =>
      _run(device, '💡 Blinking the light on ${device.roomName}…', () async {
        await ref.read(ledIdentifyProvider).blink(device.ip!);
      });

  /// Plays an audio chime (mobile only) as an audible alternative to the blink.
  Future<void> playChime(SonosDevice device) =>
      _run(device, '🔊 Playing a chime on ${device.roomName}…', () async {
        await ref.read(identifyServiceProvider).chirp(device.ip!);
      });

  /// The standard lightbulb (+ mobile chime) controls for [device], wired to
  /// this mixin's actions and busy state. Pass `chime: false` for a bonded
  /// speaker: a satellite / group member can't play the chime on its own (and a
  /// coordinator's chime plays the whole bond), so only the LED blink applies.
  Widget identifyButtons(SonosDevice device, {bool chime = true}) =>
      IdentifyButtons(
        busy: _identifyingUuid == device.uuid,
        onBlink: () => identify(device),
        onChime: (chime && onChime != null) ? () => onChime!(device) : null,
      );

  /// Shared scaffolding: guard on a missing IP, mark busy, show a status
  /// snackbar, run [action], surface errors, and always clear the busy state.
  Future<void> _run(
    SonosDevice device,
    String startMessage,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (device.ip == null) {
      messenger.showSnackBar(
          SnackBar(content: Text('No address for ${device.roomName}.')));
      return;
    }
    setState(() => _identifyingUuid = device.uuid);
    messenger.showSnackBar(SnackBar(
      content: Text(startMessage),
      duration: const Duration(seconds: 2),
    ));
    try {
      await action();
    } on SpeakerUnreachable catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 6)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Couldn’t identify ${device.roomName}: $e')));
    } finally {
      if (mounted) setState(() => _identifyingUuid = null);
    }
  }
}

/// A self-contained per-speaker identify control (LED blink + optional chime)
/// for the detail views that show a single speaker card outside the
/// pick-a-speaker flows — the room / group detail sheets. Wraps [IdentifyButtons]
/// with its own busy state via [IdentifyMixin], so a card can drop it in as a
/// `trailing` widget. Pass [allowChime] = false for a bonded speaker (LED only).
class SpeakerIdentifyButton extends ConsumerStatefulWidget {
  final SonosDevice device;
  final bool allowChime;
  const SpeakerIdentifyButton(
      {super.key, required this.device, this.allowChime = false});

  @override
  ConsumerState<SpeakerIdentifyButton> createState() =>
      _SpeakerIdentifyButtonState();
}

class _SpeakerIdentifyButtonState extends ConsumerState<SpeakerIdentifyButton>
    with IdentifyMixin {
  @override
  Widget build(BuildContext context) =>
      identifyButtons(widget.device, chime: widget.allowChime);
}

/// A [SpeakerIdentifyButton] for [device], or null when there's no reachable
/// device to identify — so a card can pass it straight to a `trailing` slot.
Widget? speakerIdentifyButton(SonosDevice? device, {bool allowChime = false}) =>
    device == null
        ? null
        : SpeakerIdentifyButton(device: device, allowChime: allowChime);
