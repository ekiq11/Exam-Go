import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/models/tryout_schedule_model.dart';

/// Layanan pengambilan data jadwal & paket tryout resmi
class TryoutScheduleService {
  TryoutScheduleService._();
  static final TryoutScheduleService instance = TryoutScheduleService._();

  static const String _kCacheKey = 'examgo_cached_tryout_schedules';

  FirebaseFirestore? _firestore;

  FirebaseFirestore? get _db {
    if (_firestore != null) return _firestore;
    try {
      _firestore = FirebaseFirestore.instance;
      return _firestore;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  void setMockFirestore(FirebaseFirestore? mock) {
    _firestore = mock;
  }

  /// Memuat daftar paket tryout aktif (Firestore + fallback GAS + fallback Local Cache)
  Future<List<TryoutSchedule>> getActiveSchedules({bool forceRefresh = false}) async {
    // 1. Coba baca dari Firestore langsung (Realtime & Akurat)
    final db = _db;
    if (db != null) {
      try {
        final snap = await db.collection('paket_tryout').get();
        if (snap.docs.isNotEmpty) {
          final list = snap.docs.map((doc) => TryoutSchedule.fromMap(doc.id, doc.data())).toList();
          final activeList = list.where((t) => t.isActive).toList();
          activeList.sort((a, b) => b.tanggal.compareTo(a.tanggal));
          await _saveToCache(activeList);
          return activeList;
        }
      } catch (_) {}
    }

    // 2. Coba fallback via Google Apps Script backend jika Firestore SDK terblokir
    try {
      final gasList = await _fetchFromGas();
      if (gasList != null && gasList.isNotEmpty) {
        await _saveToCache(gasList);
        return gasList;
      }
    } catch (_) {}

    // 3. Fallback terakhir: Cache lokal
    return _loadFromCache();
  }

  Future<List<TryoutSchedule>?> _fetchFromGas() async {
    final gasUrl = AppConfig.gasUrl;
    final apiKey = AppConfig.gasApiKey;
    if (gasUrl.isEmpty || apiKey.isEmpty) return null;

    try {
      final resp = await http.post(
        Uri.parse(gasUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'apiKey': apiKey,
          'action': 'getJadwalTryout',
        }),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        if (json['data'] is List) {
          final rawList = json['data'] as List;
          return rawList.map((item) {
            final m = item as Map<String, dynamic>;
            final id = m['paket_id']?.toString() ?? 'ID_${DateTime.now().millisecondsSinceEpoch}';
            return TryoutSchedule.fromMap(id, m);
          }).where((t) => t.isActive).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveToCache(List<TryoutSchedule> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mapped = list.map((t) => {'id': t.paketId, ...t.toMap()}).toList();
      await prefs.setString(_kCacheKey, jsonEncode(mapped));
    } catch (_) {}
  }

  Future<List<TryoutSchedule>> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_kCacheKey);
      if (str != null && str.isNotEmpty) {
        final decoded = jsonDecode(str) as List;
        return decoded.map((e) {
          final m = e as Map<String, dynamic>;
          final id = m['id']?.toString() ?? '';
          return TryoutSchedule.fromMap(id, m);
        }).toList();
      }
    } catch (_) {}
    return [];
  }
}

