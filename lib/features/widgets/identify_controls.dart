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
  /// this mixin's actions and busy state.
  Widget identifyButtons(SonosDevice device) => IdentifyButtons(
        busy: _identifyingUuid == device.uuid,
        onBlink: () => identify(device),
        onChime: onChime == null ? null : () => onChime!(device),
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
