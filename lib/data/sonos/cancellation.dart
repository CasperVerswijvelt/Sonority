/// Cooperative cancellation for the long, multi-step bonding operations.
///
/// The bonding ops are sequences of SOAP writes interleaved with long settle
/// delays (a single `bondAndVerify` can run 8×16s). They can't be killed
/// mid-SOAP-call, but they CAN stop at the next checkpoint — so abort is
/// cooperative: callers check the token between steps and during delays, and a
/// cancelled token throws [OperationCancelled], which unwinds the sequence.
library;

/// Thrown by [CancellationToken.throwIfCancelled] when an operation was aborted.
class OperationCancelled implements Exception {
  const OperationCancelled();
  @override
  String toString() => 'Operation aborted';
}

/// A one-shot cancel flag. Create one per operation, hand it to the worker, and
/// call [cancel] from the UI to abort.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// Throws [OperationCancelled] if already cancelled — call at loop boundaries
  /// and before/after major awaits.
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelled();
  }
}

/// Like `Future.delayed`, but wakes every [slice] to check [token] so an abort
/// during a long settle stops within ~[slice] instead of waiting out the whole
/// delay. Throws [OperationCancelled] as soon as the token is cancelled.
Future<void> interruptibleDelay(
  Duration total,
  CancellationToken? token, {
  Duration slice = const Duration(milliseconds: 250),
}) async {
  if (token == null) return Future<void>.delayed(total);
  var remaining = total;
  while (remaining > Duration.zero) {
    token.throwIfCancelled();
    final step = remaining < slice ? remaining : slice;
    await Future<void>.delayed(step);
    remaining -= step;
  }
  token.throwIfCancelled();
}
