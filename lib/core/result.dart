/// A tiny typed result wrapper so network/UPnP operations surface failures
/// explicitly instead of throwing across layers.
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) ok,
    required R Function(Object error, StackTrace stack) err,
  }) {
    final self = this;
    return switch (self) {
      Ok<T>() => ok(self.value),
      Err<T>() => err(self.error, self.stack),
    };
  }

  bool get isOk => this is Ok<T>;
  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends Result<T> {
  final Object error;
  final StackTrace stack;
  const Err(this.error, [this.stack = StackTrace.empty]);
}

/// Raised when a Sonos device returns a SOAP fault.
class SonosSoapException implements Exception {
  final String action;
  final int? statusCode;
  final String? faultCode;
  final String? faultString;

  SonosSoapException(this.action, {this.statusCode, this.faultCode, this.faultString});

  @override
  String toString() =>
      'SonosSoapException($action, status=$statusCode, code=$faultCode, msg=$faultString)';
}
