import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:unistay_mobile/data.dart';

class MemoryStore implements SessionStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

http.Response response(dynamic body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json page(List<Json> items, {String? next, int? count}) => {
  'results': items,
  'count': count ?? items.length,
  'next': next,
  'previous': null,
};
Json student({bool verified = true}) => {
  'id': 1,
  'name': 'Турар',
  'email': 'student@example.test',
  'role': 'student',
  'email_verified': verified,
  'profile': <String, dynamic>{
    'university': 'AITU',
    'bio': '',
    'schedule': 'early',
    'smoking': false,
    'cleanliness': 'tidy',
    'share_with_group': true,
  },
};
Json listing(int id) => {
  'id': id,
  'title': 'Квартира $id',
  'city': 'Астана',
  'district': 'Есиль',
  'university': 'AITU',
  'price': '85000.00',
  'deposit': '30000.00',
  'capacity': 3,
  'occupied': 1,
  'available': 2,
  'utilities_included': true,
  'status': 'published',
  'photos': [],
  'address': null,
  'owner_name': 'Владелец',
  'description': 'Светлая квартира для студентов',
  'move_in_date': '2026-11-01',
};
Json application({String status = 'pending'}) => {
  'id': 10,
  'listing_id': 1,
  'listing_title': 'Квартира 1',
  'student': student(),
  'status': status,
  'message': '',
  'created_at': '2026-10-23T10:00:00Z',
  'events': [
    {'to_status': status, 'created_at': '2026-10-23T10:00:00Z'},
  ],
};
