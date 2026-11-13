import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constant/app_colors.dart';
import '../../constant/security_service.dart';
import '../../models/exam_question_model.dart';
import '../../models/tryout_schedule_model.dart';
import '../../services/exam_cache_service.dart';
import '../../services/license_service.dart';
import '../../services/monitoring_service.dart';
import '../../services/national_exam_evaluator.dart';
import '../../services/student_tryout_history_service.dart';
import '../../services/trusted_time_service.dart';
import '../../utils/indo_date_formatter.dart';
import '../../utils/math_widget_factory.dart';
import 'tryout_discussion_screen.dart';
import 'tryout_schedule_screen.dart';
import 'widgets/exam_question_table_widget.dart';
import 'widgets/exam_time_lock_dialog.dart';
import '../widgets/anti_cheat_shield_overlay.dart';

class StudentExamSessionScreen extends StatefulWidget {
  final String token;
  final String studentName;
  final String studentNis;
  final bool isEvent;
  final TryoutSchedule? initialSchedule;

  /// Jika true, selesai ujian kembali ke HomeScreen bukan TryoutScheduleScreen.
  /// Diset true saat ujian dimulai dari input token manual di HomeScreen.
  final bool returnToHome;

  const StudentExamSessionScreen({
    super.key,
    required this.token,
    required this.studentName,
    required this.studentNis,
    this.isEvent = false,
    this.initialSchedule,
    this.returnToHome = false,
  });

  @override
  State<StudentExamSessionScreen> createState() =>
      _StudentExamSessionScreenState();
}

class _StudentExamSessionScreenState extends State<StudentExamSessionScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  String _loadingStatusMessage = 'Menyiapkan Lembar Ujian...';
  double _loadingProgressPercent = 0.2;
  String? _errorMessage;

  ExamPackage? _package;
  List<ExamSubtest> _subtests = [];
  final List<ExamQuestion> _allQuestions = [];

  // Index soal aktif relatif terhadap daftar soal aktif
  int _currentIndex = 0;

  // Index subtest yang sedang aktif (khusus mode per_subtest)
  int _currentSubtestIndex = 0;
  ExamSubtest? get _currentSubtest =>
      (_subtests.isNotEmpty && _currentSubtestIndex < _subtests.length)
      ? _subtests[_currentSubtestIndex]
      : null;

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
  DateTime? _effectiveExamEndTime;
  int _remainingSeconds = 0;
  Timer? _tickerTimer;

  // ─── Anti-Cheat Monitoring State ──────────────────────────────
  int _violations = 0;
  bool _isBlocked = false;
  bool _isSubmitted = false;
  bool _isShowingWarningDialog = false;
  bool _isShieldActive = false;
  bool _isSplitScreenActive = false;
  StreamSubscription<DocumentSnapshot>? _statusListener;
  Timer? _saveCacheDebounce;

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
    _saveCacheDebounce?.cancel();
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
      if (mounted) setState(() => _isShieldActive = true);
      _violations++;
      _handleViolationDetected();
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && _isShieldActive) {
        setState(() => _isShieldActive = false);
      }
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
    if (_isShowingWarningDialog || !mounted || _isBlocked || _isSubmitted) {
      return;
    }
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
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Saya Mengerti & Kembali Mengerjakan',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 13,
                ),
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
    SecurityService.instance.bringToForeground();
    SecurityService.instance.reapply();

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

  // ─── Memuat Data Ujian & Resiliensi Multi-Source (Cache-First + Fast Firestore + GAS) ──
  Future<void> _loadExamData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _loadingStatusMessage = 'Memeriksa penyimpanan lokal HP...';
      _loadingProgressPercent = 0.2;
    });

    try {
      final tokenUpper = widget.token.trim().toUpperCase();

      // ── DEFENSE-IN-DEPTH: Cek 1-Device / 1-Attempt langsung di layar ujian ──
      if (!widget.isEvent) {
        final attempt = await StudentTryoutHistoryService.instance.getLatestAttempt(tokenUpper);

        // Cek juga ke server monitoring apakah siswa sudah pernah FINISHED
        Map<String, dynamic>? studentServerData;
        if (widget.studentNis.isNotEmpty) {
          try {
            studentServerData = await MonitoringService.instance.getStudentData(
              tokenUpper,
              widget.studentNis,
            );
          } catch (_) {}
        }

        final isFinishedOnServer = studentServerData?['status'] == 'FINISHED';
        final hasPriorAttempt = attempt != null || isFinishedOnServer;

        // Khusus Event: Cek apakah ID Device ini sudah pernah menyelesaikan event ini!
        if (widget.isEvent) {
          final deviceId = await LicenseService.instance.getDeviceId();
          final prefs = await SharedPreferences.getInstance();
          bool deviceCompleted = prefs.getBool('event_completed_${tokenUpper}_$deviceId') ?? false;
          if (!deviceCompleted) {
            try {
              final doc = await FirebaseFirestore.instance
                  .collection('event_completions')
                  .doc('${tokenUpper}_$deviceId')
                  .get();
              if (doc.exists) {
                deviceCompleted = true;
                await prefs.setBool('event_completed_${tokenUpper}_$deviceId', true);
              }
            } catch (_) {}
          }
          if (deviceCompleted) {
            if (mounted) {
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Row(
                    children: [
                      Icon(Icons.block_rounded, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Event Sudah Dikerjakan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  content: const Text(
                    'Event ini hanya dapat dikerjakan satu kali per perangkat. Perangkat Anda telah menyelesaikan sesi event ini.',
                    style: TextStyle(fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (mounted) Navigator.pop(context);
            }
            return;
          }
        }

        if (hasPriorAttempt) {
          // Cek izin ujian ulang dari guru di server & lokal
          bool retakePermitted = studentServerData?['allow_retake'] == true;
          if (!retakePermitted && widget.studentNis.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            retakePermitted = prefs.getBool(
              'retake_allowed_${tokenUpper}_${widget.studentNis}',
            ) ?? false;
          }

          // Pembatasan 1x: untuk tryout guru/terkunci atau sesi yang sudah disubmit
          final isRestricted = (attempt != null && !attempt.allowRetake) ||
              widget.initialSchedule?.allowRetake == false ||
              widget.isEvent ||
              isFinishedOnServer;

          if (isRestricted && (!retakePermitted || widget.isEvent)) {
            // Periksa apakah waktu ujian sudah berakhir
            DateTime? eventEnd;
            if (widget.isEvent && widget.initialSchedule?.tanggal.isNotEmpty == true) {
              final dt = IndoDateFormatter.parse(widget.initialSchedule!.tanggal);
              if (dt != null) {
                final jamP = widget.initialSchedule!.jamSelesai.split(':');
                final h = int.tryParse(jamP[0]) ?? 23;
                final m = jamP.length > 1 ? (int.tryParse(jamP[1]) ?? 59) : 59;
                eventEnd = DateTime(dt.year, dt.month, dt.day, h, m);
              }
            }
            final targetEndTime = eventEnd ?? attempt?.examEndTime;
            final isEnded = await TrustedTimeService.instance.isExamTimeEnded(
              examEndTime: targetEndTime,
              submittedAt: attempt?.submittedAt ?? DateTime.now(),
              elapsedRealtimeMs: attempt?.elapsedRealtimeMs,
            );

            if (mounted) {
              if (isEnded) {
                // Waktu habis → arahkan ke Pembahasan & Kunci
                List<ExamQuestion> questions = attempt?.questions ?? [];
                if (questions.isEmpty) {
                  final cached = await ExamCacheService.instance.loadExam(tokenUpper);
                  if (cached != null && cached.questions.isNotEmpty) {
                    questions = cached.questions;
                  }
                }
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TryoutDiscussionScreen(
                      title: attempt?.namaPaket.isNotEmpty == true ? attempt!.namaPaket : 'Pembahasan Ujian',
                      kategori: attempt?.kategori.isNotEmpty == true ? attempt!.kategori : 'CBT Guru',
                      questions: questions,
                      studentAnswers: attempt?.jawaban ?? {},
                      score: attempt?.finalScore ?? 0,
                      statusKelulusan: attempt?.statusKelulusan ?? 'SELESAI',
                      returnToHome: widget.returnToHome,
                      token: tokenUpper,
                    ),
                  ),
                );
              } else {
                // Waktu belum habis → tampilkan dialog kunci waktu lalu pop
                await showExamTimeLockDialog(
                  context,
                  endTime: targetEndTime ?? DateTime.now().add(const Duration(minutes: 60)),
                  examTitle: attempt?.namaPaket.isNotEmpty == true ? attempt!.namaPaket : 'Ujian',
                );
                if (mounted) Navigator.pop(context);
              }
            }
            return;
          }
        }
      }

      // Inisialisasi awal metadata paket jika dioper dari halaman jadwal / home
      if (widget.initialSchedule != null) {
        final sched = widget.initialSchedule!;
        _package = ExamPackage(
          paketId: sched.paketId,
          namaPaket: sched.namaPaket,
          kategori: sched.jenisTest,
          jenisWaktu: sched.jenisWaktu,
          durasiMenit: sched.durasiMenit,
          allowRetake: sched.allowRetake,
          isTeacherGenerated: sched.isTeacherGenerated,
        );
      }

      // ── TAHAP 0: Cache-First (Instant Load < 50ms jika sudah tersimpan di perangkat) ──
      final cached = await ExamCacheService.instance.loadExam(tokenUpper);
      if (cached != null && cached.questions.isNotEmpty) {
        _package ??= cached.package;
        _subtests = cached.subtests;
        _allQuestions.clear();
        _allQuestions.addAll(cached.questions);

        _hydrateSubtestsWithQuestions();
        await _restoreLocalCache();
        await _initTimer();

        if (mounted) {
          setState(() => _isLoading = false);
        }

        // Monitoring background non-blocking
        unawaited(
          MonitoringService.instance.updateStudentStatus(
            examId: widget.token,
            nis: widget.studentNis,
            name: widget.studentName,
            status: 'ONLINE',
            violations: 0,
          ),
        );
        return;
      }

      // ── TAHAP 1: Unduh dari Firestore / GAS & Simpan ke Penyimpanan Lokal HP ──
      final downloaded = await ExamCacheService.instance.downloadAndCacheExam(
        paketId: tokenUpper,
        initialSchedule: widget.initialSchedule,
        onProgress: (msg, pct) {
          if (mounted) {
            setState(() {
              _loadingStatusMessage = msg;
              _loadingProgressPercent = pct;
            });
          }
        },
      );

      _package = downloaded.package ?? _package;
      _subtests = downloaded.subtests;
      _allQuestions.clear();
      _allQuestions.addAll(downloaded.questions);

      _hydrateSubtestsWithQuestions();
      await _restoreLocalCache();
      await _initTimer();

      if (mounted) {
        setState(() => _isLoading = false);
      }

      unawaited(
        MonitoringService.instance.updateStudentStatus(
          examId: widget.token,
          nis: widget.studentNis,
          name: widget.studentName,
          status: 'ONLINE',
          violations: 0,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _hydrateSubtestsWithQuestions() {
    if (_subtests.isNotEmpty) {
      int seqNumber = 1;
      for (final st in _subtests) {
        final stSoal = _allQuestions.where((q) {
          final qSt = q.subtestId.trim().toUpperCase();
          final sSt = st.subtestId.trim().toUpperCase();
          return qSt == sSt ||
              (qSt.isNotEmpty &&
                  sSt.isNotEmpty &&
                  (qSt.contains(sSt) || sSt.contains(qSt)));
        }).toList();
        stSoal.sort((a, b) => a.soalId.compareTo(b.soalId));
        for (final q in stSoal) {
          q.nomorSoal = seqNumber++;
        }
        st.soalList = stSoal;
      }

      final orphans = _allQuestions
          .where((q) => !_subtests.any((st) => st.soalList.contains(q)))
          .toList();
      if (orphans.isNotEmpty && _subtests.isNotEmpty) {
        orphans.sort((a, b) => a.soalId.compareTo(b.soalId));
        for (final q in orphans) {
          q.nomorSoal = seqNumber++;
        }
        _subtests.first.soalList.addAll(orphans);
      }
    } else {
      int seqNumber = 1;
      _allQuestions.sort((a, b) => a.soalId.compareTo(b.soalId));
      for (final q in _allQuestions) {
        q.nomorSoal = seqNumber++;
      }
      _subtests = [
        ExamSubtest(
          subtestId: 'ST1',
          paketId: widget.token.trim().toUpperCase(),
          judul: 'Soal Ujian',
          durasiMenit: _package?.durasiMenit ?? 90,
          soalList: _allQuestions,
        ),
      ];
    }
    _allQuestions.sort((a, b) => a.nomorSoal.compareTo(b.nomorSoal));
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

  void _debouncedSaveCache() {
    _saveCacheDebounce?.cancel();
    _saveCacheDebounce = Timer(const Duration(milliseconds: 500), () {
      _saveSessionToLocalCache();
    });
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

  // ─── Klasifikasi Aturan Resmi Ujian Nasional (SNBT, TKA, SKD/BKN) ───
  bool get _isSnbt {
    // Soal yang dibuat guru / WebGAS dan kategori umum bebas dari aturan kaku blocking time
    if (_package?.isTeacherGenerated == true) return false;
    final kat = (_package?.kategori ?? '').trim().toUpperCase();
    if (kat == ExamCategory.umum || kat == 'UMUM') return false;
    return kat == ExamCategory.snbt ||
        kat == 'SNBT' ||
        kat.contains('SNBT') ||
        kat.contains('UTBK');
  }

  bool get _isSkd {
    final kat = (_package?.kategori ?? '').trim().toUpperCase();
    return kat == ExamCategory.skd || kat == 'SKD';
  }

  bool get _isTka {
    final kat = (_package?.kategori ?? '').trim().toUpperCase();
    return kat.startsWith('TKA') || kat.contains('TKA');
  }

  // ─── Manajemen Timer Per-Subtest & Global ──────────────────────
  bool get _isPerSubtest {
    final jw = (_package?.jenisWaktu ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    if (jw == 'per_subtest') return true;
    if (jw == 'per_paket') return false;

    // Soal buatan guru / WebGAS jika memiliki lebih dari 1 subtest otomatis tampil per-subtest
    if (_package?.isTeacherGenerated == true && _subtests.length > 1) return true;

    // Sesuai aturan CAT BKN: SKD resmi selalu satu kesatuan waktu global 100 menit (bebas lintas subtes)
    if (_isSkd) return false;

    // SNBT dan TKA menggunakan alokasi waktu terpisah per-subtest
    if (_isSnbt || _isTka) return true;

    return _subtests.length > 1;
  }

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

      final totalPkgEndKey =
          'exam_pkg_total_end_${widget.token}_${widget.studentNis}';
      final savedTotalMs = prefs.getInt(totalPkgEndKey);
      if (savedTotalMs != null) {
        _packageEndTime = DateTime.fromMillisecondsSinceEpoch(savedTotalMs);
      } else {
        final totalMins =
            _subtests.fold<int>(0, (acc, st) => acc + st.durasiMenit);
        _packageEndTime = now.add(
          Duration(
            minutes:
                totalMins > 0 ? totalMins : (_package?.durasiMenit ?? 90),
          ),
        );
        await prefs.setInt(
          totalPkgEndKey,
          _packageEndTime!.millisecondsSinceEpoch,
        );
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
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      _checkRemainingTime();
      if (!_isSubmitted && !_isBlocked) {
        final inMulti = await SecurityService.instance.isInMultiWindowMode();
        if (inMulti != _isSplitScreenActive && mounted) {
          setState(() => _isSplitScreenActive = inMulti);
          if (inMulti) {
            _violations++;
            _handleViolationDetected();
          }
        }
      }
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
            final answeredCount = activeQuestions
                .where((q) => _answers.containsKey(q.soalId))
                .length;
            final totalCount = activeQuestions.length;
            final hasNextSubtest =
                _isPerSubtest && _currentSubtestIndex < _subtests.length - 1;

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
                            if (_isSkd)
                              Text(
                                'Simulasi CAT BKN: Bebas Akses Seluruh Soal',
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  color: const Color(0xFF2563EB),
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else if (_isPerSubtest && _subtests.isNotEmpty)
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
                              _debouncedSaveCache();
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
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 12),

                    // Baris Aksi Bawah: Rekap & Tombol Kirim Ujian
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Progres Pengerjaan',
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                '$answeredCount / $totalCount Terjawab',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isSnbt && hasNextSubtest) ...[
                          // SNBT dengan subtes belum selesai:
                          // JANGAN tampilkan tombol "Lanjut Subtest" dan JANGAN tampilkan tombol "Kirim Ujian"
                          // HANYA tampilkan status badge informatif Blocking Time
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _showBlockingTimeInfoDialog();
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.lock_clock_rounded,
                                    size: 15,
                                    color: Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Blocking Time Terkunci',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF92400E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          // TKA / Non-SNBT atau Subtes Terakhir SNBT atau SKD
                          if (hasNextSubtest) ...[
                            // TKA / Non-SNBT boleh tampil tombol Lanjut Subtest
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _confirmFinishSubtestDialog();
                              },
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                              label: Text(
                                'Lanjut Subtest',
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD97706),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmSubmitDialog();
                            },
                            icon: const Icon(
                              Icons.send_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Kirim Ujian',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ],
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

      final prefs = await SharedPreferences.getInstance();
      final studentEmail = prefs.getString('student_email') ?? '-';
      final studentWa = prefs.getString('student_whatsapp') ?? '-';
      final deviceId = await LicenseService.instance.getDeviceId();

      final docRef = FirebaseFirestore.instance
          .collection('jawaban_tryout')
          .doc('${widget.studentNis}_${widget.token}');

      await docRef.set({
        'token': widget.token,
        'nama_peserta': widget.studentName,
        'nis': widget.studentNis,
        'device_id': deviceId,
        'email': studentEmail,
        'no_wa': studentWa,
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
        'subtest_scores': evalResult.subtests.map(
          (k, v) => MapEntry(k, v.toMap()),
        ),
        'jawaban': _answers,
        'violations': _violations,
        'is_blocked': _isBlocked,
        'submitted_at': FieldValue.serverTimestamp(),
        'auto_submitted': autoSubmit,
      });

      // Catat device_id yang telah menyelesaikan event (mencegah pengerjaan ulang event)
      if (widget.isEvent || _package?.kategori == 'EVENT' || widget.initialSchedule?.jenisTest == 'EVENT') {
        unawaited(
          FirebaseFirestore.instance
              .collection('event_completions')
              .doc('${widget.token}_$deviceId')
              .set({
                'token': widget.token,
                'device_id': deviceId,
                'nis': widget.studentNis,
                'nama_peserta': widget.studentName,
                'skor_akhir': evalResult.finalScore,
                'submitted_at': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .catchError((_) {}),
        );
        await prefs.setBool('event_completed_${widget.token}_$deviceId', true);
      }

      // Update status monitoring ke FINISHED di background non-blocking
      unawaited(
        MonitoringService.instance.updateStudentStatus(
          examId: widget.token,
          nis: widget.studentNis,
          name: widget.studentName,
          status: 'FINISHED',
          violations: _violations,
        ),
      );

      // Kunci kembali izin ujian ulang di server agar pengerjaan berikutnya harus meminta izin guru lagi (background non-blocking)
      unawaited(
        FirebaseFirestore.instance
            .collection('exam_sessions')
            .doc(widget.token)
            .collection('students')
            .doc(widget.studentNis)
            .set({
              'allow_retake': false,
            }, SetOptions(merge: true))
            .catchError((_) {}),
      );
      await prefs.remove('retake_allowed_${widget.token}_${widget.studentNis}');

      // Hitung waktu resmi berakhirnya event jika ada
      DateTime? officialEventEndTime;
      if (widget.initialSchedule?.tanggal.isNotEmpty == true) {
        final dt = IndoDateFormatter.parse(widget.initialSchedule!.tanggal);
        if (dt != null) {
          final jamP = widget.initialSchedule!.jamSelesai.split(':');
          final h = int.tryParse(jamP[0]) ?? 23;
          final m = jamP.length > 1 ? (int.tryParse(jamP[1]) ?? 59) : 59;
          officialEventEndTime = DateTime(dt.year, dt.month, dt.day, h, m);
        }
      }

      _effectiveExamEndTime = (widget.isEvent && officialEventEndTime != null)
          ? officialEventEndTime
          : (_packageEndTime ??
              DateTime.now().add(
                Duration(minutes: _package?.durasiMenit ?? 90),
              ));
      final effectiveExamEndTime = _effectiveExamEndTime!;

      // Simpan riwayat ujian & butir soal ke lokal agar bisa ditinjau di Pembahasan
      await StudentTryoutHistoryService.instance.saveAttempt(
        token: widget.token,
        namaPaket: _package?.namaPaket ?? 'Tryout',
        kategori: category,
        result: evalResult,
        answers: _answers,
        questions: _allQuestions,
        examEndTime: effectiveExamEndTime,
        allowRetake: widget.isEvent
            ? false
            : (_package?.allowRetake ??
                (widget.initialSchedule?.allowRetake ?? false)),
        syncCloud: false,
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

  void _navigateToDashboard() {
    if (!mounted) return;
    // Jika ujian dari token manual (home screen), kembali ke HomeScreen.
    // Jika dari TryoutScheduleScreen (premium), kembali ke sana.
    if (widget.returnToHome) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const TryoutScheduleScreen()),
        (route) => route.isFirst,
      );
    }
  }

  void _showResultDialog(ExamEvaluationResult result) {
    final isPassed = result.isPassed;
    final isSKD = result.category.toUpperCase().contains('SKD');
    final isSNBT =
        result.category.toUpperCase().contains('SNBT') ||
        result.category.toUpperCase().contains('UTBK');
    final themeColor = isPassed
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Ringkas
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPassed
                          ? Icons.emoji_events_rounded
                          : Icons.info_rounded,
                      size: 24,
                      color: themeColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Evaluasi Hasil Ujian',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '${result.category} • ${result.statusKelulusan}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: themeColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: themeColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      result.predikat,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: themeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Kartu Skor Utama & Mini Stat Ringkas (Horizontal Split)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: isPassed
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isPassed
                        ? const Color(0xFFBBF7D0)
                        : const Color(0xFFFECDD3),
                  ),
                ),
                child: Row(
                  children: [
                    // Sisi Kiri: Nilai Akhir
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isSKD
                                ? 'SKOR SKD'
                                : (isSNBT ? 'RATA-RATA UTBK' : 'NILAI AKHIR'),
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              color: isPassed
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF9F1239),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${result.finalScore}',
                                style: GoogleFonts.poppins(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: isPassed
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFFBE123C),
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '/ ${result.maxScore}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 42,
                      color: const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(width: 12),
                    // Sisi Kanan: 4 Mini Stat ringkas
                    Expanded(
                      flex: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMiniStat(
                            'Benar',
                            '${result.totalBenar}',
                            const Color(0xFF16A34A),
                          ),
                          _buildMiniStat(
                            'Salah',
                            '${result.totalSalah}',
                            const Color(0xFFDC2626),
                          ),
                          _buildMiniStat(
                            'Kosong',
                            '${result.totalKosong}',
                            const Color(0xFF64748B),
                          ),
                          _buildMiniStat(
                            'Soal',
                            '${result.totalSoal}',
                            const Color(0xFF0F172A),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Rincian Subtes (Scrollable dengan batas tinggi maksimal 125px)
              if (result.subtests.isNotEmpty) ...[
                Text(
                  'Rincian Nilai Subtes:',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 125),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Scrollbar(
                    thumbVisibility: result.subtests.length > 2,
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      itemCount: result.subtests.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      itemBuilder: (context, i) {
                        final st = result.subtests.values.elementAt(i);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  st.judul,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1E293B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${st.benar}/${st.total} B • ',
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                '${st.skor} pts',
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: st.isPassed
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Tombol Aksi Harmonis ExamGO
              Builder(
                builder: (context) {
                  DateTime? eventEndTime;
                  if (widget.isEvent && widget.initialSchedule?.tanggal.isNotEmpty == true) {
                    final dt = IndoDateFormatter.parse(widget.initialSchedule!.tanggal);
                    if (dt != null) {
                      final jamP = widget.initialSchedule!.jamSelesai.split(':');
                      final h = int.tryParse(jamP[0]) ?? 23;
                      final m = jamP.length > 1 ? (int.tryParse(jamP[1]) ?? 59) : 59;
                      eventEndTime = DateTime(dt.year, dt.month, dt.day, h, m);
                    }
                  }
                  final targetEndTime = eventEndTime ?? _effectiveExamEndTime ?? _packageEndTime;
                  final isTimeEnded = targetEndTime == null ||
                      DateTime.now().isAfter(targetEndTime);
                  return SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final isEnded =
                            await TrustedTimeService.instance.isExamTimeEnded(
                          examEndTime: targetEndTime,
                        );
                        if (!isEnded && targetEndTime != null) {
                          if (!context.mounted) return;
                          showExamTimeLockDialog(
                            context,
                            endTime: targetEndTime,
                            examTitle: _package?.namaPaket,
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        Navigator.pop(ctx);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TryoutDiscussionScreen(
                              title: _package?.namaPaket ?? 'Pembahasan Tryout',
                              kategori: _package?.kategori ?? ExamCategory.umum,
                              questions: _allQuestions,
                              studentAnswers: _answers,
                              score: result.finalScore,
                              statusKelulusan: result.statusKelulusan,
                              returnToDashboardOnExit: !widget.returnToHome,
                              returnToHome: widget.returnToHome,
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        isTimeEnded
                            ? Icons.menu_book_rounded
                            : Icons.lock_clock_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: Text(
                        isTimeEnded
                            ? 'Lihat Pembahasan & Kunci'
                            : 'Pembahasan & Kunci (Terkunci)',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isTimeEnded
                            ? AppColors.primaryGreen
                            : const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _navigateToDashboard();
                  },
                  icon: Icon(
                    widget.returnToHome
                        ? Icons.home_rounded
                        : Icons.dashboard_rounded,
                    size: 18,
                    color: const Color(0xFF1B5E20),
                  ),
                  label: Text(
                    widget.returnToHome
                        ? 'Kembali ke Beranda ExamGO'
                        : 'Kembali ke Dashboard Tryout',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: const Color(0xFF1B5E20),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8F5E9),
                    foregroundColor: const Color(0xFF1B5E20),
                    side: const BorderSide(
                      color: Color(0xFFA5D6A7),
                      width: 1.2,
                    ),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Branded pulsing badge
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDCFCE7), Color(0xFFF0FDF4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFBBF7D0),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Menyiapkan Lembar Ujian',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _loadingStatusMessage,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _loadingProgressPercent,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primaryGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Penyimpanan Lokal HP',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    Text(
                      '${(_loadingProgressPercent * 100).toInt()}%',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
    final selectedAns = _answers[currentQ.soalId];
    final isRagu = _raguRagu.contains(currentQ.soalId);
    final isWarningTimer = _remainingSeconds < 300; // < 5 menit

    final String currentSubtestTitle;
    if (_isPerSubtest && _currentSubtestIndex < _subtests.length) {
      currentSubtestTitle = _subtests[_currentSubtestIndex].judul;
    } else if (_isSkd && _subtests.isNotEmpty) {
      final matchingSt = _subtests.firstWhere(
        (st) => st.subtestId == currentQ.subtestId,
        orElse: () => _subtests.first,
      );
      currentSubtestTitle = 'SKD — ${matchingSt.judul}';
    } else {
      currentSubtestTitle = _package?.namaPaket ?? 'Ujian';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_isSubmitted) {
            _navigateToDashboard();
          } else {
            _confirmExitDialog();
          }
        }
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
        body: AntiCheatShieldOverlay(
          isShieldActive: _isShieldActive || _isSplitScreenActive,
          onRecover: () {
            SecurityService.instance.bringToForeground();
            SecurityService.instance.reapply();
          },
          child: Column(
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
                    if (!_isSnbt && _currentSubtestIndex < _subtests.length - 1)
                      InkWell(
                        onTap: _confirmFinishSubtestDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFFDE68A),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Lanjut Babak',
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF92400E),
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 14,
                                color: Color(0xFF92400E),
                              ),
                            ],
                          ),
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

                          // 1. Stimulus Teks Bacaan (jika soal memiliki bacaan/wacana)
                          // Ditempatkan DI ATAS pertanyaan agar alur membaca siswa alami dan elegan
                          if (currentQ.tabel.isNotEmpty &&
                              ExamQuestionTableWidget.isReadingPassage(
                                currentQ.tabel,
                                subtestJudul: _currentSubtest?.judul,
                              )) ...[
                            ExamQuestionTableWidget(
                              tabelStr: currentQ.tabel,
                              subtestJudul: _currentSubtest?.judul,
                              fontSizeScale: _fontSizeScale,
                            ),
                            const Divider(
                              height: 20,
                              thickness: 1,
                              color: Color(0xFFF1F5F9),
                            ),
                          ],

                          // 2. Teks Pertanyaan Render LaTeX & HTML
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

                          // 3. Tabel Data Statistik/Numerik (HANYA untuk tabel angka/kuantitatif, BUKAN teks bacaan)
                          if (currentQ.tabel.isNotEmpty &&
                              !ExamQuestionTableWidget.isReadingPassage(
                                currentQ.tabel,
                                subtestJudul: _currentSubtest?.judul,
                              )) ...[
                            const SizedBox(height: 12),
                            ExamQuestionTableWidget(
                              tabelStr: currentQ.tabel,
                              subtestJudul: _currentSubtest?.judul,
                              fontSizeScale: _fontSizeScale,
                            ),
                          ],

                          // Gambar Soal jika ada
                          if (currentQ.gambar.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            MathHtmlFormatter.buildQuestionImage(
                              currentQ.gambar,
                              borderRadius: BorderRadius.circular(12),
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
                        _debouncedSaveCache();
                      },
                    ),
                    _buildOptionCard(
                      'B',
                      currentQ.opsiB,
                      currentQ.gamB,
                      selectedAns == 'B',
                      () {
                        setState(() => _answers[currentQ.soalId] = 'B');
                        _debouncedSaveCache();
                      },
                    ),
                    _buildOptionCard(
                      'C',
                      currentQ.opsiC,
                      currentQ.gamC,
                      selectedAns == 'C',
                      () {
                        setState(() => _answers[currentQ.soalId] = 'C');
                        _debouncedSaveCache();
                      },
                    ),
                    _buildOptionCard(
                      'D',
                      currentQ.opsiD,
                      currentQ.gamD,
                      selectedAns == 'D',
                      () {
                        setState(() => _answers[currentQ.soalId] = 'D');
                        _debouncedSaveCache();
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
                          _debouncedSaveCache();
                        },
                      ),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),

            // Sticky Bottom Navigation Bar Modern & Ergonomis
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 1. Tombol Sebelumnya
                  InkWell(
                    onTap: _currentIndex > 0
                        ? () {
                            setState(() => _currentIndex--);
                            _debouncedSaveCache();
                          }
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _currentIndex > 0
                            ? Colors.white
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _currentIndex > 0
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: _currentIndex > 0
                            ? const Color(0xFF334155)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Tombol Ragu-Ragu
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (isRagu) {
                            _raguRagu.remove(currentQ.soalId);
                          } else {
                            _raguRagu.add(currentQ.soalId);
                          }
                        });
                        _debouncedSaveCache();
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isRagu
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isRagu
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFCBD5E1),
                            width: isRagu ? 1.5 : 1.0,
                          ),
                          boxShadow: isRagu
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFD97706,
                                    ).withValues(alpha: 0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isRagu
                                  ? Icons.flag_rounded
                                  : Icons.outlined_flag_rounded,
                              size: 18,
                              color: isRagu
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Ragu-Ragu',
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: isRagu
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isRagu
                                    ? const Color(0xFF92400E)
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Tombol Aksi Utama (Berikutnya / Blocking Time / Lanjut Subtest / Kumpulkan)
                  if (_currentIndex < activeQuestions.length - 1)
                    InkWell(
                      onTap: () {
                        setState(() => _currentIndex++);
                        _debouncedSaveCache();
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0F766E,
                              ).withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Berikutnya',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_isPerSubtest &&
                      _currentSubtestIndex < _subtests.length - 1)
                    if (_isSnbt)
                      InkWell(
                        onTap: _showBlockingTimeInfoDialog,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFEF3C7), Color(0xFFFFFBEB)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFFDE68A),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFD97706,
                                ).withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_clock_rounded,
                                size: 16,
                                color: Color(0xFFB45309),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Blocking Time',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF92400E),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: _confirmFinishSubtestDialog,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFD97706,
                                ).withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Lanjut Subtest',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      )
                  else
                    InkWell(
                      onTap: _confirmSubmitDialog,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF15803D), Color(0xFF22C55E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF15803D,
                              ).withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.send_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Kumpulkan',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
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
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
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
                    MathHtmlFormatter.buildQuestionImage(
                      img,
                      height: 110,
                      borderRadius: BorderRadius.circular(8),
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

  Widget _buildBlockedScreen() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _confirmExitDialog();
        }
      },
      child: Scaffold(
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
                const SizedBox(height: 24),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Memeriksa status izin dari pengawas...'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                      final data = await MonitoringService.instance.getStudentData(
                        widget.token,
                        widget.studentNis,
                      );
                      final status = data?['status']?.toString();
                      final isBlockedInDb =
                          data?['is_blocked'] == true || status == 'BLOCKED';
                      if (!isBlockedInDb &&
                          (status == 'ONLINE' ||
                              status == 'ACTIVE' ||
                              data?['unblocked_at'] != null)) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove(
                          'blocked_${widget.token}_${widget.studentNis}',
                        );
                        if (mounted) {
                          setState(() {
                            _isBlocked = false;
                            _violations = 0;
                          });
                          _enterImmersiveMode();
                          SecurityService.instance.reapply();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Blokir telah dibuka! Silakan lanjutkan ujian.',
                              ),
                              backgroundColor: AppColors.primaryGreen,
                            ),
                          );
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Status masih diblokir. Harap hubungi Pengawas Ujian.',
                              ),
                              backgroundColor: Colors.black87,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: Text(
                      'Periksa Status Blokir',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: TextButton.icon(
                    onPressed: () => _confirmExitDialog(),
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                    label: Text(
                      'Kumpulkan Jawaban & Keluar Ujian',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Dialog Edukasi & Regulasi Resmi Sistem Blocking Time (UTBK-SNBT)
  void _showBlockingTimeInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFEF3C7), Color(0xFFFFFBEB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFDE68A),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD97706).withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: Color(0xFFD97706),
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Sistem Blocking Time UTBK',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Sesuai Aturan Resmi BPPP & SNPMB Nasional',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFD97706),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildRuleRow(
                      Icons.timer_outlined,
                      'Waktu Terkunci per Subtes',
                      'Setiap subtes memiliki alokasi waktu tersendiri. Anda tidak dapat maju ke subtes berikutnya sebelum waktu habis.',
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildRuleRow(
                      Icons.lock_outline_rounded,
                      'Berpindah Otomatis (00:00)',
                      'Saat timer subtes mencapai 00:00, sistem komputer akan langsung mengalihkan layar ke subtes selanjutnya secara otomatis.',
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildRuleRow(
                      Icons.published_with_changes_rounded,
                      'Periksa Kembali Jawaban',
                      'Gunakan sisa menit yang ada untuk mengecek kembali jawaban & nomor ragu-ragu. Begitu berpindah, Anda tidak bisa kembali ke subtes ini.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Mengerti, Lanjutkan Pengerjaan',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRuleRow(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFFD97706)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  color: const Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmFinishSubtestDialog() {
    if (_isSnbt) {
      _showBlockingTimeInfoDialog();
      return;
    }
    final subtest = _subtests[_currentSubtestIndex];
    final activeQ = _getActiveQuestions();
    int answered = 0;
    for (final q in activeQ) {
      if (_answers.containsKey(q.soalId)) answered++;
    }
    final unanswered = activeQ.length - answered;
    final hasNext = _currentSubtestIndex < _subtests.length - 1;
    final nextSubtest = hasNext ? _subtests[_currentSubtestIndex + 1] : null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge Icon Header
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFEF3C7), Color(0xFFFFFBEB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFDE68A),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD97706).withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFFD97706),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),

              // Judul & Subjudul
              Text(
                'Lanjut ke Subtest Berikutnya?',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Pastikan Anda telah memeriksa jawaban sebelum melanjutkan.',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),

              // Alur Subtest & Ringkasan Pengerjaan
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    // Subtest Saat Ini
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Subtest ${_currentSubtestIndex + 1} Selesai',
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF16A34A),
                                ),
                              ),
                              Text(
                                subtest.judul,
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (nextSubtest != null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                      ),
                      // Subtest Berikutnya
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.play_circle_fill_rounded,
                              size: 16,
                              color: Color(0xFFD97706),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Subtest Selanjutnya (${_currentSubtestIndex + 2}/${_subtests.length})',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFD97706),
                                  ),
                                ),
                                Text(
                                  nextSubtest.judul,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1E293B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (nextSubtest.durasiMenit > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Text(
                                '${nextSubtest.durasiMenit} Menit',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF92400E),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                    ),

                    // Baris Indikator Soal Terjawab
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.task_alt_rounded,
                                size: 16,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Terjawab',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    '$answered / ${activeQ.length} Soal',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: const Color(0xFFE2E8F0),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                unanswered > 0
                                    ? Icons.error_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 16,
                                color: unanswered > 0
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Belum Dijawab',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    unanswered > 0
                                        ? '$unanswered Soal'
                                        : 'Lengkap',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: unanswered > 0
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF16A34A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Peringatan Regulasi UTBK
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Regulasi Ujian: Begitu Anda berpindah subtes, lembar jawaban subtes ini dikunci permanen, sisa waktu akan hangus, dan Anda tidak dapat kembali lagi.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFF92400E),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tombol Aksi: Lanjut Sekarang (Utama) & Periksa Kembali (Sekunder)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _handleSubtestTimeExpired();
                  },
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'Lanjut ke Subtest Berikutnya',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Periksa Kembali Jawaban',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSubmitDialog() {
    if (_isSnbt &&
        _isPerSubtest &&
        _currentSubtestIndex < _subtests.length - 1) {
      _showBlockingTimeInfoDialog();
      return;
    }

    final answeredCount = _answers.length;
    final total = _allQuestions.length;
    final raguCount = _raguRagu.length;
    final unanswered = total - answeredCount;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge Icon Header
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDCFCE7), Color(0xFFF0FDF4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFBBF7D0),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.assignment_turned_in_rounded,
                  color: AppColors.primaryGreen,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),

              // Judul & Subjudul
              Text(
                'Kumpulkan Lembar Jawaban?',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Seluruh sesi ujian akan diselesaikan dan nilai akan dihitung.',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),

              // Kartu Ringkasan Pengerjaan
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Terjawab',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    '$answeredCount / $total Soal',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: const Color(0xFFE2E8F0),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                unanswered > 0
                                    ? Icons.error_outline_rounded
                                    : Icons.task_alt_rounded,
                                size: 16,
                                color: unanswered > 0
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Belum Dijawab',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    unanswered > 0
                                        ? '$unanswered Soal'
                                        : '0 Soal',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: unanswered > 0
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF16A34A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (raguCount > 0) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.help_outline_rounded,
                            size: 15,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Ditandai Ragu-Ragu: ',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            '$raguCount butir soal',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tombol Aksi
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _submitExam();
                  },
                  icon: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'Kumpulkan Ujian Sekarang',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Periksa Kembali Jawaban',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmExitDialog() {
    final answeredCount = _answers.length;
    final total = _allQuestions.length;
    final remainingTimeStr = _formatDuration(_remainingSeconds);
    final isPerSub = _isPerSubtest && _currentSubtestIndex < _subtests.length;
    final currentSubTitle = isPerSub
        ? _subtests[_currentSubtestIndex].judul
        : (_package?.namaPaket ?? 'Ujian');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge Icon Header
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFEE2E2), Color(0xFFFEF2F2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFECACA),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFDC2626),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),

              // Judul & Subjudul
              Text(
                'Keluar dari Sesi Ujian?',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Sesi pengerjaan Anda saat ini masih berlangsung.',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),

              // Ringkasan Pengerjaan
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.assignment_outlined,
                            size: 16,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            currentSubTitle,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E293B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 16,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sisa Waktu',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    remainingTimeStr,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          color: const Color(0xFFE2E8F0),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 16,
                                color: AppColors.primaryGreen,
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Terjawab',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                  Text(
                                    '$answeredCount / $total Soal',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Peringatan Regulasi Ujian
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Keluar sekarang akan mengakhiri sesi ujian dan jawaban yang telah Anda pilih akan langsung dikumpulkan.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFF92400E),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tombol Aksi: Tetap Lanjutkan (Utama) & Kumpulkan & Keluar (Sekunder)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'Tetap Lanjutkan Ujian',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _submitExam(autoSubmit: false);
                  },
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFDC2626),
                    size: 16,
                  ),
                  label: Text(
                    'Kumpulkan & Keluar Sekarang',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    backgroundColor: const Color(0xFFFEF2F2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
