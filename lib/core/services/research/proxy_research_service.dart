import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:visiosoil_app/core/services/research/http_transport.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// [ResearchService] over the documented app↔proxy HTTP contract
/// (`POST /v1/management-tips`; see docs/architecture/research-agent.md §4).
///
/// Resilience mirrors `InferenceService`: a per-attempt [_timeout], up to
/// [_maxAttempts] tries with a [_retryDelay] backoff on transient failures, and
/// a typed [ResearchResult] instead of throwing. No provider credentials live
/// here — the proxy holds them; the only secret-adjacent header is an optional
/// bearer from the injected [TokenProvider].
class ProxyResearchService implements ResearchService {
  ProxyResearchService(
    this._transport, {
    required String baseUrl,
    TokenProvider? tokenProvider,
    String appVersion = _defaultAppVersion,
    Duration timeout = _defaultTimeout,
    Duration retryDelay = _defaultRetryDelay,
    int maxAttempts = _defaultMaxAttempts,
  })  : _endpoint = _resolveEndpoint(baseUrl),
        _tokenProvider = tokenProvider ?? _noToken,
        _appVersion = appVersion,
        _timeout = timeout,
        _retryDelay = retryDelay,
        _maxAttempts = maxAttempts;

  static const String _path = '/v1/management-tips';
  static const String _defaultAppVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  static const Duration _defaultTimeout = Duration(seconds: 20);
  static const Duration _defaultRetryDelay = Duration(milliseconds: 400);
  static const int _defaultMaxAttempts = 3;
  static const String _defaultLocale = 'pt-BR';

  final HttpTransport _transport;
  final Uri _endpoint;
  final TokenProvider _tokenProvider;
  final String _appVersion;
  final Duration _timeout;
  final Duration _retryDelay;
  final int _maxAttempts;

  static Future<String?> _noToken() async => null;

  static Uri _resolveEndpoint(String baseUrl) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed$_path');
  }

  @override
  Future<ResearchResult> fetchTips(SoilRecord record, {String? locale}) async {
    final uuid = record.uuid;
    final textureClass = record.textureClass;
    if (uuid == null ||
        uuid.isEmpty ||
        textureClass == null ||
        textureClass.isEmpty) {
      // No identity or no class to research — fail before touching the network.
      return const ResearchFailure(ResearchFailureKind.invalidRecord);
    }

    final body = jsonEncode({
      'recordUuid': uuid,
      'textureClass': textureClass,
      'latitude': record.latitude,
      'longitude': record.longitude,
      'address': record.address,
      'locale': locale ?? _defaultLocale,
    });
    final headers = await _buildHeaders();

    var lastFailure = const ResearchFailure(ResearchFailureKind.network);
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      final outcome = await _attempt(headers, body);
      if (outcome is ResearchSuccess) return outcome;

      lastFailure = outcome as ResearchFailure;
      if (!_isRetryable(lastFailure)) return lastFailure;
      if (attempt < _maxAttempts) {
        await Future<void>.delayed(_retryDelay);
      }
    }
    return lastFailure;
  }

  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'X-App-Version': _appVersion,
    };
    final token = await _tokenProvider();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<ResearchResult> _attempt(
    Map<String, String> headers,
    String body,
  ) async {
    final TransportResponse response;
    try {
      response = await _transport
          .postJson(url: _endpoint, headers: headers, body: body)
          .timeout(_timeout);
    } on TimeoutException {
      return const ResearchFailure(ResearchFailureKind.timeout);
    } on Exception catch (e) {
      // Connection-level transport failures (socket reset, DNS, TLS) are all
      // Exceptions; surface them as a typed result instead of throwing into UI.
      developer.log('research request failed: $e',
          name: 'ProxyResearchService');
      return const ResearchFailure(ResearchFailureKind.network);
    }

    if (response.statusCode == 200) {
      return _parse(response.body);
    }
    return ResearchFailure(
      _statusToKind(response.statusCode),
      statusCode: response.statusCode,
    );
  }

  ResearchResult _parse(String body) {
    // Trust boundary: a contract-violating body can throw a FormatException
    // (Exception) from jsonDecode OR a cast TypeError (Error) from fromJson.
    // Both must surface as malformedResponse, so the catch is deliberately broad.
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return ResearchSuccess(ManagementTipsResult.fromJson(json));
    } catch (e) {
      developer.log('malformed tips body: $e', name: 'ProxyResearchService');
      return const ResearchFailure(ResearchFailureKind.malformedResponse);
    }
  }

  static ResearchFailureKind _statusToKind(int statusCode) {
    switch (statusCode) {
      case 401:
        return ResearchFailureKind.unauthenticated;
      case 429:
        return ResearchFailureKind.rateLimited;
      default:
        // 5xx and any other unexpected non-200 are reported as an upstream
        // problem; only 5xx is actually retried (see _isRetryable).
        return ResearchFailureKind.upstreamUnavailable;
    }
  }

  static bool _isRetryable(ResearchFailure failure) {
    switch (failure.kind) {
      case ResearchFailureKind.timeout:
      case ResearchFailureKind.network:
        return true;
      case ResearchFailureKind.upstreamUnavailable:
        // Retry genuine server-side errors (5xx) and statusless transport
        // failures only; an unexpected 4xx will not be fixed by retrying.
        final code = failure.statusCode;
        return code == null || code >= 500;
      case ResearchFailureKind.invalidRecord:
      case ResearchFailureKind.unauthenticated:
      case ResearchFailureKind.rateLimited:
      case ResearchFailureKind.malformedResponse:
        return false;
    }
  }
}
