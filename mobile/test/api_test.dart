import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unistay_mobile/data.dart';
import 'helpers.dart';

void main() {
  test(
    'encodes filters and attaches Bearer only to authenticated requests',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'https://example.test/api/v1/',
        client: MockClient((r) async {
          requests.add(r);
          return response(page([]));
        }),
      )..token = 'test-token';
      await api.object(
        'GET',
        'listings/',
        query: {'city': 'Астана', 'max_price': '90000'},
      );
      await api.object(
        'POST',
        'auth/login/',
        body: {'email': 'a@b.test', 'password': 'password'},
        authenticated: false,
      );
      expect(requests.first.url.path, '/api/v1/listings/');
      expect(requests.first.url.queryParameters['city'], 'Астана');
      expect(requests.first.headers['Authorization'], 'Bearer test-token');
      expect(requests.last.headers.containsKey('Authorization'), false);
      expect(jsonDecode(requests.last.body)['email'], 'a@b.test');
    },
  );
  test(
    'nested validation errors and conflicts preserve server explanation',
    () async {
      final api = ApiClient(
        baseUrl: 'https://example.test',
        client: MockClient(
          (_) async => response({
            'error': {
              'details': {
                'email': ['Уже зарегистрирован'],
              },
            },
          }, 409),
        ),
      );
      await expectLater(
        api.request('POST', 'auth/register/'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 409)
              .having(
                (e) => e.message,
                'message',
                contains('Уже зарегистрирован'),
              ),
        ),
      );
    },
  );
  test('401 expires a protected session, but wrong login does not', () async {
    var expired = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((_) async => response({'detail': 'Expired'}, 401)),
    )..token = 'secret';
    api.onUnauthorized = () => expired++;
    await expectLater(
      api.request('POST', 'auth/login/', authenticated: false),
      throwsA(isA<ApiException>()),
    );
    expect(expired, 0);
    await expectLater(api.request('GET', 'me/'), throwsA(isA<ApiException>()));
    expect(expired, 1);
  });
  test(
    'network errors become actionable messages; no internal exception leaks',
    () async {
      final api = ApiClient(
        baseUrl: 'https://example.test',
        client: MockClient(
          (_) async => throw http.ClientException('socket failed'),
        ),
      );
      await expectLater(
        api.request('GET', 'listings/'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Проверьте интернет'),
          ),
        ),
      );
    },
  );
  test('204 logout response needs no JSON body', () async {
    final api = ApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((_) async => http.Response('', 204)),
    );
    expect(await api.request('POST', 'auth/logout/'), null);
  });
  test(
    'restores unexpired session from secure store through me endpoint',
    () async {
      final store = MemoryStore();
      store.values['session:https://example.test'] = jsonEncode({
        'token': 'saved-token',
        'expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });
      final api = ApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer saved-token');
          return response(student());
        }),
      );
      final state = AppState(api: api, store: store);
      await state.initialize();
      expect(state.user?['name'], 'Турар');
      expect(state.profileComplete, true);
      expect(state.ready, true);
      state.dispose();
    },
  );
  test('expired stored token is discarded without HTTP', () async {
    final store = MemoryStore();
    store.values['session:https://example.test'] = jsonEncode({
      'token': 'expired',
      'expires_at': '2000-01-01T00:00:00Z',
    });
    final state = AppState(
      api: ApiClient(
        baseUrl: 'https://example.test',
        client: MockClient((_) async {
          fail('No request expected');
        }),
      ),
      store: store,
    );
    await state.initialize();
    expect(state.user, null);
    expect(store.values, isEmpty);
    state.dispose();
  });
  test('changing server removes in-memory identity and token', () async {
    final state = AppState(
      api: ApiClient(baseUrl: 'https://old.test')..token = 'old-token',
      store: MemoryStore(),
    )..user = student();
    await state.changeServer('https://new.test');
    expect(state.api.token, null);
    expect(state.user, null);
    expect(state.api.baseUrl, 'https://new.test');
    state.dispose();
  });
  test('missing habits gate application even when university exists', () {
    final state = AppState(
      api: ApiClient(baseUrl: 'https://example.test'),
      store: MemoryStore(),
    )..user = student();
    state.user!['profile']['smoking'] = null;
    expect(state.profileComplete, false);
    state.dispose();
  });
}
