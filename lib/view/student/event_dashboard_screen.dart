import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/exam_question_model.dart';
import '../../models/tryout_schedule_model.dart';
import '../../services/exam_cache_service.dart';
import '../../services/student_tryout_history_service.dart';
import '../../services/tryout_schedule_service.dart';
import '../pre_exam_checklist.dart';
import 'student_exam_session_screen.dart';
import 'tryout_discussion_screen.dart';

enum _EventScheduleStatus { open, belumMulai, sudahSelesai }

class _LeaderboardEntry {
  final String nama;
  final String nis;
  final int skor;
  final String predikat;
  final bool isMe;

  _LeaderboardEntry({
    required this.nama,
    required this.nis,
    required this.skor,
    required this.predikat,
    this.isMe = false,
  });
}

/// Dashboard Khusus Event & Tryout Berbayar (Diadaptasi dari myOLCv2 dengan sentuhan ExamGO)
class EventDashboardScreen extends StatefulWidget {
  final String eventId;
  final String? eventToken;
  final TryoutSchedule? initialSchedule;

  const EventDashboardScreen({
    super.key,
    required this.eventId,
    this.eventToken,
    this.initialSchedule,
  });

  @override
  State<EventDashboardScreen> createState() => _EventDashboardScreenState();
}

class _EventDashboardScreenState extends State<EventDashboardScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  bool _isLoading = true;
  TryoutSchedule? _schedule;
  String _studentName = '';
  String _studentNis = '';

  bool _sudahDikerjakan = false;
  int? _myScore;
  int? _myRank;
  StudentTryoutHistoryItem? _myHistory;

  List<_LeaderboardEntry> _leaderboard = [];

  // Theme Palette (Emerald - Teal)
  static const Color _kTealDeep = Color(0xFF004D40);
  static const Color _kTealD = Color(0xFF00695C);
  static const Color _kTeal = Color(0xFF00897B);
  static const Color _kAccent = Color(0xFF64FFDA);
  static const Color _kBg = Color(0xFFF4FBF9);

  String get _greet {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat Pagi';
    if (h < 15) return 'Selamat Siang';
    if (h < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  String get _shortDate {
    final n = DateTime.now();
    const d = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${d[n.weekday - 1]}, ${n.day} ${m[n.month - 1]} ${n.year}';
  }

  String _fmtTanggal(String raw) {
    if (raw.isEmpty) return 'Fleksibel';
    try {
      final p = raw.split('-');
      if (p.length == 3) {
        const bulan = [
          'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
          'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
        ];
        final mIdx = int.tryParse(p[1]) ?? 1;
        return '${p[2]} ${bulan[mIdx - 1]} ${p[0]}';
      }
    } catch (_) {}
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    _loadAllData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await _loadStudentIdentity();
    await _loadSchedule();
    await _checkSubmissionStatus();
    await _loadLeaderboard();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadStudentIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    _studentName = prefs.getString('student_name') ?? '';
    _studentNis = prefs.getString('student_nis') ?? '';

    if (_studentName.isEmpty || _studentNis.isEmpty) {
      if (!mounted) return;
      final identity = await PreExamChecklistDialog.show(context, 'Data Peserta Event');
      if (identity != null) {
        _studentName = identity['name'] ?? 'Peserta';
        _studentNis = identity['nis'] ?? '-';
      } else {
        _studentName = 'Peserta Event';
        _studentNis = 'ID_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      }
    }
  }

  Future<void> _loadSchedule() async {
    if (widget.initialSchedule != null) {
      _schedule = widget.initialSchedule;
      return;
    }
    final effectiveId = widget.eventId.trim();
    try {
      final doc = await FirebaseFirestore.instance.collection('paket_tryout').doc(effectiveId).get();
      if (doc.exists) {
        _schedule = TryoutSchedule.fromMap(doc.id, doc.data() ?? {});
      }
    } catch (_) {}

    // Fallback 1: cari by target_exam_id jika eventId adalah kode target exam
    if (_schedule == null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('paket_tryout')
            .where('target_exam_id', isEqualTo: effectiveId.toUpperCase())
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          _schedule = TryoutSchedule.fromMap(snap.docs.first.id, snap.docs.first.data());
        }
      } catch (_) {}
    }

    // Fallback 2: cari dari daftar aktif lokal / GAS
    if (_schedule == null) {
      final all = await TryoutScheduleService.instance.getActiveSchedules();
      final match = all.where((s) =>
        s.paketId.toUpperCase() == effectiveId.toUpperCase() ||
        (s.targetExamId != null && s.targetExamId!.toUpperCase() == effectiveId.toUpperCase())
      ).firstOrNull;
      if (match != null) _schedule = match;
    }

    // Default fallback jika tidak ditemukan
    _schedule ??= TryoutSchedule(
      paketId: widget.eventId,
      namaPaket: 'Event Tryout Nasional',
      jenisTest: 'EVENT',
      durasiMenit: 90,
      tanggal: '',
    );
  }

  Future<void> _checkSubmissionStatus() async {
    final effectivePaketId = _schedule?.paketId ?? widget.eventId;

    // 1. Cek dari Riwayat Lokal Siswa
    final localList = await StudentTryoutHistoryService.instance.getHistory();
    final localMatch = localList.where((h) =>
      h.token == effectivePaketId ||
      h.token == widget.eventId ||
      (_schedule?.targetExamId != null && h.token == _schedule!.targetExamId)
    ).firstOrNull;

    if (localMatch != null) {
      _sudahDikerjakan = true;
      _myScore = localMatch.finalScore;
      _myHistory = localMatch;
    }

    // 2. Verifikasi ke Firestore (jawaban_tryout)
    if (_studentNis.isNotEmpty) {
      try {
        var doc = await FirebaseFirestore.instance
            .collection('jawaban_tryout')
            .doc('${_studentNis}_$effectivePaketId')
            .get();
        if (!doc.exists && effectivePaketId != widget.eventId) {
          doc = await FirebaseFirestore.instance
              .collection('jawaban_tryout')
              .doc('${_studentNis}_${widget.eventId}')
              .get();
        }
        if (doc.exists) {
          final data = doc.data()!;
          _sudahDikerjakan = true;
          _myScore = (data['skor_akhir'] as num?)?.toInt() ?? _myScore;
        }
      } catch (_) {}
    }
  }

  Future<void> _loadLeaderboard() async {
    final effectivePaketId = _schedule?.paketId ?? widget.eventId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('jawaban_tryout')
          .where('token', isEqualTo: effectivePaketId)
          .get();

      if (snap.docs.isNotEmpty) {
        final list = snap.docs.map((d) {
          final m = d.data();
          final nis = m['nis']?.toString() ?? '';
          final score = (m['skor_akhir'] as num?)?.toInt() ?? 0;
          return _LeaderboardEntry(
            nama: m['nama_peserta']?.toString() ?? 'Peserta',
            nis: nis,
            skor: score,
            predikat: m['predikat']?.toString() ?? '-',
            isMe: _studentNis.isNotEmpty && nis == _studentNis,
          );
        }).toList();

        list.sort((a, b) => b.skor.compareTo(a.skor));

        final myIdx = list.indexWhere((e) => e.isMe);
        if (myIdx >= 0) {
          _myRank = myIdx + 1;
        }

        if (mounted) {
          setState(() {
            _leaderboard = list;
          });
        }
      }
    } catch (_) {}
  }

  _EventScheduleStatus _checkScheduleStatus() {
    final s = _schedule;
    if (s == null || s.isLifetime || s.tanggal.isEmpty) {
      return _EventScheduleStatus.open;
    }
    try {
      final now = DateTime.now();
      final p = s.tanggal.split('-');
      final year = int.parse(p[0]);
      final month = int.parse(p[1]);
      final day = int.parse(p[2]);

      final jamP = s.jamMulai.split(':');
      final startH = int.tryParse(jamP[0]) ?? 8;
      final startM = jamP.length > 1 ? (int.tryParse(jamP[1]) ?? 0) : 0;
      final start = DateTime(year, month, day, startH, startM);

      final endP = s.jamSelesai.split(':');
      final endH = int.tryParse(endP[0]) ?? 23;
      final endM = endP.length > 1 ? (int.tryParse(endP[1]) ?? 59) : 59;
      final end = DateTime(year, month, day, endH, endM);

      if (now.isBefore(start)) return _EventScheduleStatus.belumMulai;
      if (now.isAfter(end)) return _EventScheduleStatus.sudahSelesai;
      return _EventScheduleStatus.open;
    } catch (_) {
      return _EventScheduleStatus.open;
    }
  }

  Future<void> _startExam() async {
    final sch = _schedule;
    if (sch == null) return;

    // Tampilkan verifikasi identitas & konfirmasi regulasi anti-curang
    final identity = await PreExamChecklistDialog.show(context, sch.namaPaket);
    if (identity == null) return;
    setState(() {
      _studentName = identity['name'] ?? _studentName;
      _studentNis = identity['nis'] ?? _studentNis;
    });

    if (!mounted) return;

    // Siswa event tidak terpotong kuota free dan tidak dibatasi limit 5x
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentExamSessionScreen(
          token: sch.paketId,
          studentName: _studentName,
          studentNis: _studentNis,
          isEvent: true,
        ),
      ),
    );

    // Refresh setelah selesai
    if (mounted) {
      _loadAllData();
    }
  }

  Future<void> _openDiscussion() async {
    if (_myHistory != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TryoutDiscussionScreen(
            title: _myHistory!.namaPaket,
            kategori: _myHistory!.kategori,
            questions: _myHistory!.questions,
            studentAnswers: _myHistory!.jawaban,
            score: _myHistory!.finalScore,
            statusKelulusan: _myHistory!.statusKelulusan,
          ),
        ),
      );
      return;
    }

    // Jika riwayat offline kosong, coba muat dari Firestore & Cache lokal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: _kTeal),
      ),
    );

    try {
      final effectivePaketId = _schedule?.paketId ?? widget.eventId;
      final examData = await ExamCacheService.instance.downloadAndCacheExam(
        paketId: effectivePaketId,
        initialSchedule: _schedule,
      );

      Map<String, String> answers = {};
      int score = _myScore ?? 0;
      String statusKelulusan = 'SELESAI';

      if (_studentNis.isNotEmpty) {
        var doc = await FirebaseFirestore.instance
            .collection('jawaban_tryout')
            .doc('${_studentNis}_$effectivePaketId')
            .get();
        if (!doc.exists && effectivePaketId != widget.eventId) {
          doc = await FirebaseFirestore.instance
              .collection('jawaban_tryout')
              .doc('${_studentNis}_${widget.eventId}')
              .get();
        }
        if (doc.exists) {
          final data = doc.data()!;
          if (data['jawaban'] is Map) {
            final raw = data['jawaban'] as Map;
            raw.forEach((k, v) => answers[k.toString()] = v.toString());
          }
          score = (data['skor_akhir'] as num?)?.toInt() ?? score;
          statusKelulusan = data['status_kelulusan']?.toString() ?? statusKelulusan;
        }
      }

      if (mounted) {
        Navigator.pop(context); // Tutup loading
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TryoutDiscussionScreen(
              title: _schedule?.namaPaket ?? 'Pembahasan Event',
              kategori: _schedule?.jenisTest ?? ExamCategory.umum,
              questions: examData.questions,
              studentAnswers: answers,
              score: score,
              statusKelulusan: statusKelulusan,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat pembahasan: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _checkScheduleStatus();
    final canStart = (status == _EventScheduleStatus.open) && (!_sudahDikerjakan || (_schedule?.allowRetake ?? false));

    return Scaffold(
      backgroundColor: _kBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kTeal))
          : FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                color: _kTeal,
                backgroundColor: Colors.white,
                onRefresh: _loadAllData,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    _buildHeroAppBar(),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 60),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildScheduleCard(status),
                          const SizedBox(height: 14),
                          if (status != _EventScheduleStatus.open) ...[
                            _buildStatusBanner(status),
                            const SizedBox(height: 14),
                          ],
                          _buildPesertaCard(),
                          const SizedBox(height: 16),
                          _buildActionButtons(canStart, status),
                          const SizedBox(height: 24),
                          _buildLeaderboardSection(),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeroAppBar() {
    final sch = _schedule;
    final initial = _studentName.isNotEmpty ? _studentName[0].toUpperCase() : 'P';

    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      stretch: true,
      automaticallyImplyLeading: false,
      backgroundColor: _kTealDeep,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_kTealDeep, _kTealD, _kTeal],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // Decorative circle blobs
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -20,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kAccent.withValues(alpha: 0.06),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Greet, Short Date, Close
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _greet,
                                  style: GoogleFonts.poppins(
                                    color: _kAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  _studentName.split(' ').take(2).join(' '),
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            child: Text(
                              _shortDate,
                              style: GoogleFonts.poppins(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                            onPressed: () => Navigator.pop(context),
                            tooltip: 'Kembali',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.12),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Event Highlight Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_kAccent, Color(0xFF00E5FF)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'EXAMGO EVENT RESMI',
                                        style: GoogleFonts.poppins(
                                          color: _kAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (sch != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            sch.jenisTest,
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    sch?.namaPaket ?? 'Paket Tryout',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                              child: Text(
                                initial,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleCard(_EventScheduleStatus status) {
    final sch = _schedule;
    final statusColor = status == _EventScheduleStatus.open
        ? const Color(0xFF22C55E)
        : (status == _EventScheduleStatus.belumMulai ? const Color(0xFFF59E0B) : const Color(0xFF64748B));

    final statusLabel = status == _EventScheduleStatus.open
        ? 'Berlangsung'
        : (status == _EventScheduleStatus.belumMulai ? 'Segera' : 'Berakhir');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _kTeal.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kTealDeep, _kTeal]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_available_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Jadwal Pelaksanaan Ujian',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: _buildColInfo(
                    icon: Icons.calendar_today_rounded,
                    label: 'Tanggal',
                    value: _fmtTanggal(sch?.tanggal ?? ''),
                    color: _kTeal,
                  ),
                ),
                Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
                Expanded(
                  child: _buildColInfo(
                    icon: Icons.access_time_rounded,
                    label: 'Pukul',
                    value: sch != null && sch.jamMulai.isNotEmpty ? '${sch.jamMulai} - ${sch.jamSelesai}' : 'Bebas',
                    color: const Color(0xFF3B82F6),
                  ),
                ),
                Container(width: 1, height: 36, color: const Color(0xFFE2E8F0)),
                Expanded(
                  child: _buildColInfo(
                    icon: Icons.timer_rounded,
                    label: 'Durasi',
                    value: '${sch?.durasiMenit ?? 90} Mnt',
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColInfo({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 10, color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(_EventScheduleStatus status) {
    final sch = _schedule;
    final isBefore = status == _EventScheduleStatus.belumMulai;
    final color = isBefore ? const Color(0xFFF59E0B) : const Color(0xFF64748B);
    final icon = isBefore ? Icons.hourglass_top_rounded : Icons.lock_clock_rounded;
    final title = isBefore ? 'Ujian Belum Dimulai' : 'Waktu Ujian Telah Berakhir';
    final sub = isBefore
        ? 'Ujian dibuka pada ${_fmtTanggal(sch?.tanggal ?? '')} pukul ${sch?.jamMulai ?? '08:00'}.'
        : 'Waktu pengerjaan telah berakhir. Silakan tinjau nilai & pembahasan di bawah.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12.5, color: color),
                ),
                Text(
                  sub,
                  style: GoogleFonts.poppins(fontSize: 11, color: color.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPesertaCard() {
    final initial = _studentName.isNotEmpty ? _studentName[0].toUpperCase() : 'P';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kTeal.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: _kTeal.withValues(alpha: 0.15),
            child: Text(
              initial,
              style: GoogleFonts.poppins(color: _kTeal, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _studentName,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF0F172A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'NIS / ID: $_studentNis',
                  style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF64748B)),
                ),
                if (widget.eventToken != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Tiket: ${widget.eventToken}',
                    style: GoogleFonts.poppins(fontSize: 10, color: _kTeal, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          if (_myScore != null) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$_myScore',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _kTeal,
                  ),
                ),
                Text(
                  _myRank != null ? 'Peringkat #$_myRank' : 'Skor Akhir',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool canStart, _EventScheduleStatus status) {
    String label = 'Mulai Ujian Sekarang';
    if (_sudahDikerjakan) {
      label = (_schedule?.allowRetake ?? false) ? 'Kerjakan Ulang Ujian' : 'Ujian Sudah Dikerjakan ✅';
    } else if (status == _EventScheduleStatus.belumMulai) {
      label = 'Ujian Belum Dibuka';
    } else if (status == _EventScheduleStatus.sudahSelesai) {
      label = 'Waktu Ujian Selesai';
    }

    return Column(
      children: [
        // Primary Button: Mulai Ujian
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: canStart ? _startExam : null,
            icon: Icon(
              _sudahDikerjakan && !canStart ? Icons.check_circle_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
            label: Text(
              label,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kTeal,
              disabledBackgroundColor: _sudahDikerjakan ? const Color(0xFF10B981) : Colors.grey.shade400,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: canStart ? 4 : 0,
            ),
          ),
        ),
        if (_sudahDikerjakan) ...[
          const SizedBox(height: 10),
          // Secondary Button: Riwayat & Pembahasan
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _openDiscussion,
              icon: const Icon(Icons.menu_book_rounded, color: _kTeal, size: 18),
              label: Text(
                'Tinjau Jawaban & Pembahasan',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _kTeal,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kTeal, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLeaderboardSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Papan Peringkat Peserta',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Peringkat langsung peserta yang telah submit',
                    style: GoogleFonts.poppins(fontSize: 10.5, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_leaderboard.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.military_tech_outlined, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'Belum ada peserta yang mengumpulkan ujian.',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    Text(
                      'Jadilah yang pertama di papan peringkat!',
                      style: GoogleFonts.poppins(fontSize: 11, color: _kTeal, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _leaderboard.length.clamp(0, 10),
              separatorBuilder: (_, _) => const Divider(height: 14, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final entry = _leaderboard[index];
                final rank = index + 1;

                Color? badgeColor;
                if (rank == 1) badgeColor = const Color(0xFFFFB300); // Gold
                if (rank == 2) badgeColor = const Color(0xFF94A3B8); // Silver
                if (rank == 3) badgeColor = const Color(0xFFB45309); // Bronze

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  decoration: BoxDecoration(
                    color: entry.isMe ? _kTeal.withValues(alpha: 0.08) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: badgeColor != null
                            ? Icon(Icons.workspace_premium_rounded, color: badgeColor, size: 22)
                            : Text(
                                '#$rank',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: entry.isMe ? _kTeal : Colors.grey.shade200,
                        child: Text(
                          entry.nama.isNotEmpty ? entry.nama[0].toUpperCase() : '?',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: entry.isMe ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.nama + (entry.isMe ? ' (Kamu)' : ''),
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: entry.isMe ? FontWeight.bold : FontWeight.w600,
                                color: entry.isMe ? _kTealDeep : const Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'NIS: ${entry.nis.length > 4 ? '${entry.nis.substring(0, 4)}***' : entry.nis}',
                              style: GoogleFonts.poppins(fontSize: 10, color: const Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${entry.skor}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: entry.isMe ? _kTeal : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
