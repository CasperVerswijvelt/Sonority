// Writes the generated chime to a file so it can be played/inspected locally.
//   dart run tool/dump_chime.dart /tmp/chime.wav

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:soyes/core/tone_generator.dart';

Future<void> main(List<String> argv) async {
  final path = argv.isNotEmpty ? argv.first : '/tmp/chime.wav';
  final bytes = generateChimeWav();
  await File(path).writeAsBytes(bytes);
  print('Wrote ${bytes.length} bytes to $path');
}
