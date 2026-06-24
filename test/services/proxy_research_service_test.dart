// Tests for ProxyResearchService: request building, response parsing, resilience
// (timeout + bounded retries), and typed failure mapping — all against a fake
// HttpTransport, so no real socket or package:http client is touched.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/research/http_transport.dart';
import 'package:visiosoil_app/core/services/research/proxy_research_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Captured outbound request, for asserting payload and headers.
class _Captured {
  const _Captured({required this.url, required this.headers, required this.body});
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

/// Fake transport that replays a scripted list of outcomes. Each entry is either
/// a [TransportResponse] (returned) or an [Object] (thrown). When more calls are
/// made than entries, the last entry is repeated — so a single-element script
/// models "always returns/throws this".
class _FakeTransport implements HttpTransport {
  _FakeTransport(this._outcomes);

  final List<Object> _outcomes;
  int callCount = 0;
  final List<_Captured> captured = [];

  @override
  Future<TransportResponse> postJson({
    required Uri url,
    required Map<String, String> headers,
    required String body,
  }) async {
    captured.add(_Captured(url: url, headers: headers, body: body));
    final index = callCount < _outcomes.length ? callCount : _outcomes.length - 1;
    callCount++;
    final outcome = _outcomes[index];
    if (outcome is TransportResponse) return outcome;
    throw outcome;
  }
}

TransportResponse _ok(String body) => TransportResponse(statusCode: 200, body: body);
TransportResponse _status(int code) =>
    TransportResponse(statusCode: code, body: '{}');

const _groundedJson = '''
{
  "status": "grounded",
  "tips": [{"text": "Mantenha cobertura vegetal permanente.", "citations": [0]}],
  "sources": [
    {"title": "Embrapa Solos", "url": "https://embrapa.br/x",
     "publisher": "Embrapa", "date": "2025-03-01"}
  ],
  "disclaimer": "Orientacao advisory; valide com analise de solo local.",
  "model": "groq:llama-3.3-70b",
  "retrievedAt": "2026-06-23T12:00:00Z"
}
''';

const _abstainedJson = '''
{
  "status": "abstained",
  "tips": [],
  "sources": [{"title": "Busca", "url": "https://example.org/q"}],
  "disclaimer": "Evidencia insuficiente; veja o que encontramos.",
  "model": "groq:llama-3.3-70b",
  "retrievedAt": "2026-06-23T12:00:00Z"
}
''';

SoilRecord _record({
  String? uuid = 'rec-uuid-1',
  String? textureClass = 'Argilosa',
}) =>
    SoilRecord(
      uuid: uuid,
      imagePath: '/data/img.jpg',
      timestamp: '2026-06-23T10:00:00Z',
      latitude: -23.5,
      longitude: -46.6,
      address: 'Piracicaba, SP',
      textureClass: textureClass,
    );

ProxyResearchService _service(
  HttpTransport transport, {
  TokenProvider? tokenProvider,
}) =>
    ProxyResearchService(
      transport,
      baseUrl: 'https://proxy.test',
      tokenProvider: tokenProvider,
      retryDelay: Duration.zero,
    );

void main() {
  group('ProxyResearchService', () {
    test('builds_request_payload_from_soil_record', () async {
      final transport = _FakeTransport([_ok(_groundedJson)]);

      await _service(transport).fetchTips(_record(), locale: 'pt-BR');

      final req = transport.captured.single;
      expect(req.url.toString(), 'https://proxy.test/v1/management-tips');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['recordUuid'], 'rec-uuid-1');
      expect(body['textureClass'], 'Argilosa');
      expect(body['latitude'], -23.5);
      expect(body['longitude'], -46.6);
      expect(body['address'], 'Piracicaba, SP');
      expect(body['locale'], 'pt-BR');
      expect(req.headers['Content-Type'], contains('application/json'));
      expect(req.headers['X-App-Version'], isNotEmpty);
    });

    test('returns_grounded_success_for_grounded_body', () async {
      final transport = _FakeTransport([_ok(_groundedJson)]);

      final result = await _service(transport).fetchTips(_record());

      expect(result, isA<ResearchSuccess>());
      final tips = (result as ResearchSuccess).tips;
      expect(tips.status, ManagementTipsStatus.grounded);
      expect(tips.tips, hasLength(1));
      expect(tips.tips.first.citations, [0]);
      expect(tips.sources.first.publisher, 'Embrapa');
    });

    test('returns_abstained_success_for_abstained_body', () async {
      final transport = _FakeTransport([_ok(_abstainedJson)]);

      final result = await _service(transport).fetchTips(_record());

      expect(result, isA<ResearchSuccess>());
      expect((result as ResearchSuccess).tips.status,
          ManagementTipsStatus.abstained);
      expect(result.tips.tips, isEmpty);
    });

    test('maps_401_to_unauthenticated', () async {
      final transport = _FakeTransport([_status(401)]);

      final result = await _service(transport).fetchTips(_record());

      expect(result, isA<ResearchFailure>());
      expect((result as ResearchFailure).kind,
          ResearchFailureKind.unauthenticated);
      expect(result.statusCode, 401);
      expect(transport.callCount, 1); // auth failure is not retried
    });

    test('maps_429_to_rate_limited', () async {
      final transport = _FakeTransport([_status(429)]);

      final result = await _service(transport).fetchTips(_record());

      expect((result as ResearchFailure).kind, ResearchFailureKind.rateLimited);
      expect(result.statusCode, 429);
      expect(transport.callCount, 1); // rate limit is not retried
    });

    test('maps_503_to_upstream_unavailable_after_retries', () async {
      final transport = _FakeTransport([_status(503)]);

      final result = await _service(transport).fetchTips(_record());

      expect((result as ResearchFailure).kind,
          ResearchFailureKind.upstreamUnavailable);
      expect(result.statusCode, 503);
      expect(transport.callCount, 3); // transient: retried to exhaustion
    });

    test('returns_timeout_failure_when_request_times_out', () async {
      final transport = _FakeTransport([TimeoutException('slow')]);

      final result = await _service(transport).fetchTips(_record());

      expect((result as ResearchFailure).kind, ResearchFailureKind.timeout);
      expect(transport.callCount, 3);
    });

    test('returns_network_failure_on_connection_error', () async {
      final transport = _FakeTransport([Exception('socket down')]);

      final result = await _service(transport).fetchTips(_record());

      expect((result as ResearchFailure).kind, ResearchFailureKind.network);
      expect(transport.callCount, 3);
    });

    test('retries_transient_failure_then_succeeds', () async {
      final transport = _FakeTransport([_status(503), _ok(_groundedJson)]);

      final result = await _service(transport).fetchTips(_record());

      expect(result, isA<ResearchSuccess>());
      expect(transport.callCount, 2);
    });

    test('returns_failure_after_retries_exhausted', () async {
      final transport = _FakeTransport([_status(503)]);

      final result = await _service(transport).fetchTips(_record());

      expect(result, isA<ResearchFailure>());
      expect(transport.callCount, 3);
    });

    test('returns_invalid_record_failure_when_uuid_missing', () async {
      final transport = _FakeTransport([_ok(_groundedJson)]);

      final result = await _service(transport).fetchTips(_record(uuid: null));

      expect((result as ResearchFailure).kind, ResearchFailureKind.invalidRecord);
      expect(transport.callCount, 0); // no network call attempted
    });

    test('returns_invalid_record_failure_when_texture_missing', () async {
      final transport = _FakeTransport([_ok(_groundedJson)]);

      final result =
          await _service(transport).fetchTips(_record(textureClass: null));

      expect((result as ResearchFailure).kind, ResearchFailureKind.invalidRecord);
      expect(transport.callCount, 0);
    });

    test('omits_authorization_header_when_token_is_null', () async {
      final transport = _FakeTransport([_ok(_groundedJson)]);

      await _service(transport).fetchTips(_record());

      expect(transport.captured.single.headers.containsKey('Authorization'),
          isFalse);
    });

    test('sets_bearer_when_token_present', () async {
      final transport = _FakeTransport([_ok(_groundedJson)]);

      await _service(transport, tokenProvider: () async => 'tok-123')
          .fetchTips(_record());

      expect(transport.captured.single.headers['Authorization'],
          'Bearer tok-123');
    });

    test('returns_unauthenticated_when_token_provider_throws', () async {
      final transport = _FakeTransport([_ok(_groundedJson)]);
      final service = _service(
        transport,
        tokenProvider: () => Future<String?>.error(Exception('storage broken')),
      );

      final result = await service.fetchTips(_record());

      expect((result as ResearchFailure).kind,
          ResearchFailureKind.unauthenticated);
      expect(transport.callCount, 0); // failed before any network call
    });

    test('surfaces_malformed_body_as_typed_failure', () async {
      final transport = _FakeTransport([_ok('not json {{')]);

      final result = await _service(transport).fetchTips(_record());

      expect((result as ResearchFailure).kind,
          ResearchFailureKind.malformedResponse);
      expect(transport.callCount, 1); // contract violation, not retried
    });

    test('returns_malformed_failure_for_empty_200_body', () async {
      final transport = _FakeTransport([_ok('')]);

      final result = await _service(transport).fetchTips(_record());

      expect((result as ResearchFailure).kind,
          ResearchFailureKind.malformedResponse);
      expect(transport.callCount, 1);
    });

    test('does_not_retry_unexpected_4xx', () async {
      final transport = _FakeTransport([_status(400)]);

      final result = await _service(transport).fetchTips(_record());

      expect(result, isA<ResearchFailure>());
      expect((result as ResearchFailure).statusCode, 400);
      expect(transport.callCount, 1); // a 4xx is not fixed by retrying
    });
  });
}
