import 'api_parameter.dart';
import 'api_request_body.dart';
import 'api_response.dart';

/// An API operation (one HTTP method on one path).
class ApiOperation {
  const ApiOperation({
    required this.method,
    required this.operationId,
    this.summary,
    this.description,
    this.parameters = const [],
    this.requestBody,
    this.responses = const [],
    this.security = const [],
    this.tags = const [],
    this.deprecated = false,
  });

  /// HTTP method (get, post, put, delete, patch, head, options).
  final String method;

  /// Unique operation identifier.
  final String operationId;

  /// Short summary.
  final String? summary;

  /// Long description.
  final String? description;

  /// Operation parameters (path, query, header, cookie).
  final List<ApiParameter> parameters;

  /// Request body (if any).
  final ApiRequestBody? requestBody;

  /// Responses keyed by status code.
  final List<ApiResponse> responses;

  /// Security requirements (list of maps: scheme name → scopes).
  final List<Map<String, List<String>>> security;

  /// Tags for grouping operations into client classes.
  final List<String> tags;

  /// Whether this operation is deprecated.
  final bool deprecated;

  /// Find the success response (prefer 200, then 201, then first 2xx).
  ApiResponse? get successResponse {
    final r200 = responses.where((r) => r.statusCode == '200').firstOrNull;
    if (r200 != null) return r200;
    final r201 = responses.where((r) => r.statusCode == '201').firstOrNull;
    if (r201 != null) return r201;
    return responses
        .where((r) => r.statusCode.startsWith('2') && r.statusCode.length == 3)
        .firstOrNull;
  }

  @override
  String toString() => 'ApiOperation($method $operationId)';
}
