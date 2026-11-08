import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constant/app_colors.dart';
import '../../constant/app_config.dart';
import '../../constant/security_service.dart';
import '../../models/exam_question_model.dart';
import '../../models/tryout_schedule_model.dart';
import '../../services/monitoring_service.dart';
import '../../services/national_exam_evaluator.dart';
import '../../services/student_tryout_history_service.dart';
import '../../utils/math_widget_factory.dart';
import 'tryout_discussion_screen.dart';

class StudentExamSessionScreen extends StatefulWidget {
  final String token;
  final String studentName;
  final String studentNis;
  final bool isEvent;
  final TryoutSchedule? initialSchedule;

  const StudentExamSessionScreen({
    super.key,
    required this.token,
    required this.studentName,
    required this.studentNis,
    this.isEvent = false,
    this.initialSchedule,
  });

  @override
  State<StudentExamSessionScreen> createState() =>
      _StudentExamSessionScreenState();
}

class _StudentExamSessionScreenState extends State<StudentExamSessionScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _errorMessage;

  ExamPackage? _package;
  List<ExamSubtest> _subtests = [];
  final List<ExamQuestion> _allQuestions = [];

  // Index soal aktif relatif terhadap daftar soal aktif
  int _currentIndex = 0;

  // Index subtest yang sedang aktif (khusus mode per_subtest)
  int _currentSubtestIndex = 0;

  // Jawaban siswa: soalId -> opsi ('A'..'E')
  final Map<String, String> _answers = {};

  // Soal yang ditandai ragu-ragu: Set of soalId
  final Set<String> _raguRagu = {};

  // ─── Font Scale Factor (A- / A+) ──────────────────────────────
  double _fontSizeScale =
      1.0; // 0.9 (Kecil), 1.0 (Normal), 1.15 (Sedang), 1.3 (Besar)

  // ─── Wall-Clock Timer State ───────────────────────────────────
  DateTime? _subtestEndTime;
  DateTime? _packageEndTime;
  int _remainingSeconds = 0;
  Timer? _tickerTimer;

  // ─── Anti-Cheat Monitoring State ──────────────────────────────
  int _violations = 0;
  bool _isBlocked = false;
  bool _isSubmitted = false;
  bool _isShowingWarningDialog = false;
  StreamSubscription<DocumentSnapshot>? _statusListener;

  static const int _maxViolations = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersiveMode();
    SecurityService.instance.enable();
    _loadExamData();
    _listenTeacherMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerTimer?.cancel();
    _statusListener?.cancel();
    _exitImmersiveMode();
    SecurityService.instance.disable(force: true);
    if (!_isSubmitted) {
      MonitoringService.instance.updateStudentStatus(
        examId: widget.token,
        nis: widget.studentNis,
        name: widget.studentName,
        status: 'OFFLINE',
        violations: _violations,
      );
    }
    super.dispose();
  }

  void _enterImmersiveMode() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ─── Deteksi Pelanggaran Siswa (Lifecycle) ───────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isSubmitted || _isBlocked) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _violations++;
      _handleViolationDetected();
    } else if (state == AppLifecycleState.resumed) {
      _enterImmersiveMode();
      SecurityService.instance.reapply();
      _checkRemainingTime();
      if (_violations >= _maxViolations) {
        setState(() => _isBlocked = true);
      } else if (_violations > 0 && mounted) {
        _showViolationWarningDialog(_violations);
      }
    }
  }

  void _showViolationWarningDialog(int count) {
    if (_isShowingWarningDialog || !mounted || _isBlocked || _isSubmitted) return;
    _isShowingWarningDialog = true;
    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'PERINGATAN KECURANGAN!',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFDC2626),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                'Pelanggaran ke-$count dari $_maxViolations kali toleransi',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFB45309),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Aplikasi mendeteksi bahwa Anda meninggalkan layar ujian atau membuka aplikasi lain.\n\n'
              '⚠️ Kejadian ini telah OTOMATIS TERCATAT dan DILAPORKAN ke Pengawas Ujian secara real-time.\n\n'
              'Jika Anda melanggar ${_maxViolations - count} kali lagi, perangkat akan DIBLOKIR TOTAL dan ujian dinyatakan GUGUR!',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: const Color(0xFF334155),
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _isShowingWarningDialog = false;
                _enterImmersiveMode();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Saya Mengerti & Kembali Mengerjakan',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    ).then((_) {
      _isShowingWarningDialog = false;
    });
  }

  void _handleViolationDetected() {
    MonitoringService.instance.logActivity(
      examId: widget.token,
      nis: widget.studentNis,
      activityType: 'EXIT_ATTEMPT',
      description:
          'Peserta mencoba keluar dari aplikasi ujian (Pelanggaran ke-$_violations)',
    );

    MonitoringService.instance.updateStudentStatus(
      examId: widget.token,
      nis: widget.studentNis,
      name: widget.studentName,
      status: _violations >= _maxViolations ? 'BLOCKED' : 'ONLINE',
      violations: _violations,
    );
  }

  void _listenTeacherMonitoring() {
    _statusListener = FirebaseFirestore.instance
        .collection('exam_sessions')
        .doc(widget.token)
        .collection('students')
        .doc(widget.studentNis)
        .snapshots()
        .listen((snap) {
          if (!snap.exists) return;
          final data = snap.data();
          if (data == null) return;

          final status = data['status']?.toString();
          if (status == 'BLOCKED' && !_isBlocked) {
            setState(() => _isBlocked = true);
          } else if ((status == 'ONLINE' || status == 'ACTIVE') && _isBlocked) {
            setState(() {
              _isBlocked = false;
              _violations = 0;
            });
            _enterImmersiveMode();
            SecurityService.instance.reapply();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Blokir telah dibuka oleh Pengawas. Silakan lanjutkan pengerjaan.',
                  ),
                  backgroundColor: AppColors.primaryGreen,
                ),
              );
            }
          }
        });
  }

  // ─── Memuat Data Ujian & Resiliensi Multi-Source (Firestore + GAS + Cache Offline) ──
  Future<void> _loadExamData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tokenUpper = widget.token.trim().toUpperCase();
      final tokenRaw = widget.token.trim();

      // Inisialisasi awal metadata paket jika dioper dari halaman jadwal
      if (widget.initialSchedule != null) {
        final sched = widget.initialSchedule!;
        _package = ExamPackage(
          paketId: sched.paketId,
          namaPaket: sched.namaPaket,
          kategori: sched.jenisTest,
          jenisWaktu: sched.jenisWaktu,
          durasiMenit: sched.durasiMenit,
        );
      }

      List<ExamSubtest> loadedSubtests = [];
      List<ExamQuestion> loadedQuestions = [];

      // ── TAHAP 1: Query Firestore (Multi-Query Resilience seperti myOLCv2) ──
      try {
        final db = FirebaseFirestore.instance;

        // 1. Ambil dokumen paket_tryout jika belum ada
        if (_package == null) {
          DocumentSnapshot<Map<String, dynamic>>? pkgDoc;
          final d1 = await db.collection('paket_tryout').doc(tokenUpper).get().timeout(const Duration(seconds: 8));
          if (d1.exists) {
            pkgDoc = d1;
          } else {
            final d2 = await db.collection('paket_tryout').doc(tokenRaw).get().timeout(const Duration(seconds: 8));
            if (d2.exists) {
              pkgDoc = d2;
            } else {
              final q1 = await db.collection('paket_tryout').where('paket_id', isEqualTo: tokenUpper).limit(1).get().timeout(const Duration(seconds: 8));
              if (q1.docs.isNotEmpty) pkgDoc = q1.docs.first;
            }
          }

          if (pkgDoc != null && pkgDoc.data() != null) {
            _package = ExamPackage.fromFirestore(pkgDoc.data()!, pkgDoc.id);
          }
        }

        // 2. Ambil subtests
        final stDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final stSnap1 = await db.collection('subtest').where('paket_id', isEqualTo: tokenUpper).get().timeout(const Duration(seconds: 8));
        stDocs.addAll(stSnap1.docs);

        if (stDocs.isEmpty && tokenRaw != tokenUpper) {
          final stSnap2 = await db.collection('subtest').where('paket_id', isEqualTo: tokenRaw).get().timeout(const Duration(seconds: 8));
          stDocs.addAll(stSnap2.docs);
        }

        loadedSubtests = stDocs.map((d) => ExamSubtest.fromFirestore(d.data(), d.id)).toList();
        loadedSubtests.sort((a, b) => a.subtestId.compareTo(b.subtestId));

        // 3. Ambil butir tryout_soal (Kombinasi subtest_id chunk dan paket_id)
        final qDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final seenQIds = <String>{};

        // (a) Query berdasarkan subtest_id (Identik dengan myOLCv2)
        final subtestIds = loadedSubtests.map((s) => s.subtestId).where((id) => id.isNotEmpty).toList();
        if (subtestIds.isNotEmpty) {
          for (var i = 0; i < subtestIds.length; i += 10) {
            final chunk = subtestIds.sublist(i, (i + 10 > subtestIds.length) ? subtestIds.length : i + 10);
            final sSnap = await db.collection('tryout_soal').where('subtest_id', whereIn: chunk).get().timeout(const Duration(seconds: 10));
            for (final d in sSnap.docs) {
              if (seenQIds.add(d.id)) qDocs.add(d);
            }
          }
        }

        // (b) Query berdasarkan paket_id
        final qSnapPkg = await db.collection('tryout_soal').where('paket_id', isEqualTo: tokenUpper).get().timeout(const Duration(seconds: 10));
        for (final d in qSnapPkg.docs) {
          if (seenQIds.add(d.id)) qDocs.add(d);
        }

        if (qDocs.isEmpty && tokenRaw != tokenUpper) {
          final qSnapPkg2 = await db.collection('tryout_soal').where('paket_id', isEqualTo: tokenRaw).get().timeout(const Duration(seconds: 10));
          for (final d in qSnapPkg2.docs) {
            if (seenQIds.add(d.id)) qDocs.add(d);
          }
        }

        loadedQuestions = qDocs.map((d) => ExamQuestion.fromFirestore(d.data(), d.id)).toList();
        loadedQuestions.sort((a, b) => a.nomorSoal.compareTo(b.nomorSoal));
      } catch (fsErr) {
        debugPrint('[StudentExam] Firestore query failed: $fsErr');
      }

      // ── TAHAP 2: Fallback ke Backend Google Apps Script jika Firestore kosong ──
      if (loadedQuestions.isEmpty) {
        debugPrint('[StudentExam] Firestore soal kosong untuk paket $tokenUpper, menghubungi backend GAS...');
        final gasData = await _fetchQuestionsFromGas(tokenUpper);
        if (gasData != null) {
          if (_package == null && gasData['paket'] != null) {
            final pMap = gasData['paket'] as Map<String, dynamic>;
            _package = ExamPackage(
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

      // ── TAHAP 3: Fallback ke Cache Offline ──
      if (loadedQuestions.isEmpty) {
        final cached = await _loadQuestionsFromOfflineCache(tokenUpper);
        if (cached != null && cached.isNotEmpty) {
          loadedQuestions = cached;
        }
      }

      // ── Validasi Hasil Akhir ──
      if (loadedQuestions.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Soal ujian untuk paket "$tokenUpper" belum tersedia atau sedang disiapkan oleh Admin.';
        });
        return;
      }

      // Pastikan objek _package selalu terisi
      _package ??= ExamPackage(
        paketId: tokenUpper,
        namaPaket: widget.initialSchedule?.namaPaket ?? 'Tryout $tokenUpper',
        kategori: widget.initialSchedule?.jenisTest ?? ExamCategory.umum,
        jenisWaktu: widget.initialSchedule?.jenisWaktu ?? 'per_subtest',
        durasiMenit: widget.initialSchedule?.durasiMenit ?? 90,
      );

      // Asosiasikan butir soal ke masing-masing subtest
      if (loadedSubtests.isNotEmpty) {
        for (final st in loadedSubtests) {
          st.soalList = loadedQuestions.where((q) {
            return q.subtestId == st.subtestId || q.subtestId.toUpperCase() == st.subtestId.toUpperCase();
          }).toList();
        }
        final orphans = loadedQuestions.where((q) => !loadedSubtests.any((st) => st.soalList.contains(q))).toList();
        if (orphans.isNotEmpty && loadedSubtests.isNotEmpty) {
          loadedSubtests.first.soalList.addAll(orphans);
        }
        _subtests = loadedSubtests;
      } else {
        _subtests = [
          ExamSubtest(
            subtestId: 'ST1',
            paketId: tokenUpper,
            judul: 'Soal Ujian',
            durasiMenit: _package!.durasiMenit,
            soalList: loadedQuestions,
          ),
        ];
      }

      _allQuestions.clear();
      _allQuestions.addAll(loadedQuestions);

      // Simpan ke Cache Offline
      await _saveQuestionsToOfflineCache(tokenUpper, loadedQuestions);

      // Pulihkan jawaban & status dari cache lokal siswa
      await _restoreLocalCache();

      // Inisialisasi Timer
      await _initTimer();

      // Daftarkan siswa ke sesi monitoring pengawas
      await MonitoringService.instance.updateStudentStatus(
        examId: widget.token,
        nis: widget.studentNis,
        name: widget.studentName,
        status: 'ONLINE',
        violations: 0,
      );

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Terjadi kesalahan saat memuat soal ujian: $e';
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchQuestionsFromGas(String paketId) async {
    final gasUrl = AppConfig.gasUrl;
    final apiKey = AppConfig.gasApiKey;
    if (gasUrl.isEmpty || apiKey.isEmpty) return null;

    try {
      final resp = await http.post(
        Uri.parse(gasUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'apiKey': apiKey,
          'action': 'getSoalTryout',
          'paketId': paketId,
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        if (json['status'] == 'success') {
          return json;
        }
      }
    } catch (e) {
      debugPrint('[StudentExam] Error fetching questions from GAS: $e');
    }
    return null;
  }

  Future<void> _saveQuestionsToOfflineCache(String paketId, List<ExamQuestion> questions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'exam_questions_cache_$paketId';
      final list = questions.map((q) => q.toFirestore()).toList();
      await prefs.setString(key, jsonEncode(list));
    } catch (_) {}
  }

  Future<List<ExamQuestion>?> _loadQuestionsFromOfflineCache(String paketId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'exam_questions_cache_$paketId';
      final str = prefs.getString(key);
      if (str != null && str.isNotEmpty) {
        final decoded = jsonDecode(str) as List;
        return decoded.map((item) => ExamQuestion.fromFirestore(item as Map<String, dynamic>, item['soal_id']?.toString() ?? '')).toList();
      }
    } catch (_) {}
    return null;
  }

  // ─── Cache Lokal Otomatis (Auto-Save Jawaban) ──────────────────
  Future<void> _restoreLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final ansKey = 'exam_ans_${widget.token}_${widget.studentNis}';
    final raguKey = 'exam_ragu_${widget.token}_${widget.studentNis}';
    final stIdxKey = 'exam_st_idx_${widget.token}_${widget.studentNis}';
    final qIdxKey = 'exam_q_idx_${widget.token}_${widget.studentNis}';

    final savedAnsJson = prefs.getString(ansKey);
    if (savedAnsJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(savedAnsJson);
        decoded.forEach((k, v) => _answers[k] = v.toString());
      } catch (_) {}
    }

    final savedRaguList = prefs.getStringList(raguKey);
    if (savedRaguList != null) {
      _raguRagu.addAll(savedRaguList);
    }

    _currentSubtestIndex = prefs.getInt(stIdxKey) ?? 0;
    if (_currentSubtestIndex >= _subtests.length) {
      _currentSubtestIndex = _subtests.length - 1;
    }

    _currentIndex = prefs.getInt(qIdxKey) ?? 0;
    final activeSoalCount = _getActiveQuestions().length;
    if (_currentIndex >= activeSoalCount && activeSoalCount > 0) {
      _currentIndex = 0;
    }
  }

  Future<void> _saveSessionToLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    final ansKey = 'exam_ans_${widget.token}_${widget.studentNis}';
    final raguKey = 'exam_ragu_${widget.token}_${widget.studentNis}';
    final stIdxKey = 'exam_st_idx_${widget.token}_${widget.studentNis}';
    final qIdxKey = 'exam_q_idx_${widget.token}_${widget.studentNis}';

    await prefs.setString(ansKey, jsonEncode(_answers));
    await prefs.setStringList(raguKey, _raguRagu.toList());
    await prefs.setInt(stIdxKey, _currentSubtestIndex);
    await prefs.setInt(qIdxKey, _currentIndex);
  }

  Future<void> _clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('exam_ans_${widget.token}_${widget.studentNis}');
    await prefs.remove('exam_ragu_${widget.token}_${widget.studentNis}');
    await prefs.remove('exam_st_idx_${widget.token}_${widget.studentNis}');
    await prefs.remove('exam_q_idx_${widget.token}_${widget.studentNis}');
    await prefs.remove('exam_pkg_end_${widget.token}_${widget.studentNis}');

    for (int i = 0; i < 20; i++) {
      await prefs.remove('exam_st_end_${widget.token}_${widget.studentNis}_$i');
    }
  }

  // ─── Manajemen Timer Per-Subtest & Global ──────────────────────
  bool get _isPerSubtest => _package?.jenisWaktu == 'per_subtest';

  List<ExamQuestion> _getActiveQuestions() {
    if (_subtests.isEmpty) return _allQuestions;
    if (_isPerSubtest) {
      if (_currentSubtestIndex < _subtests.length) {
        final list = _subtests[_currentSubtestIndex].soalList;
        return list.isNotEmpty ? list : _allQuestions;
      }
      return _allQuestions;
    }
    return _allQuestions;
  }

  Future<void> _initTimer() async {
    final prefs = await SharedPreferences.getInstance();

    if (_isPerSubtest) {
      final currentSt = _subtests[_currentSubtestIndex];
      final stEndKey =
          'exam_st_end_${widget.token}_${widget.studentNis}_$_currentSubtestIndex';
      final savedMs = prefs.getInt(stEndKey);

      final now = DateTime.now();
      if (savedMs != null) {
        _subtestEndTime = DateTime.fromMillisecondsSinceEpoch(savedMs);
      } else {
        _subtestEndTime = now.add(Duration(minutes: currentSt.durasiMenit));
        await prefs.setInt(stEndKey, _subtestEndTime!.millisecondsSinceEpoch);
      }
    } else {
      final pkgEndKey = 'exam_pkg_end_${widget.token}_${widget.studentNis}';
      final savedMs = prefs.getInt(pkgEndKey);

      final now = DateTime.now();
      if (savedMs != null) {
        _packageEndTime = DateTime.fromMillisecondsSinceEpoch(savedMs);
      } else {
        _packageEndTime = now.add(Duration(minutes: _package!.durasiMenit));
        await prefs.setInt(pkgEndKey, _packageEndTime!.millisecondsSinceEpoch);
      }
    }

    _checkRemainingTime();

    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkRemainingTime();
    });
  }

  void _checkRemainingTime() {
    final now = DateTime.now();
    final targetTime = _isPerSubtest ? _subtestEndTime : _packageEndTime;

    if (targetTime == null) return;
    final diff = targetTime.difference(now).inSeconds;

    if (diff <= 0) {
      _remainingSeconds = 0;
      if (_isPerSubtest) {
        _handleSubtestTimeExpired();
      } else {
        _tickerTimer?.cancel();
        _submitExam(autoSubmit: true);
      }
    } else {
      setState(() => _remainingSeconds = diff);
      // Heartbeat hemat kuota: update status ONLINE setiap 45 detik selama siswa aktif ujian
      if (diff > 0 && diff % 45 == 0 && !_isBlocked && !_isSubmitted) {
        MonitoringService.instance.updateStudentStatus(
          examId: widget.token,
          nis: widget.studentNis,
          name: widget.studentName,
          status: 'ONLINE',
          violations: _violations,
        );
      }
    }
  }

  /// Penanganan waktu habis pada mode per-subtest
  void _handleSubtestTimeExpired() {
    if (_currentSubtestIndex < _subtests.length - 1) {
      final expiredTitle = _subtests[_currentSubtestIndex].judul;
      setState(() {
        _currentSubtestIndex++;
        _currentIndex = 0;
      });

      _initTimer();
      _saveSessionToLocalCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.lock_clock_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Waktu subtest "$expiredTitle" telah habis. Memulai: ${_subtests[_currentSubtestIndex].judul}',
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFD97706),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } else {
      // Subtest terakhir habis -> kumpulkan otomatis
      _tickerTimer?.cancel();
      _submitExam(autoSubmit: true);
    }
  }

  String _formatDuration(int totalSecs) {
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // ─── Pengatur Skala Ukuran Teks (A- / A+) ─────────────────────
  void _cycleFontSize() {
    setState(() {
      if (_fontSizeScale == 1.0) {
        _fontSizeScale = 1.15; // Sedang
      } else if (_fontSizeScale == 1.15) {
        _fontSizeScale = 1.30; // Besar
      } else if (_fontSizeScale == 1.30) {
        _fontSizeScale = 0.90; // Kecil
      } else {
        _fontSizeScale = 1.0; // Normal
      }
    });

    final label = _fontSizeScale == 1.30
        ? 'Ukuran Teks: Sangat Besar'
        : _fontSizeScale == 1.15
        ? 'Ukuran Teks: Sedang'
        : _fontSizeScale == 0.90
        ? 'Ukuran Teks: Kecil'
        : 'Ukuran Teks: Normal';

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── Modal Grid Navigasi Nomor Soal (Desain myOLCv2) ───────────
  void _showQuestionGridSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final activeQuestions = _getActiveQuestions();

            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Sheet
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lembar Navigasi Soal',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            if (_isPerSubtest && _subtests.isNotEmpty)
                              Text(
                                'Subtest ${_currentSubtestIndex + 1}/${_subtests.length}: ${_subtests[_currentSubtestIndex].judul}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  color: AppColors.primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF64748B),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Legenda Warna
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildLegendItem('Terjawab', AppColors.primaryGreen),
                          const SizedBox(width: 12),
                          _buildLegendItem(
                            'Ragu-Ragu',
                            const Color(0xFFD97706),
                          ),
                          const SizedBox(width: 12),
                          _buildLegendItem(
                            'Belum Dijawab',
                            const Color(0xFFF1F5F9),
                            textColor: const Color(0xFF475569),
                          ),
                          if (_isPerSubtest) ...[
                            const SizedBox(width: 12),
                            _buildLegendItem(
                              'Terkunci',
                              const Color(0xFFE2E8F0),
                              textColor: const Color(0xFF94A3B8),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 24, color: Color(0xFFE2E8F0)),

                    // Grid Nomor Soal
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.1,
                            ),
                        itemCount: activeQuestions.length,
                        itemBuilder: (context, i) {
                          final q = activeQuestions[i];
                          final isAnswered = _answers.containsKey(q.soalId);
                          final isRagu = _raguRagu.contains(q.soalId);
                          final isCurrent = i == _currentIndex;

                          Color tileBg = const Color(0xFFF8FAFC);
                          Color textClr = const Color(0xFF1E293B);
                          Border border = Border.all(
                            color: const Color(0xFFE2E8F0),
                          );

                          if (isRagu) {
                            tileBg = const Color(0xFFFEF3C7);
                            textClr = const Color(0xFF92400E);
                            border = Border.all(
                              color: const Color(0xFFF59E0B),
                              width: 1.5,
                            );
                          } else if (isAnswered) {
                            tileBg = AppColors.primaryGreen;
                            textClr = Colors.white;
                            border = Border.all(
                              color: AppColors.primaryGreen,
                              width: 1.5,
                            );
                          }

                          if (isCurrent) {
                            border = Border.all(
                              color: const Color(0xFF2563EB),
                              width: 2.2,
                            );
                          }

                          return InkWell(
                            onTap: () {
                              setState(() => _currentIndex = i);
                              _saveSessionToLocalCache();
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: tileBg,
                                borderRadius: BorderRadius.circular(12),
                                border: border,
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Text(
                                      '${q.nomorSoal}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: textClr,
                                      ),
                                    ),
                                  ),
                                  if (isRagu)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFD97706),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLegendItem(
    String label,
    Color color, {
    Color textColor = const Color(0xFF334155),
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 0.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─── Kumpulkan Jawaban Ujian & Kalkulasi Skoring ───────────────
  Future<void> _submitExam({bool autoSubmit = false}) async {
    if (_isSubmitted) return;
    _isSubmitted = true;
    _tickerTimer?.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      ),
    );

    try {
      final category = _package?.kategori ?? ExamCategory.umum;
      final evalResult = NationalExamEvaluator.evaluate(
        category: category,
        subtests: _subtests,
        allQuestions: _allQuestions,
        answers: _answers,
      );

      final docRef = FirebaseFirestore.instance
          .collection('jawaban_tryout')
          .doc('${widget.studentNis}_${widget.token}');

      await docRef.set({
        'token': widget.token,
        'nama_peserta': widget.studentName,
        'nis': widget.studentNis,
        'kategori': category,
        'jumlah_benar': evalResult.totalBenar,
        'jumlah_salah': evalResult.totalSalah,
        'jumlah_kosong': evalResult.totalKosong,
        'total_soal': evalResult.totalSoal,
        'skor_akhir': evalResult.finalScore,
        'max_skor': evalResult.maxScore,
        'is_passed': evalResult.isPassed,
        'status_kelulusan': evalResult.statusKelulusan,
        'predikat': evalResult.predikat,
        'subtest_scores': evalResult.subtests.map((k, v) => MapEntry(k, v.toMap())),
        'jawaban': _answers,
        'violations': _violations,
        'is_blocked': _isBlocked,
        'submitted_at': FieldValue.serverTimestamp(),
        'auto_submitted': autoSubmit,
      });

      // Update status monitoring ke FINISHED
      await MonitoringService.instance.updateStudentStatus(
        examId: widget.token,
        nis: widget.studentNis,
        name: widget.studentName,
        status: 'FINISHED',
        violations: _violations,
      );

      // Simpan riwayat ujian & butir soal ke lokal agar bisa ditinjau di Pembahasan
      await StudentTryoutHistoryService.instance.saveAttempt(
        token: widget.token,
        namaPaket: _package?.namaPaket ?? 'Tryout',
        kategori: category,
        result: evalResult,
        answers: _answers,
        questions: _allQuestions,
      );

      // Bersihkan cache sesi ujian lokal
      await _clearLocalCache();

      if (!mounted) return;
      Navigator.pop(context); // Tutup dialog loading

      _showResultDialog(evalResult);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengirim jawaban: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showResultDialog(ExamEvaluationResult result) {
    final isPassed = result.isPassed;
    final isSKD = result.category.toUpperCase().contains('SKD');
    final isSNBT = result.category.toUpperCase().contains('SNBT') || result.category.toUpperCase().contains('UTBK');

    Color themeColor;
    if (isPassed) {
      themeColor = const Color(0xFF16A34A); // Emerald Green
    } else {
      themeColor = const Color(0xFFE11D48); // Rose / Red
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPassed ? Icons.stars_rounded : Icons.info_outline_rounded,
                size: 40,
                color: themeColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Ujian Telah Selesai',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              isPassed ? '🎉 Selamat! Hasil evaluasi telah memenuhi standar.' : '💪 Evaluasi hasil belajarmu dan terus berlatih.',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Kartu Skor Utama
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isPassed ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isPassed ? const Color(0xFFBBF7D0) : const Color(0xFFFECDD3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        isSKD
                            ? 'TOTAL SKOR SKD (MAKS 550)'
                            : (isSNBT ? 'SKOR RATA-RATA UTBK (SKALA 1000)' : 'NILAI AKHIR AKADEMIK'),
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          color: isPassed ? const Color(0xFF166534) : const Color(0xFF9F1239),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${result.finalScore}',
                        style: GoogleFonts.poppins(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: isPassed ? const Color(0xFF15803D) : const Color(0xFFBE123C),
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Status Kelulusan Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPassed ? const Color(0xFF16A34A) : const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          result.statusKelulusan,
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Predikat: ${result.predikat}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isPassed ? const Color(0xFF166534) : const Color(0xFF9F1239),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Ringkasan Benar, Salah, Kosong, Total
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMiniStat('Benar', '${result.totalBenar}', const Color(0xFF16A34A)),
                      _buildMiniStat('Salah', '${result.totalSalah}', const Color(0xFFDC2626)),
                      _buildMiniStat('Kosong', '${result.totalKosong}', const Color(0xFF64748B)),
                      _buildMiniStat('Total', '${result.totalSoal}', const Color(0xFF0F172A)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Rincian Nilai per Subtest
                if (result.subtests.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Rincian Nilai Per Subtest:',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF334155),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...result.subtests.values.map((st) {
                    final isPassedSt = st.isPassed;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isPassedSt ? const Color(0xFFE2E8F0) : const Color(0xFFFECDD3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  st.judul,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPassedSt ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  st.predikat,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isPassedSt ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                st.isTkp
                                    ? 'Skor: ${st.skor}/${st.maxSkor} (PG: ${st.passingGrade ?? "-"})'
                                    : (isSKD
                                        ? '${st.benar} Benar • Skor: ${st.skor}/${st.maxSkor} (PG: ${st.passingGrade ?? "-"})'
                                        : '${st.benar}/${st.total} Benar'),
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                '${st.skor}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isPassedSt ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TryoutDiscussionScreen(
                    title: _package?.namaPaket ?? 'Pembahasan Tryout',
                    kategori: _package?.kategori ?? ExamCategory.umum,
                    questions: _allQuestions,
                    studentAnswers: _answers,
                    score: result.finalScore,
                    statusKelulusan: result.statusKelulusan,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.menu_book_rounded, size: 16),
            label: Text(
              'Lihat Pembahasan & Kunci 📖',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              minimumSize: const Size(double.infinity, 42),
            ),
            child: Text(
              'Kembali ke Beranda',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isBlocked) {
      return _buildBlockedScreen();
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primaryGreen),
              const SizedBox(height: 16),
              Text(
                'Menyiapkan lembar ujian & memverifikasi sesi...',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: GoogleFonts.poppins(fontSize: 14, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                  ),
                  child: Text(
                    'Kembali',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activeQuestions = _getActiveQuestions();
    if (activeQuestions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            'Tidak ada butir soal pada sesi ujian ini.',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
        ),
      );
    }

    if (_currentIndex >= activeQuestions.length) {
      _currentIndex = 0;
    }

    final currentQ = activeQuestions[_currentIndex];
    final driveImg = MathHtmlFormatter.convertDriveUrl(currentQ.gambar);
    final selectedAns = _answers[currentQ.soalId];
    final isRagu = _raguRagu.contains(currentQ.soalId);
    final isWarningTimer = _remainingSeconds < 300; // < 5 menit

    final currentSubtestTitle =
        _isPerSubtest && _currentSubtestIndex < _subtests.length
        ? _subtests[_currentSubtestIndex].judul
        : (_package?.namaPaket ?? 'Ujian');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExitDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.apps_rounded,
                color: AppColors.primaryGreen,
                size: 18,
              ),
            ),
            tooltip: 'Lembar Navigasi Soal',
            onPressed: _showQuestionGridSheet,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentSubtestTitle,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Soal ${_currentIndex + 1} dari ${activeQuestions.length}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          actions: [
            // Tombol Ubah Ukuran Font (A- / A+)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.format_size_rounded,
                  color: Color(0xFF334155),
                  size: 18,
                ),
              ),
              tooltip: 'Ubah Ukuran Teks',
              onPressed: _cycleFontSize,
            ),

            // Badge Timer
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isWarningTimer
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isWarningTimer
                      ? const Color(0xFFDC2626)
                      : AppColors.primaryGreen,
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 15,
                    color: isWarningTimer
                        ? const Color(0xFFDC2626)
                        : AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_remainingSeconds),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isWarningTimer
                          ? const Color(0xFFDC2626)
                          : AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          children: [
            // Bar Navigasi Subtest jika dalam mode per_subtest
            if (_isPerSubtest && _subtests.length > 1)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Babak ${_currentSubtestIndex + 1}/${_subtests.length}',
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _subtests[_currentSubtestIndex].judul,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Konten Soal Scrollable
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card Soal (Design Bersih & Responsif myOLCv2)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x06000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryGreen,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${currentQ.nomorSoal}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Butir Pertanyaan',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: const Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (isRagu)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Ragu-Ragu',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Teks Pertanyaan Render LaTeX & HTML
                          HtmlWidget(
                            MathHtmlFormatter.format(currentQ.pertanyaan),
                            textStyle: GoogleFonts.poppins(
                              fontSize: 14 * _fontSizeScale,
                              color: const Color(0xFF1E293B),
                              height: 1.6,
                            ),
                            factoryBuilder: () => MathWidgetFactory(
                              fontSize: 14 * _fontSizeScale,
                            ),
                          ),

                          // Tabel Soal jika ada
                          if (currentQ.tabel.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildQuestionTable(currentQ.tabel),
                          ],

                          // Gambar Soal jika ada
                          if (driveImg.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: driveImg,
                                width: double.infinity,
                                fit: BoxFit.contain,
                                placeholder: (context, url) => Container(
                                  height: 140,
                                  color: const Color(0xFFF1F5F9),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primaryGreen,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Opsi Pilihan Jawaban
                    Text(
                      'Pilihan Jawaban:',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 10),

                    _buildOptionCard(
                      'A',
                      currentQ.opsiA,
                      currentQ.gamA,
                      selectedAns == 'A',
                      () {
                        setState(() => _answers[currentQ.soalId] = 'A');
                        _saveSessionToLocalCache();
                      },
                    ),
                    _buildOptionCard(
                      'B',
                      currentQ.opsiB,
                      currentQ.gamB,
                      selectedAns == 'B',
                      () {
                        setState(() => _answers[currentQ.soalId] = 'B');
                        _saveSessionToLocalCache();
                      },
                    ),
                    _buildOptionCard(
                      'C',
                      currentQ.opsiC,
                      currentQ.gamC,
                      selectedAns == 'C',
                      () {
                        setState(() => _answers[currentQ.soalId] = 'C');
                        _saveSessionToLocalCache();
                      },
                    ),
                    _buildOptionCard(
                      'D',
                      currentQ.opsiD,
                      currentQ.gamD,
                      selectedAns == 'D',
                      () {
                        setState(() => _answers[currentQ.soalId] = 'D');
                        _saveSessionToLocalCache();
                      },
                    ),
                    if (currentQ.opsiE.isNotEmpty || currentQ.gamE.isNotEmpty)
                      _buildOptionCard(
                        'E',
                        currentQ.opsiE,
                        currentQ.gamE,
                        selectedAns == 'E',
                        () {
                          setState(() => _answers[currentQ.soalId] = 'E');
                          _saveSessionToLocalCache();
                        },
                      ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),

            // Sticky Bottom Navigation Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Tombol Sebelumnya
                  IconButton.outlined(
                    onPressed: _currentIndex > 0
                        ? () {
                            setState(() => _currentIndex--);
                            _saveSessionToLocalCache();
                          }
                        : null,
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Tombol Ragu-Ragu
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          if (isRagu) {
                            _raguRagu.remove(currentQ.soalId);
                          } else {
                            _raguRagu.add(currentQ.soalId);
                          }
                        });
                        _saveSessionToLocalCache();
                      },
                      icon: Icon(
                        isRagu
                            ? Icons.flag_rounded
                            : Icons.outlined_flag_rounded,
                        color: isRagu
                            ? const Color(0xFFD97706)
                            : const Color(0xFF64748B),
                        size: 18,
                      ),
                      label: Text(
                        'Ragu-Ragu',
                        style: GoogleFonts.poppins(
                          color: isRagu
                              ? const Color(0xFFB45309)
                              : const Color(0xFF334155),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isRagu
                            ? const Color(0xFFFEF3C7)
                            : Colors.transparent,
                        side: BorderSide(
                          color: isRagu
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFCBD5E1),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Tombol Berikutnya / Selesai Subtest / Kumpulkan
                  if (_currentIndex < activeQuestions.length - 1)
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _currentIndex++);
                        _saveSessionToLocalCache();
                      },
                      icon: const Text(
                        'Berikutnya',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      label: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    )
                  else if (_isPerSubtest &&
                      _currentSubtestIndex < _subtests.length - 1)
                    ElevatedButton(
                      onPressed: _confirmFinishSubtestDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Lanjut Subtest',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    ElevatedButton(
                      onPressed: _confirmSubmitDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Kumpulkan',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard(
    String key,
    String text,
    String img,
    bool isSelected,
    VoidCallback onTap,
  ) {
    if (text.isEmpty && img.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryGreen.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryGreen
                : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.15),
                    blurRadius: 8,
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x04000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryGreen
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  key,
                  style: GoogleFonts.poppins(
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (text.isNotEmpty)
                    HtmlWidget(
                      MathHtmlFormatter.format(text),
                      textStyle: GoogleFonts.poppins(
                        fontSize: 13.5 * _fontSizeScale,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF15803D)
                            : const Color(0xFF0F172A),
                        height: 1.45,
                      ),
                      factoryBuilder: () =>
                          MathWidgetFactory(fontSize: 13.5 * _fontSizeScale),
                    ),
                  if (img.isNotEmpty) ...[
                    if (text.isNotEmpty) const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        MathHtmlFormatter.convertDriveUrl(img),
                        height: 110,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 4),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primaryGreen,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionTable(String tabelStr) {
    if (tabelStr.isEmpty) return const SizedBox.shrink();
    try {
      final rowsArr = tabelStr.contains('===')
          ? tabelStr.split('===')
          : tabelStr.split(',/');
      final delim = tabelStr.contains('===') ? '|||' : '-';
      final tableRows = <TableRow>[];

      for (int k = 0; k < rowsArr.length; k++) {
        final parts = rowsArr[k].split(delim);
        if (parts.isNotEmpty) parts.removeAt(0);
        if (parts.isEmpty) continue;
        final isHeader = k == 0;

        tableRows.add(TableRow(
          decoration: BoxDecoration(
            color: isHeader
                ? const Color(0xFFF1F5F9)
                : (k.isEven ? const Color(0xFFFAFAFA) : Colors.white),
          ),
          children: parts.map((cell) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: HtmlWidget(
                MathHtmlFormatter.format(cell.trim()),
                textStyle: GoogleFonts.poppins(
                  fontSize: 12.5 * _fontSizeScale,
                  fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                  color: const Color(0xFF1E293B),
                ),
                factoryBuilder: () =>
                    MathWidgetFactory(fontSize: 12.5 * _fontSizeScale),
              ),
            );
          }).toList(),
        ));
      }

      if (tableRows.isEmpty) return const SizedBox.shrink();

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320),
            child: Table(
              border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: tableRows,
            ),
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildBlockedScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF991B1B),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.block_rounded,
                  color: Color(0xFFDC2626),
                  size: 54,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'LAYAR UJIAN TERKUNCI',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Terdeteksi upaya meninggalkan aplikasi ujian sebanyak $_violations kali.\n\n'
                'Silakan hubungi Pengawas Ujian di ruangan untuk membuka blokir perangkat Anda.',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmFinishSubtestDialog() {
    final subtest = _subtests[_currentSubtestIndex];
    final activeQ = _getActiveQuestions();
    int answered = 0;
    for (final q in activeQ) {
      if (_answers.containsKey(q.soalId)) answered++;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Selesaikan Subtest Ini?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subtest: ${subtest.judul}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '• Terjawab: $answered dari ${activeQ.length} soal',
              style: GoogleFonts.poppins(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Perhatian: Begitu Anda berpindah ke subtest berikutnya, Anda tidak dapat kembali ke subtest ini lagi (sesuai aturan UTBK resmi).',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: const Color(0xFFB45309),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Periksa Kembali',
              style: GoogleFonts.poppins(color: const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleSubtestTimeExpired();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Lanjut Sekarang',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSubmitDialog() {
    final answeredCount = _answers.length;
    final total = _allQuestions.length;
    final raguCount = _raguRagu.length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Kumpulkan Jawaban Ujian?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ringkasan Pengerjaan:',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '• Terjawab: $answeredCount dari $total butir soal',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (raguCount > 0)
              Text(
                '• Ditandai Ragu-Ragu: $raguCount butir',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: const Color(0xFFD97706),
                ),
              ),
            if (answeredCount < total)
              Text(
                '• Belum Dijawab: ${total - answeredCount} butir',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: const Color(0xFFDC2626),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Apakah Anda yakin ingin menyelesaikan dan mengirim seluruh lembar ujian?',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Periksa Kembali',
              style: GoogleFonts.poppins(color: const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitExam();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Kumpulkan Sekarang',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Keluar dari Ujian?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Keluar dari aplikasi selama ujian berlangsung akan dicatat sebagai pelanggaran tata tertib ujian.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Tetap di Ujian',
              style: GoogleFonts.poppins(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitExam(autoSubmit: false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: Text(
              'Kumpulkan & Keluar',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
