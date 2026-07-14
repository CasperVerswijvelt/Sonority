/// Progress reporting for multi-step bonding operations (full HT setup,
/// profile-apply). Pure Dart (no Flutter); the UI renders the list as a stepper.
///
/// Phase 0 proved that bonding is inherently multi-step and can fail partway
/// (a satellite silently fails to join), so the user must see which step is
/// active and exactly where/why it failed.
library;

enum ApplyStatus { pending, active, done, failed, skipped }

/// One step in a bonding operation, e.g. "Bond surrounds" or "Restore names".
/// A step with a [parentId] is a phase sub-step rendered nested under its
/// parent (entity) step; the list stays flat — tree order == list order
/// because operations run strictly sequentially.
class ApplyStep {
  final String id;
  final String label;
  final ApplyStatus status;

  /// On failure: the reason (SOAP fault, "satellite never joined", …). On
  /// success it may carry a short note ("re-asserted after 1 retry").
  final String? detail;

  /// Non-null for a phase sub-step nested under a top-level step.
  final String? parentId;

  const ApplyStep({
    required this.id,
    required this.label,
    this.status = ApplyStatus.pending,
    this.detail,
    this.parentId,
  });

  ApplyStep copyWith({ApplyStatus? status, String? detail}) => ApplyStep(
        id: id,
        label: label,
        status: status ?? this.status,
        detail: detail ?? this.detail,
        parentId: parentId,
      );

  bool get isChild => parentId != null;
  bool get isFailed => status == ApplyStatus.failed;
}

/// A mutable, observable list of [ApplyStep]s. Mutating a step fires [onChange]
/// with an immutable snapshot so the controller can push it to a Riverpod
/// provider the UI watches, and [onLog] with a human line so the same events
/// accumulate into a raw log (the timeline shows current state; the log keeps
/// the full history for debugging / copy-out).
class ApplyProgress {
  final List<ApplyStep> _steps;
  final void Function(List<ApplyStep> steps)? onChange;
  final void Function(String line)? onLog;

  /// The most recently begun phase sub-step — [noteActive] routes verbose
  /// per-attempt text here. Well-defined because operations are sequential.
  String? _activeChildId;

  ApplyProgress(List<ApplyStep> steps, {this.onChange, this.onLog})
      : _steps = List.of(steps) {
    _emit();
  }

  List<ApplyStep> get steps => List.unmodifiable(_steps);

  int _indexOf(String id) => _steps.indexWhere((s) => s.id == id);

  void start(String id) {
    _activeChildId = null; // each entity starts with a clean phase slate
    _set(id, ApplyStatus.active);
    _log(id, '▸');
  }

  void done(String id, {String? detail}) {
    _closeActiveChildOf(id, ApplyStatus.done);
    // Drop seeded phases that turned out unnecessary.
    _steps.removeWhere(
        (s) => s.parentId == id && s.status == ApplyStatus.pending);
    _set(id, ApplyStatus.done, detail);
    _log(id, '✓');
  }

  void fail(String id, String detail) {
    // The view shows the error on the sub-step when the parent has children,
    // so the failing phase must carry the reason too.
    _closeActiveChildOf(id, ApplyStatus.failed, detail);
    _set(id, ApplyStatus.failed, detail);
    _log(id, '✗', detail);
  }

  /// Fails whichever top-level step is currently active (and its active child)
  /// with [detail]. No-op if nothing is active. Used to attach an abort reason
  /// to the step that was running when the user hit Abort.
  void failActive(String detail) {
    final i = _steps.indexWhere(
        (s) => s.parentId == null && s.status == ApplyStatus.active);
    if (i >= 0) fail(_steps[i].id, detail);
  }

  /// Seeds pending phase sub-steps under [parentId] (the phases knowable
  /// upfront); conditional phases are inserted later by [startSub].
  void seedSubs(String parentId, List<(String id, String label)> subs) {
    var at = _lastChildIndex(parentId) + 1;
    for (final (id, label) in subs) {
      _steps.insert(
          at++, ApplyStep(id: id, label: label, parentId: parentId));
    }
    _emit();
  }

  /// Begins phase [id] under [parentId]: completes the previously active
  /// phase (starting phase N+1 means N finished), activates the seeded
  /// sub-step if it exists (refreshing its label — seeds may be approximate),
  /// else inserts it before the parent's first pending sub-step (a
  /// conditional phase like "freeing" runs before the seeded ones).
  void startSub(String parentId, String id, String label) {
    if (_activeChildId != id) _closeActiveChildOf(parentId, ApplyStatus.done);
    final step = ApplyStep(
        id: id, label: label, status: ApplyStatus.active, parentId: parentId);
    final i = _indexOf(id);
    if (i >= 0) {
      _steps[i] = step;
    } else {
      var at = _steps.indexWhere(
          (s) => s.parentId == parentId && s.status == ApplyStatus.pending);
      if (at < 0) at = _lastChildIndex(parentId) + 1;
      _steps.insert(at, step);
    }
    _activeChildId = id;
    _emit();
    _log(id, '▸');
  }

  /// Marks the active phase skipped — it turned out to be a no-op (e.g.
  /// "layout unchanged", "name already set"). The step stays in the list (no
  /// layout shift) but renders distinctly from real work.
  void skipSub({String? detail}) {
    final id = _activeChildId;
    if (id == null) return;
    _activeChildId = null;
    _set(id, ApplyStatus.skipped, detail);
    _log(id, '−', detail);
  }

  /// Verbose within-phase progress ("attempt 2: re-asserting") → subtitle of
  /// the active phase sub-step; falls back to the active top-level step so
  /// paths without phases still surface their notes.
  void noteActive(String detail) {
    final id = _activeChildId ??
        _steps
            .where((s) => !s.isChild && s.status == ApplyStatus.active)
            .firstOrNull
            ?.id;
    if (id != null) note(id, detail);
  }

  void _closeActiveChildOf(String parentId, ApplyStatus status,
      [String? detail]) {
    final id = _activeChildId;
    if (id == null) return;
    final i = _indexOf(id);
    if (i < 0 || _steps[i].parentId != parentId) return;
    _activeChildId = null;
    if (_steps[i].status != ApplyStatus.active) return;
    // Clear the transient verbose note unless we're recording a failure.
    _steps[i] = ApplyStep(
      id: _steps[i].id,
      label: _steps[i].label,
      status: status,
      detail: detail,
      parentId: parentId,
    );
    _emit();
    _log(id, status == ApplyStatus.failed ? '✗' : '✓', detail);
  }

  int _lastChildIndex(String parentId) {
    var last = _indexOf(parentId);
    for (var i = 0; i < _steps.length; i++) {
      if (_steps[i].parentId == parentId) last = i;
    }
    return last;
  }

  /// Updates the live detail of a step without changing its status — used to
  /// surface per-attempt notes ("re-asserting…") while a step is active. Also
  /// appended (indented) to the raw log.
  void note(String id, String detail) {
    final i = _indexOf(id);
    if (i < 0) return;
    _steps[i] = _steps[i].copyWith(detail: detail);
    _emit();
    onLog?.call('    $detail');
  }

  void _set(String id, ApplyStatus status, [String? detail]) {
    final i = _indexOf(id);
    if (i < 0) return;
    _steps[i] = _steps[i].copyWith(status: status, detail: detail);
    _emit();
  }

  void _log(String id, String glyph, [String? detail]) {
    final i = _indexOf(id);
    if (i < 0) return;
    final indent = _steps[i].isChild ? '  ' : '';
    final suffix = detail == null ? '' : ': $detail';
    onLog?.call('$indent$glyph ${_steps[i].label}$suffix');
  }

  void _emit() => onChange?.call(steps);
}
