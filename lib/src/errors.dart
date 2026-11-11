/// An error the server answers with [status] and a
/// `{"error": code, "message": message}` body.
class FrtException implements Exception {
  final int status;
  final String code;
  final String message;

  FrtException(this.status, this.code, this.message);

  FrtException.badRequest(String message) : this(400, 'bad_request', message);

  @override
  String toString() => message;
}
