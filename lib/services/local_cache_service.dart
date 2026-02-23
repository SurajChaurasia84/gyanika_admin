import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

class LocalCacheService {
  LocalCacheService._();

  static const String _boxName = 'admin_settings';

  static Box<dynamic> get _box => Hive.box(_boxName);

  static Future<void> saveJson(String key, Object value) async {
    await _box.put(key, jsonEncode(value));
  }

  static Map<String, dynamic>? getJsonMap(String key) {
    final raw = _box.get(key);
    if (raw is! String || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  static List<Map<String, dynamic>> getJsonList(String key) {
    final raw = _box.get(key);
    if (raw is! String || raw.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
