import 'package:http/http.dart' as http;

/// Minimal HTTP response surface the research layer depends on, kept decoupled
/// from package:http so the transport can be faked in tests without its types.
class TransportResponse {
  const TransportResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// Thin, fakeable HTTP seam wrapping package:http. It applies no timeout or
/// retry of its own — resilience is the caller's concern (see
/// [ProxyResearchService]), mirroring how `InferenceService` owns its timeouts
/// around an injected loader. Fakes implement this seam directly (house style,
/// no mockito/mocktail).
abstract class HttpTransport {
  /// POSTs [body] to [url] with [headers] and returns the raw response.
  Future<TransportResponse> postJson({
    required Uri url,
    required Map<String, String> headers,
    required String body,
  });
}

/// [HttpTransport] backed by a real package:http [http.Client].
///
/// Owns the [http.Client] when none is injected; whoever constructs this (the
/// research provider, wired in issue #95) is responsible for calling [close]
/// on disposal so the client's sockets are released.
class HttpClientTransport implements HttpTransport {
  HttpClientTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<TransportResponse> postJson({
    required Uri url,
    required Map<String, String> headers,
    required String body,
  }) async {
    final response = await _client.post(url, headers: headers, body: body);
    return TransportResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  /// Releases the underlying client.
  void close() => _client.close();
}
