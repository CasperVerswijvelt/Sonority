/// Progress reporting for multi-step bonding operations (full HT setup,
/// profile-apply). Pure Dart (no Flutter) so the engine can emit it and the CLI
/// tools can print it; the UI renders the list as a stepper.
///
/// Phase 0 proved that bonding is inherently multi-step and can fail partway
/// (a satellite silently fails to join), so the user must see which step is
/// active and exactly where/why it failed.
library;

enum ApplyStatus { pending, active, done, failed }

/// One step in a bonding operation, e.g. "Bond surrounds" or "Restore names".
class ApplyStep {
  final String id;
  final String label;
  final ApplyStatus status;

  /// On failure: the reason (SOAP fault, "satellite never joined", …). On
  /// success it may carry a short note ("re-asserted after 1 retry").
  final String? detail;

  const ApplyStep({
    required this.id,
    required this.label,
    this.status = ApplyStatus.pending,
    this.detail,
  });

  ApplyStep copyWith({ApplyStatus? status, String? detail}) => ApplyStep(
        id: id,
        label: label,
        status: status ?? this.status,
        detail: detail ?? this.detail,
      );

  bool get isFailed => status == ApplyStatus.failed;
}

/// A mutable, observable list of [ApplyStep]s. Mutating a step fires [onChange]
/// with an immutable snapshot so the controller can push it to a Riverpod
/// provider the UI watches.
class ApplyProgress {
  final List<ApplyStep> _steps;
  final void Function(List<ApplyStep> steps)? onChange;

  ApplyProgress(List<ApplyStep> steps, {this.onChange})
      : _steps = List.of(steps) {
    _emit();
  }

  List<ApplyStep> get steps => List.unmodifiable(_steps);

  int _indexOf(String id) => _steps.indexWhere((s) => s.id == id);

  void start(String id) => _set(id, ApplyStatus.active);
  void done(String id, {String? detail}) => _set(id, ApplyStatus.done, detail);
  void fail(String id, String detail) => _set(id, ApplyStatus.failed, detail);

  void _set(String id, ApplyStatus status, [String? detail]) {
    final i = _indexOf(id);
    if (i < 0) return;
    _steps[i] = _steps[i].copyWith(status: status, detail: detail);
    _emit();
  }

  void _emit() => onChange?.call(steps);
}
