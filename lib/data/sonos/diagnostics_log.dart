/// App-wide rolling log for the diagnostics bundle.
///
/// Unlike the per-operation `operationLogProvider` (which is cleared at the start
/// of each bonding op so the progress screen only shows that op), this is a
/// single process-lifetime ring buffer that captures everything worth
/// escalating: SOAP faults/timeouts thrown anywhere, discovery details, bond
/// retries, and uncaught Flutter/platform errors. Pure Dart (no Flutter) so the
/// engine and CLI tools can write to it directly.
///
/// ponytail: in-memory only, capped ring buffer — no disk persistence. Add a
/// file sink only if users turn out to be unable to reproduce a bug live before
/// sharing.
class DiagnosticsLog {
  DiagnosticsLog._();

  static const _max = 500;
  static final List<String> _lines = [];

  /// Appends [line], timestamped `HH:MM:SS`, dropping the oldest past [_max].
  static void add(String line) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final ts = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    _lines.add('$ts  $line');
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
  }

  /// A snapshot of the buffered lines, oldest first.
  static List<String> get lines => List.unmodifiable(_lines);

  static void clear() => _lines.clear();
}
