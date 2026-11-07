class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final dynamic details;

  ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => message;

  factory ApiException.fromResponse(int statusCode, dynamic json) {
    String code = 'API_ERROR';
    String message = 'An unexpected server error occurred ($statusCode).';
    dynamic details;

    if (json is Map<String, dynamic>) {
      if (json.containsKey('error') && json['error'] is Map<String, dynamic>) {
        final err = json['error'] as Map<String, dynamic>;
        code = err['code']?.toString() ?? code;
        message = err['message']?.toString() ?? message;
        details = err['details'];
      } else if (json.containsKey('detail')) {
        final detail = json['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first.containsKey('msg')) {
            message = first['msg'].toString();
          } else {
            message = detail.toString();
          }
        }
      } else if (json.containsKey('message')) {
        message = json['message'].toString();
      }
    }

    return ApiException(
      statusCode: statusCode,
      code: code,
      message: message,
      details: details,
    );
  }

  factory ApiException.networkError(dynamic error) {
    return ApiException(
      statusCode: 0,
      code: 'NETWORK_ERROR',
      message: 'Unable to connect to the backend server. Please check your network connection or API URL.',
      details: error?.toString(),
    );
  }
}
