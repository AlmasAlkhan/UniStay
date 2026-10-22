import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int? status;
  const ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

String errorText(dynamic value) {
  if (value is Map) {
    return value.entries
        .map(
          (e) => e.key == 'detail' || e.key == 'non_field_errors'
              ? errorText(e.value)
              : '${e.key}: ${errorText(e.value)}',
        )
        .join('\n');
  }
  if (value is List) return value.map(errorText).join('\n');
  return value.toString();
}

class ApiClient {
  final http.Client client;
  final String baseUrl;
  String? token;
  VoidCallback? onUnauthorized;
  ApiClient({http.Client? client, required String baseUrl})
    : client = client ?? http.Client(),
      baseUrl = normalizeUrl(baseUrl);
  static String normalizeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiException('Укажите адрес сервера: https://example.com');
    }
    if (kReleaseMode && uri.scheme != 'https') {
      throw const ApiException('Для release-сборки нужен сервер с HTTPS.');
    }
    return value
        .trim()
        .replaceFirst(RegExp(r'/api/v1/?$'), '')
        .replaceFirst(RegExp(r'/+$'), '');
  }

  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/$path',
    ).replace(queryParameters: query);
    final sentToken = authenticated ? token : null;
    final req = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (sentToken != null) 'Authorization': 'Bearer $sentToken',
      });
    if (body != null) req.body = jsonEncode(body);
    try {
      final res = await (() async => http.Response.fromStream(
        await client.send(req),
      ))().timeout(const Duration(seconds: 20));
      dynamic data;
      if (res.body.isNotEmpty) {
        try {
          data = jsonDecode(utf8.decode(res.bodyBytes));
        } on FormatException {
          throw ApiException(
            'Сервер вернул некорректный ответ (${res.statusCode}).',
            res.statusCode,
          );
        }
      }
      if (res.statusCode >= 400) {
        if (res.statusCode == 401 && sentToken != null && sentToken == token) {
          onUnauthorized?.call();
        }
        throw ApiException(
          data is Map
              ? errorText(data['error']?['details'] ?? data)
              : 'Ошибка сервера (${res.statusCode}).',
          res.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiException(
        'Сервер не ответил за 20 секунд. Проверьте подключение и повторите попытку.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Не удалось подключиться к серверу. Проверьте интернет и адрес API в настройках.',
      );
    }
  }

  Future<Json> object(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async => Map<String, dynamic>.from(
    await request(
          method,
          path,
          body: body,
          query: query,
          authenticated: authenticated,
        )
        as Map,
  );
  String imageUrl(String path) =>
      Uri.parse('$baseUrl/').resolve(path).toString();
  void close() => client.close();
}

abstract class SessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class AppState extends ChangeNotifier {
  ApiClient api;
  final SessionStore store;
  Json? user;
  bool ready = false;
  String? startupError, notice;
  int revision = 0;
  AppState({required this.api, required this.store}) {
    _bind();
  }
  bool get isStudent => user?['role'] == 'student';
  bool get verified => user?['email_verified'] == true;
  Json get profile => Map<String, dynamic>.from(user?['profile'] ?? {});
  bool get profileComplete =>
      [
        'university',
        'schedule',
        'cleanliness',
      ].every((k) => (profile[k] ?? '').toString().isNotEmpty) &&
      profile['smoking'] != null;
  String get sessionKey => 'session:${api.baseUrl}';
  void _bind() {
    api.onUnauthorized = () {
      unawaited(expire());
    };
  }

  Future<void> initialize() async {
    startupError = null;
    try {
      final saved = await store.read('server');
      if (saved != null && saved != api.baseUrl) {
        api.close();
        api = ApiClient(baseUrl: saved);
        _bind();
      }
      final session = await store.read(sessionKey);
      if (session != null) {
        final data = jsonDecode(session) as Json;
        if (DateTime.parse(data['expires_at']).isAfter(DateTime.now())) {
          api.token = data['token'];
          await refreshUser();
        } else {
          await store.delete(sessionKey);
        }
      }
    } catch (e) {
      startupError = e is ApiException
          ? e.message
          : 'Не удалось восстановить сессию. Повторите попытку или войдите заново.';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    user = await api.object('GET', 'me/');
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await api.object(
      'POST',
      'auth/login/',
      body: {'email': email.trim(), 'password': password},
      authenticated: false,
    );
    try {
      await store.write(
        sessionKey,
        jsonEncode({'token': data['token'], 'expires_at': data['expires_at']}),
      );
    } catch (_) {
      throw const ApiException(
        'Не удалось безопасно сохранить сессию на устройстве.',
      );
    }
    api.token = data['token'];
    user = Map<String, dynamic>.from(data['user']);
    notice = null;
    startupError = null;
    changed();
  }

  Future<void> expire() async {
    api.token = null;
    user = null;
    notice = 'Сессия истекла. Войдите снова.';
    changed();
    try {
      await store.delete(sessionKey);
    } catch (_) {
      /* The token is invalid on the server. */
    }
  }

  Future<void> logout() async {
    if (api.token != null) await api.request('POST', 'auth/logout/');
    await store.delete(sessionKey);
    api.token = null;
    user = null;
    startupError = null;
    changed();
  }

  Future<void> forgetSession() async {
    await store.delete(sessionKey);
    api.token = null;
    user = null;
    startupError = null;
    changed();
  }

  Future<void> changeServer(String value) async {
    final url = ApiClient.normalizeUrl(value);
    if (url == api.baseUrl) return;
    await store.write('server', url);
    // Tokens are scoped to a server and never forwarded to a new host.
    api.close();
    api = ApiClient(baseUrl: url);
    _bind();
    user = null;
    startupError = null;
    notice = null;
    changed();
  }

  void changed() {
    revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }
}

class PageData {
  final List<Json> items;
  final bool hasNext;
  final int count;
  PageData.fromJson(Json json)
    : items = (json['results'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      hasNext = json['next'] != null,
      count = json['count'] as int;
}

const statusLabels = {
  'pending': 'На рассмотрении',
  'accepted': 'Принята',
  'rejected': 'Отклонена',
  'cancelled': 'Отменена',
};
const preferenceLabels = {
  'schedule': 'Режим сна',
  'smoking': 'Курение',
  'cleanliness': 'Чистоплотность',
};
String listingCount(int count) {
  final lastTwo = count % 100, last = count % 10;
  final noun = lastTwo >= 11 && lastTwo <= 14
      ? 'объявлений'
      : last == 1
      ? 'объявление'
      : last >= 2 && last <= 4
      ? 'объявления'
      : 'объявлений';
  return '$count $noun';
}

String money(dynamic value) {
  final n = double.tryParse(value.toString());
  if (n == null) return '—';
  return '${n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} ₸';
}

String dateLabel(dynamic value) {
  final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return d == null
      ? 'Не указана'
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
