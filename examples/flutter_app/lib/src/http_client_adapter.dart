import 'package:dart_open_fetch_runtime/dart_open_fetch_runtime.dart';
import 'package:http/http.dart' as http;

/// An [HttpAdapter] implementation backed by `package:http`.
///
/// This is the bridge between dart_open_fetch generated clients and a real
/// HTTP library. Pass an instance of this to any generated client.
class HttpClientAdapter implements HttpAdapter {
  HttpClientAdapter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    final httpRequest = http.Request(request.method, request.url);
    httpRequest.headers.addAll(request.headers);
    if (request.body != null) {
      httpRequest.body = request.body!;
    }

    final streamedResponse = await _client.send(httpRequest);
    final body = await streamedResponse.stream.bytesToString();

    return HttpResponse(
      statusCode: streamedResponse.statusCode,
      headers: streamedResponse.headers,
      body: body,
    );
  }

  /// Close the underlying HTTP client.
  void close() => _client.close();
}
