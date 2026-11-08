import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/models/tryout_schedule_model.dart';

/// Layanan penyimpanan & caching offline butir soal & subtest ujian.
/// Mengurangi beban server Firestore/GAS dan menjamin pembukaan soal super cepat (< 50ms).
class ExamCacheService {
  ExamCacheService._();
  static final ExamCacheService instance = ExamCacheService._();

  static const String _kCachedPackagesListKey = 'examgo_offline_cached_packages';
  static const String _kPkgPrefix = 'exam_pkg_cache_';
  static const String _kStPrefix = 'exam_st_cache_';
  static const String _kQPrefix = 'exam_questions_cache_';
  static const String _kCachedAtPrefix = 'exam_cached_at_';

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

  /// Cek apakah paket soal sudah tersimpan di penyimpanan lokal HP
  Future<bool> isExamCached(String paketId) async {
    final cleanId = paketId.trim().toUpperCase();
    final rawId = paketId.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasUpper = prefs.containsKey('$_kQPrefix$cleanId');
      if (hasUpper) {
        final qStr = prefs.getString('$_kQPrefix$cleanId');
        if (qStr != null && qStr.length > 10) return true;
      }
      if (rawId != cleanId && prefs.containsKey('$_kQPrefix$rawId')) {
        final qStr = prefs.getString('$_kQPrefix$rawId');
        if (qStr != null && qStr.length > 10) return true;
      }
    } catch (_) {}
    return false;
  }

  /// Daftar ID paket yang sudah terunduh offline
  Future<List<String>> getCachedPackageIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kCachedPackagesListKey) ?? [];
      // Verifikasi ulang bahwa data soal benar-benar masih ada
      final valid = <String>[];
      for (final id in list) {
        final qStr = prefs.getString('$_kQPrefix$id');
        if (qStr != null && qStr.length > 10) {
          valid.add(id);
        }
      }
      return valid;
    } catch (_) {
      return [];
    }
  }

  /// Memuat paket ujian langsung dari penyimpanan lokal (< 50ms)
  Future<({ExamPackage? package, List<ExamSubtest> subtests, List<ExamQuestion> questions})?> loadExam(
    String paketId,
  ) async {
    final cleanId = paketId.trim().toUpperCase();
    final rawId = paketId.trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      var qStr = prefs.getString('$_kQPrefix$cleanId');
      var targetId = cleanId;
      if ((qStr == null || qStr.isEmpty) && rawId != cleanId) {
        qStr = prefs.getString('$_kQPrefix$rawId');
        targetId = rawId;
      }

      if (qStr == null || qStr.isEmpty) return null;

      final qDecoded = jsonDecode(qStr) as List;
      final questions = qDecoded
          .map((item) => ExamQuestion.fromFirestore(item as Map<String, dynamic>, item['soal_id']?.toString() ?? ''))
          .toList();
      if (questions.isEmpty) return null;

      ExamPackage? package;
      final pkgStr = prefs.getString('$_kPkgPrefix$targetId');
      if (pkgStr != null && pkgStr.isNotEmpty) {
        package = ExamPackage.fromFirestore(jsonDecode(pkgStr) as Map<String, dynamic>, targetId);
      }

      final List<ExamSubtest> subtests = [];
      final stStr = prefs.getString('$_kStPrefix$targetId');
      if (stStr != null && stStr.isNotEmpty) {
        final stDecoded = jsonDecode(stStr) as List;
        subtests.addAll(
          stDecoded.map((item) => ExamSubtest.fromFirestore(item as Map<String, dynamic>, item['subtest_id']?.toString() ?? '')),
        );
      }

      return (package: package, subtests: subtests, questions: questions);
    } catch (e) {
      debugPrint('[ExamCacheService] Gagal memuat dari cache: $e');
      return null;
    }
  }

  /// Menyimpan paket ujian ke penyimpanan lokal secara permanen
  Future<void> saveExam({
    required String paketId,
    ExamPackage? package,
    required List<ExamSubtest> subtests,
    required List<ExamQuestion> questions,
  }) async {
    final cleanId = paketId.trim().toUpperCase();
    try {
      final prefs = await SharedPreferences.getInstance();

      if (package != null) {
        await prefs.setString('$_kPkgPrefix$cleanId', jsonEncode(package.toFirestore()));
      }
      if (subtests.isNotEmpty) {
        final stList = subtests.map((s) => s.toFirestore()).toList();
        await prefs.setString('$_kStPrefix$cleanId', jsonEncode(stList));
      }
      final qList = questions.map((q) => q.toFirestore()).toList();
      await prefs.setString('$_kQPrefix$cleanId', jsonEncode(qList));
      await prefs.setString('$_kCachedAtPrefix$cleanId', DateTime.now().toIso8601String());

      // Update daftar ID paket ter-cache
      final currentList = prefs.getStringList(_kCachedPackagesListKey) ?? [];
      if (!currentList.contains(cleanId)) {
        currentList.add(cleanId);
        await prefs.setStringList(_kCachedPackagesListKey, currentList);
      }
      debugPrint('[ExamCacheService] Sukses menyimpan cache offline untuk $cleanId (${questions.length} butir soal)');
    } catch (e) {
      debugPrint('[ExamCacheService] Gagal menyimpan cache: $e');
    }
  }

  /// Menghapus cache paket ujian tertentu dari HP
  Future<void> removeExamCache(String paketId) async {
    final cleanId = paketId.trim().toUpperCase();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kPkgPrefix$cleanId');
      await prefs.remove('$_kStPrefix$cleanId');
      await prefs.remove('$_kQPrefix$cleanId');
      await prefs.remove('$_kCachedAtPrefix$cleanId');

      final currentList = prefs.getStringList(_kCachedPackagesListKey) ?? [];
      currentList.remove(cleanId);
      await prefs.setStringList(_kCachedPackagesListKey, currentList);
    } catch (_) {}
  }

  /// Mengunduh data paket & soal dari Firestore / GAS dengan laporan progress real-time,
  /// kemudian menyimpannya ke cache lokal HP.
  Future<({ExamPackage? package, List<ExamSubtest> subtests, List<ExamQuestion> questions})> downloadAndCacheExam({
    required String paketId,
    TryoutSchedule? initialSchedule,
    void Function(String message, double progress)? onProgress,
    bool forceRefresh = false,
  }) async {
    final tokenUpper = paketId.trim().toUpperCase();
    final tokenRaw = paketId.trim();

    // 1. Cek apakah sudah tersimpan di cache lokal
    if (!forceRefresh) {
      onProgress?.call('Memeriksa penyimpanan lokal perangkat...', 0.1);
      final cached = await loadExam(tokenUpper);
      if (cached != null && cached.questions.isNotEmpty) {
        onProgress?.call('Soal siap dibuka dari penyimpanan lokal!', 1.0);
        return cached;
      }
    }

    ExamPackage? package;
    if (initialSchedule != null) {
      package = ExamPackage(
        paketId: initialSchedule.paketId,
        namaPaket: initialSchedule.namaPaket,
        kategori: initialSchedule.jenisTest,
        jenisWaktu: initialSchedule.jenisWaktu,
        durasiMenit: initialSchedule.durasiMenit,
      );
    }

    List<ExamSubtest> loadedSubtests = [];
    List<ExamQuestion> loadedQuestions = [];

    // 2. Unduh langsung dari Cloud Firestore
    onProgress?.call('Menghubungkan ke Cloud Firestore...', 0.25);
    final db = _db;
    if (db != null) {
      try {
        final targetIds = [tokenUpper, if (tokenRaw != tokenUpper) tokenRaw];

        onProgress?.call('Mengunduh struktur paket & subtest dari Firestore...', 0.40);
        final results = await Future.wait([
          package != null
              ? Future.value(null)
              : db.collection('paket_tryout').doc(tokenUpper).get().timeout(const Duration(milliseconds: 4000)),
          db.collection('subtest').where('paket_id', whereIn: targetIds).get().timeout(const Duration(milliseconds: 4000)),
          db.collection('tryout_soal').where('paket_id', whereIn: targetIds).get().timeout(const Duration(milliseconds: 4000)),
        ]);

        final pkgDocSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>?;
        final stSnap = results[1] as QuerySnapshot<Map<String, dynamic>>?;
        final qSnap = results[2] as QuerySnapshot<Map<String, dynamic>>?;

        if (package == null && pkgDocSnap != null && pkgDocSnap.exists && pkgDocSnap.data() != null) {
          package = ExamPackage.fromFirestore(pkgDocSnap.data()!, pkgDocSnap.id);
        }

        final stDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (stSnap != null && stSnap.docs.isNotEmpty) {
          stDocs.addAll(stSnap.docs);
        }

        final qDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final seenQIds = <String>{};
        if (qSnap != null && qSnap.docs.isNotEmpty) {
          for (final d in qSnap.docs) {
            if (seenQIds.add(d.id)) qDocs.add(d);
          }
        }

        loadedSubtests = stDocs.map((d) => ExamSubtest.fromFirestore(d.data(), d.id)).toList();
        loadedSubtests.sort((a, b) {
          if (a.orderIndex != 0 || b.orderIndex != 0) {
            final cmp = a.orderIndex.compareTo(b.orderIndex);
            if (cmp != 0) return cmp;
          }
          return a.subtestId.compareTo(b.subtestId);
        });

        // Jika soal by paket_id kosong tapi subtest ada, query tryout_soal by subtest_id
        if (qDocs.isEmpty && loadedSubtests.isNotEmpty) {
          onProgress?.call('Mengunduh butir soal per subtest...', 0.60);
          final subtestIds = loadedSubtests.map((s) => s.subtestId).where((id) => id.isNotEmpty).toList();
          final List<Future<QuerySnapshot<Map<String, dynamic>>>> chunkFutures = [];
          for (var i = 0; i < subtestIds.length; i += 10) {
            final chunk = subtestIds.sublist(i, (i + 10 > subtestIds.length) ? subtestIds.length : i + 10);
            chunkFutures.add(
              db.collection('tryout_soal').where('subtest_id', whereIn: chunk).get().timeout(const Duration(milliseconds: 4000)),
            );
          }
          final chunkSnapshots = await Future.wait(chunkFutures);
          for (final sSnap in chunkSnapshots) {
            for (final d in sSnap.docs) {
              if (seenQIds.add(d.id)) qDocs.add(d);
            }
          }
        }

        loadedQuestions = qDocs.map((d) => ExamQuestion.fromFirestore(d.data(), d.id)).toList();
      } catch (fsErr) {
        debugPrint('[ExamCacheService] Query Firestore gagal/timeout: $fsErr');
      }
    }

    // 3. Fallback ke Google Apps Script backend jika Firestore kosong
    if (loadedQuestions.isEmpty) {
      onProgress?.call('Menghubungkan ke server cadangan...', 0.70);
      var gasData = await _fetchQuestionsFromGas(tokenUpper);
      if (gasData == null && tokenRaw != tokenUpper) {
        gasData = await _fetchQuestionsFromGas(tokenRaw);
      }

      if (gasData != null) {
        if (package == null && gasData['paket'] != null) {
          final pMap = gasData['paket'] as Map<String, dynamic>;
          package = ExamPackage(
            paketId: pMap['paket_id']?.toString() ?? tokenUpper,
            namaPaket: pMap['nama_paket']?.toString() ?? 'Tryout $tokenUpper',
            kategori: pMap['jenis_test']?.toString() ?? ExamCategory.umum,
            jenisWaktu: pMap['jenis_waktu']?.toString() ?? 'per_subtest',
            durasiMenit: (pMap['durasi_menit'] as num?)?.toInt() ?? 90,
          );
        }

        if (gasData['subtests'] is List) {
          final stList = gasData['subtests'] as List;
          loadedSubtests = stList.map((item) {
            final m = item as Map<String, dynamic>;
            return ExamSubtest(
              subtestId: m['subtest_id']?.toString() ?? 'ST_${DateTime.now().millisecondsSinceEpoch}',
              paketId: m['paket_id']?.toString() ?? tokenUpper,
              judul: m['judul_subtest']?.toString() ?? m['judul']?.toString() ?? 'Subtest',
              durasiMenit: (m['durasi_menit'] as num?)?.toInt() ?? 30,
            );
          }).toList();
          loadedSubtests.sort((a, b) => a.subtestId.compareTo(b.subtestId));
        }

        if (gasData['questions'] is List) {
          final qList = gasData['questions'] as List;
          int counter = 1;
          loadedQuestions = qList.map((item) {
            final m = item as Map<String, dynamic>;
            final qId = m['soal_id']?.toString() ?? '${tokenUpper}_Q$counter';
            final nSoal = (m['nomor_soal'] as num?)?.toInt() ?? counter++;
            return ExamQuestion(
              soalId: qId,
              subtestId: m['subtest_id']?.toString() ?? '',
              nomorSoal: nSoal,
              pertanyaan: m['pertanyaan']?.toString() ?? '',
              opsiA: m['opsi_a']?.toString() ?? m['a']?.toString() ?? '',
              opsiB: m['opsi_b']?.toString() ?? m['b']?.toString() ?? '',
              opsiC: m['opsi_c']?.toString() ?? m['c']?.toString() ?? '',
              opsiD: m['opsi_d']?.toString() ?? m['d']?.toString() ?? '',
              opsiE: m['opsi_e']?.toString() ?? m['e']?.toString() ?? '',
              gamA: m['gam_a']?.toString() ?? '',
              gamB: m['gam_b']?.toString() ?? '',
              gamC: m['gam_c']?.toString() ?? '',
              gamD: m['gam_d']?.toString() ?? '',
              gamE: m['gam_e']?.toString() ?? '',
              kunci: (m['kunci']?.toString() ?? m['kunci_jawaban']?.toString() ?? 'A').toUpperCase(),
              pembahasan: m['pembahasan']?.toString() ?? '',
              gambar: m['gambar']?.toString() ?? m['gambar_soal']?.toString() ?? '',
              tabel: m['tabel']?.toString() ?? m['baris_tabel']?.toString() ?? '',
            );
          }).toList();
          loadedQuestions.sort((a, b) => a.nomorSoal.compareTo(b.nomorSoal));
        }
      }
    }

    // 4. Jika tetap kosong, lemparkan Exception agar penangan UI mengetahuinya
    if (loadedQuestions.isEmpty) {
      throw Exception('Butir soal untuk paket "$tokenUpper" belum tersedia di server.');
    }

    package ??= ExamPackage(
      paketId: tokenUpper,
      namaPaket: initialSchedule?.namaPaket ?? 'Tryout $tokenUpper',
      kategori: initialSchedule?.jenisTest ?? ExamCategory.umum,
      jenisWaktu: initialSchedule?.jenisWaktu ?? 'per_subtest',
      durasiMenit: initialSchedule?.durasiMenit ?? 90,
    );

    // 5. Simpan ke local storage HP agar pembukaan berikutnya instan & hemat server
    onProgress?.call('Menyimpan ${loadedQuestions.length} butir soal ke penyimpanan perangkat...', 0.90);
    await saveExam(
      paketId: tokenUpper,
      package: package,
      subtests: loadedSubtests,
      questions: loadedQuestions,
    );

    onProgress?.call('Selesai! Membuka lembar ujian...', 1.0);
    return (package: package, subtests: loadedSubtests, questions: loadedQuestions);
  }

  Future<Map<String, dynamic>?> _fetchQuestionsFromGas(String paketId) async {
    final gasUrl = AppConfig.gasUrl;
    final apiKey = AppConfig.gasApiKey;
    if (gasUrl.isEmpty || apiKey.isEmpty) return null;

    try {
      var resp = await http.post(
        Uri.parse(gasUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'apiKey': apiKey,
          'action': 'getSoalTryout',
          'paketId': paketId,
        }),
      ).timeout(const Duration(seconds: 7));

      if (resp.statusCode >= 300 && resp.statusCode < 400 && resp.headers.containsKey('location')) {
        final redirectUrl = resp.headers['location']!;
        resp = await http.get(Uri.parse(redirectUrl)).timeout(const Duration(seconds: 7));
      }

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        if (json['status'] == 'success') {
          return json;
        }
      }
    } catch (_) {}
    return null;
  }
}
