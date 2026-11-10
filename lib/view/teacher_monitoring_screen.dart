import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../constant/app_colors.dart';
import 'widgets/examgo_dialog.dart';

import 'package:examgo/constant/app_config.dart';
import 'package:examgo/services/monitoring_service.dart';
import 'package:examgo/widget/slide_to_unblock.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/exam_pdf_exporter.dart';

// ─── Konstanta Warna & Style ──────────────────────────────────────────────────
const _kGreen = Color(0xFF2E7D32);
const _kGreenL = Color(0xFF43A047);
const _kBg = Color(0xFFF0F4F8);

// ─── Konfigurasi Tipe Log ─────────────────────────────────────────────────────
class _ActivityType {
  final IconData icon;
  final Color color;
  final String label;
  const _ActivityType({
    required this.icon,
    required this.color,
    required this.label,
  });
}

const _activityTypes = <String, _ActivityType>{
  'EXIT_APP': _ActivityType(
    icon: Icons.exit_to_app_rounded,
    color: Color(0xFFE53935),
    label: 'Keluar Aplikasi',
  ),
  'EXIT_ATTEMPT': _ActivityType(
    icon: Icons.logout_rounded,
    color: Color(0xFFFF6F00),
    label: 'Percobaan Keluar',
  ),
  'SCREENSHOT': _ActivityType(
    icon: Icons.screenshot_monitor,
    color: Color(0xFF8E24AA),
    label: 'Percobaan Screenshot',
  ),
  'SCREEN_HIDDEN': _ActivityType(
    icon: Icons.visibility_off_rounded,
    color: Color(0xFF1565C0),
    label: 'Layar Tersembunyi',
  ),
  'ACTIVE': _ActivityType(
    icon: Icons.play_circle_rounded,
    color: Color(0xFF2E7D32),
    label: 'Mulai Ujian',
  ),
  'FINISHED': _ActivityType(
    icon: Icons.check_circle_rounded,
    color: Color(0xFF1976D2),
    label: 'Selesai Ujian',
  ),
  'BLOCKED': _ActivityType(
    icon: Icons.block_rounded,
    color: Color(0xFFE53935),
    label: 'Diblokir',
  ),
  'INFO': _ActivityType(
    icon: Icons.info_rounded,
    color: Color(0xFF0288D1),
    label: 'Info Sistem',
  ),
};

_ActivityType _getActivityType(String type) =>
    _activityTypes[type] ??
    const _ActivityType(
      icon: Icons.radio_button_checked,
      color: Color(0xFF607D8B),
      label: 'Aktivitas',
    );

// ─── Daftar Sesi Ujian (List Screen) ─────────────────────────────────────────
class TeacherMonitoringListScreen extends StatefulWidget {
  const TeacherMonitoringListScreen({super.key});
  @override
  State<TeacherMonitoringListScreen> createState() =>
      _TeacherMonitoringListScreenState();
}

class _TeacherMonitoringListScreenState
    extends State<TeacherMonitoringListScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, String>> _history = [];
  bool _loading = true;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _loadHistory();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('teacher_exam_history') ?? [];

    // Auto-cleanup sesi ujian yang berumur >= 10 hari dan siswanya 0
    final validList = <String>[];
    for (final item in list) {
      final parts = item.split('|');
      final examId = parts.isNotEmpty ? parts[0] : '';
      final timestamp = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
      final createdAt = DateTime.fromMillisecondsSinceEpoch(timestamp);

      if (timestamp > 0 && DateTime.now().difference(createdAt).inDays >= 10) {
        final cleaned = await MonitoringService.instance.cleanupIfAbandoned(
          examId,
          createdAt,
        );
        if (cleaned) continue;
      }
      validList.add(item);
    }

    if (validList.length != list.length) {
      await prefs.setStringList('teacher_exam_history', validList);
    }

    final parsed = validList.map((item) {
      final parts = item.split('|');
      return {
        'examId': parts.isNotEmpty ? parts[0] : '',
        'title': parts.length > 1 ? parts[1] : 'Ujian',
        'timestamp': parts.length > 2 ? parts[2] : '0',
        'url': parts.length > 3 ? parts[3] : '',
      };
    }).toList();
    if (mounted) {
      setState(() {
        _history = parsed;
        _loading = false;
      });
    }
  }

  Future<void> _confirmDelete(Map<String, String> item) async {
    final confirmed = await ExamGoDialog.danger(
      context,
      title: 'Hapus Sesi Ujian?',
      message:
          'Sesi "${item['title']}" (Token: ${item['examId']}) beserta seluruh data siswa dan log aktivitasnya akan dihapus permanen.',
      confirmText: 'Ya, Hapus',
    );

    if (confirmed != true) return;
    await _deleteSession(item['examId']!);
  }

  void _showQrDialog(Map<String, String> item) {
    final token = item['examId'] ?? '';
    final title = item['title'] ?? 'Ujian';
    final url = item['url'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FFFA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Token: $token',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F766E),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: QrImageView(
                  data: url.isNotEmpty ? url : token,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Minta siswa membuka ExamGO dan memindai QR ini atau mengetikkan token ujian di atas.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: Text('Tutup', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareExamInfo(Map<String, String> item) {
    final title = item['title'] ?? 'Ujian';
    final token = item['examId'] ?? '';
    final msg = '*INFORMASI SESI UJIAN EXAMGO*\n'
        '📋 *Ujian:* $title\n'
        '🔑 *Kode Token:* *$token*\n\n'
        '📲 *Langkah Mengikuti Ujian:*\n'
        '1. Buka aplikasi *ExamGO* di smartphone Anda.\n'
        '2. Pada menu Beranda, masukkan Token di atas pada kolom "Token Ujian" atau ketuk "🎯 Masuk Event".\n'
        '3. Anda akan langsung diarahkan ke lembar soal ujian.\n\n'
        '_Catatan: Pastikan koneksi internet stabil & patuhi tata tertib ujian._';
    Clipboard.setData(ClipboardData(text: msg));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pesan info ujian & token $token disalin! Siap dibagikan ke WhatsApp siswa.', style: GoogleFonts.poppins(fontSize: 12)),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _deleteSession(String examId) async {
    await MonitoringService.instance.deleteExamSession(examId);
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('teacher_exam_history') ?? [];
    list.removeWhere((e) => e.startsWith(examId));
    await prefs.setStringList('teacher_exam_history', list);
    if (mounted) {
      setState(() => _history.removeWhere((e) => e['examId'] == examId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text('Sesi ujian berhasil dihapus', style: GoogleFonts.poppins()),
            ],
          ),
          backgroundColor: _kGreenL,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Gradient SliverAppBar ──────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            stretch: true,
            backgroundColor: _kGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: 'Segarkan Riwayat',
                onPressed: _loadHistory,
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                'Riwayat Ujian & Token Guru',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF1B5E20),
                          Color(0xFF2E7D32),
                          Color(0xFF43A047),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20,
                    left: -20,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 50,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.monitor_heart_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_history.length} Sesi Ujian',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Body ──────────────────────────────────────────────
          _loading
              ? const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: _kGreenL),
                  ),
                )
              : _history.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.12),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.qr_code_2_rounded,
                            size: 72,
                            color: Colors.grey.shade300,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Belum Ada Sesi Ujian',
                          style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Buat QR Code ujian terlebih dahulu\npada mode guru untuk memulai monitoring.',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final item = _history[i];
                      final ts = int.tryParse(item['timestamp'] ?? '0') ?? 0;
                      final date = DateTime.fromMillisecondsSinceEpoch(ts);
                      return _buildSessionCard(item, date, i);
                    }, childCount: _history.length),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(Map<String, String> item, DateTime date, int index) {
    final dayNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Ags',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final dayName = dayNames[date.weekday - 1];
    final monthName = monthNames[date.month - 1];
    final dateStr = '$dayName, ${date.day} $monthName ${date.year}';
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Dismissible(
      key: Key(item['examId']!),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmDelete(item);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade300, Colors.red.shade600],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.delete_sweep_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              'Hapus',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeacherMonitoringDetailScreen(
                  examId: item['examId']!,
                  title: item['title']!,
                  url: item['url'],
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon Container
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_kGreen, _kGreenL],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _kGreenL.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.qr_code_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] ?? 'Ujian',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 11.5,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 11.5,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  timeStr,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
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
                          color: _kGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Live',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _kGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Row Token Badge & Format Type
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Prominent Token Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.key_rounded,
                              size: 13,
                              color: Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'TOKEN: ${item['examId']}',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF15803D),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: item['examId'] ?? ''),
                                );
                                HapticFeedback.lightImpact();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Token ${item['examId']} disalin!',
                                      style: GoogleFonts.poppins(fontSize: 12),
                                    ),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: const Icon(
                                Icons.copy_rounded,
                                size: 13,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Builder(
                        builder: (_) {
                          final rawUrl = item['url'] ?? '';
                          final isExt =
                              rawUrl.startsWith('http://') ||
                              rawUrl.startsWith('https://');
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: isExt
                                  ? const Color(0xFFEFF6FF)
                                  : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isExt
                                    ? const Color(0xFFBFDBFE)
                                    : const Color(0xFFA7F3D0),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              isExt ? 'Tautan Eksternal' : 'Soal CBT Native',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isExt
                                    ? const Color(0xFF1D4ED8)
                                    : const Color(0xFF065F46),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 6),
                  // Quick Actions Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showQrDialog(item),
                        icon: const Icon(
                          Icons.qr_code_2_rounded,
                          size: 15,
                          color: Color(0xFF0F766E),
                        ),
                        label: Text(
                          'Lihat QR',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F766E),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _shareExamInfo(item),
                        icon: const Icon(
                          Icons.share_rounded,
                          size: 14,
                          color: Color(0xFF2563EB),
                        ),
                        label: Text(
                          'Bagikan',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeacherMonitoringDetailScreen(
                              examId: item['examId']!,
                              title: item['title']!,
                              url: item['url'],
                            ),
                          ),
                        ),
                        icon: const Icon(
                          Icons.monitor_heart_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Pantau Live',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: _kGreen,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Detail Sesi Ujian (Daftar Siswa) ────────────────────────────────────────
class TeacherMonitoringDetailScreen extends StatefulWidget {
  final String examId;
  final String title;
  final String? url;

  const TeacherMonitoringDetailScreen({
    super.key,
    required this.examId,
    required this.title,
    this.url,
  });

  @override
  State<TeacherMonitoringDetailScreen> createState() =>
      _TeacherMonitoringDetailScreenState();
}

class _TeacherMonitoringDetailScreenState
    extends State<TeacherMonitoringDetailScreen>
    with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  String _scoreSearchQuery = '';
  String _selectedFilter = 'Semua';
  bool _isExporting = false;
  bool _isExportingPdf = false;
  bool _isNativeExam = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _registerTokenForThisExam();
    _checkExamSource();
  }

  Future<void> _checkExamSource() async {
    final rawUrl = widget.url?.trim() ?? '';
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      if (mounted) setState(() => _isNativeExam = false);
      return;
    }
    if (rawUrl.startsWith('EXAMGO_TRYOUT://') ||
        rawUrl.startsWith('EXAMGO_EVENT://')) {
      if (mounted) setState(() => _isNativeExam = true);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('paket_tryout')
          .doc(widget.examId)
          .get();
      if (mounted) {
        setState(() {
          _isNativeExam = doc.exists;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isNativeExam = !rawUrl.startsWith('http');
        });
      }
    }
  }

  /// Mendaftarkan token guru HANYA untuk ujian ini, agar notifikasi terisolasi per pengawas.
  Future<void> _registerTokenForThisExam() async {
    if (AppConfig.gasUrl.isEmpty || AppConfig.gasApiKey.isEmpty) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await http
          .post(
            Uri.parse(AppConfig.gasUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'apiKey': AppConfig.gasApiKey,
              'action': 'registerToken',
              'token': token,
              'examId': widget.examId,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {}); // Memicu ulang FutureBuilder
        },
        color: _kGreen,
        child: FutureBuilder<QuerySnapshot>(
          future: MonitoringService.instance.getExamStudents(widget.examId),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];

            // ── Hitung Metrik ────────────────────────────────────
            int activeCount = 0;
            int blockedCount = 0;
            int finishedCount = 0;
            int offlineCount = 0;
            int violationTotal = 0;
            int lowBatteryCount = 0;

            final allStudents = docs.map((d) {
              final data = d.data() as Map<String, dynamic>;
              final rawName = data['name'] as String?;
              final name = (rawName == null || rawName.trim().isEmpty)
                  ? 'Anonim'
                  : rawName;
              final rawNis = data['nis'] as String?;
              final nis = (rawNis == null || rawNis.trim().isEmpty)
                  ? '-'
                  : rawNis;
              final status = data['status'] as String? ?? 'OFFLINE';
              final violations = data['violations'] as int? ?? 0;
              final battery = data['battery_level'] as int? ?? 0;
              final lastPing = data['last_ping'] as Timestamp?;

              final isOffline =
                  lastPing == null ||
                  DateTime.now().difference(lastPing.toDate()).inMinutes > 10;
              final displayStatus = isOffline ? 'OFFLINE' : status;

              return {
                'name': name,
                'nis': nis,
                'status': displayStatus,
                'violations': violations,
                'battery': battery,
                'last_ping': lastPing,
                'data': data,
              };
            }).toList();

            for (var s in allStudents) {
              final st = s['status'] as String;
              if (st == 'ACTIVE') {
                activeCount++;
              } else if (st == 'BLOCKED') {
                blockedCount++;
              } else if (st == 'FINISHED') {
                finishedCount++;
              } else {
                offlineCount++;
              }
              violationTotal += s['violations'] as int;
              if ((s['battery'] as int) <= 20) {
                lowBatteryCount++;
              }
            }

            // Filter
            final filteredStudents = allStudents.where((s) {
              final q = _searchQuery.toLowerCase();
              final nameMatch = (s['name'] as String).toLowerCase().contains(q);
              final nisMatch = (s['nis'] as String).toLowerCase().contains(q);
              if (!nameMatch && !nisMatch) return false;
              switch (_selectedFilter) {
                case 'Aktif':
                  return s['status'] == 'ACTIVE';
                case 'Melanggar':
                  return (s['violations'] as int) > 0 ||
                      s['status'] == 'BLOCKED';
                case 'Selesai':
                  return s['status'] == 'FINISHED';
                case 'Offline':
                  return s['status'] == 'OFFLINE';
                default:
                  return true;
              }
            }).toList();

            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                // ── Custom SliverAppBar ──────────────────────────
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final isCollapsed = constraints.scrollOffset > 130;
                    return SliverAppBar(
                      expandedHeight: 210,
                      pinned: true,
                      stretch: true,
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      centerTitle: true,
                      title: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: isCollapsed ? 1.0 : 0.0,
                        child: Text(
                          widget.title,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                          ),
                          tooltip: 'Segarkan Data',
                          onPressed: () {
                            setState(() {});
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(20),
                        child: Container(
                          height: 20,
                          decoration: const BoxDecoration(
                            color: _kBg,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(30),
                            ),
                          ),
                        ),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        collapseMode: CollapseMode.pin,
                        background: Stack(
                          children: [
                            // Elegant Background Pattern / Gradient
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF1B5E20),
                                    Color(0xFF2E7D32),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                            Positioned(
                              top: -40,
                              right: -40,
                              child: Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                            ),
                            SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  50,
                                  24,
                                  32,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.2,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF69F0AE),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'LIVE',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const _LiveClockText(
                                          color: Colors.white70,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      widget.title,
                                      style: GoogleFonts.poppins(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${docs.length} Peserta Terdaftar',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              body: Column(
                children: [
                  // ── Tab Bar Navigasi: Aktivitas Live vs Rekap Nilai ────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: _kGreen,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: _kGreen.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey.shade600,
                        labelStyle: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelStyle: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                        tabs: [
                          const Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.sensors_rounded, size: 16),
                                SizedBox(width: 6),
                                Text('Aktivitas Live'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isNativeExam
                                      ? Icons.leaderboard_rounded
                                      : Icons.link_off_rounded,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isNativeExam ? 'Rekap Nilai' : 'Rekap Nilai',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Konten Tab ─────────────────────────────────
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // Tab 1: Aktivitas Live
                        _buildLiveTab(
                          activeCount: activeCount,
                          blockedCount: blockedCount,
                          finishedCount: finishedCount,
                          offlineCount: offlineCount,
                          violationTotal: violationTotal,
                          lowBatteryCount: lowBatteryCount,
                          totalStudents: docs.length,
                          filteredStudents: filteredStudents,
                          isLoading:
                              snapshot.connectionState ==
                              ConnectionState.waiting,
                          hasError: snapshot.hasError,
                          errorMessage: snapshot.error?.toString(),
                        ),

                        // Tab 2: Rekap Nilai Siswa
                        _buildScoreRekapTab(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLiveTab({
    required int activeCount,
    required int blockedCount,
    required int finishedCount,
    required int offlineCount,
    required int violationTotal,
    required int lowBatteryCount,
    required int totalStudents,
    required List<Map<String, dynamic>> filteredStudents,
    required bool isLoading,
    required bool hasError,
    required String? errorMessage,
  }) {
    return Column(
      children: [
        // ── Dashboard Metrik ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            children: [
              _buildTopMetricRow(
                activeCount,
                blockedCount,
                finishedCount,
                offlineCount,
                totalStudents,
              ),
              const SizedBox(height: 10),
              _buildBottomMetricRow(
                violationTotal,
                lowBatteryCount,
                totalStudents,
              ),
            ],
          ),
        ),

        // ── Search & Filter ───────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            children: [
              // Search
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Cari nama atau NIS siswa...',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade400,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.grey.shade400,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              color: Colors.grey.shade400,
                            ),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
              ),
              const SizedBox(height: 10),
              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in [
                      'Semua',
                      'Aktif',
                      'Melanggar',
                      'Selesai',
                      'Offline',
                    ])
                      _buildFilterChip(f),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ── List Siswa ─────────────────────────────────
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: _kGreenL))
              : hasError
              ? _buildLiveErrorCard(errorMessage)
              : filteredStudents.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filteredStudents.length,
                  itemBuilder: (context, index) =>
                      _buildStudentCard(filteredStudents[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildScoreRekapTab() {
    // 1. Jika sumber ujian dari URL eksternal (Google Form / CBT Web) -> nonaktifkan
    if (!_isNativeExam) {
      return _buildExternalUrlDisabledRekapView();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jawaban_tryout')
          .where('token', isEqualTo: widget.examId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kGreenL),
          );
        }
        if (snapshot.hasError) {
          return _buildFirestoreErrorCard(snapshot.error);
        }

        final docs = snapshot.data?.docs ?? [];
        final List<Map<String, dynamic>> allScores = docs.map((d) {
          final data = d.data() as Map<String, dynamic>;
          final name = data['nama_peserta']?.toString() ?? 'Anonim';
          final nis = data['nis']?.toString() ?? '-';
          final skor = (data['skor_akhir'] as num?)?.toInt() ?? 0;
          final benar = (data['jumlah_benar'] as num?)?.toInt() ?? 0;
          final salah = (data['jumlah_salah'] as num?)?.toInt() ?? 0;
          final totalSoal = (data['total_soal'] as num?)?.toInt() ?? 0;
          final kategori = data['kategori']?.toString() ?? 'umum';
          final subtestScores =
              (data['subtest_scores'] as Map<String, dynamic>?) ?? {};
          final submittedAt = data['submitted_at'] as Timestamp?;

          return {
            'name': name,
            'nis': nis,
            'skor': skor,
            'benar': benar,
            'salah': salah,
            'totalSoal': totalSoal,
            'kategori': kategori,
            'subtestScores': subtestScores,
            'submittedAt': submittedAt,
          };
        }).toList();

        // Urutkan nilai tertinggi ke terendah
        allScores.sort(
          (a, b) => (b['skor'] as int).compareTo(a['skor'] as int),
        );

        // Filter pencarian
        final filtered = allScores.where((s) {
          if (_scoreSearchQuery.trim().isEmpty) return true;
          final q = _scoreSearchQuery.toLowerCase();
          final nameMatch = (s['name'] as String).toLowerCase().contains(q);
          final nisMatch = (s['nis'] as String).toLowerCase().contains(q);
          return nameMatch || nisMatch;
        }).toList();

        // Hitung statistik nilai
        final totalSubmissions = allScores.length;
        final avgScore = totalSubmissions > 0
            ? (allScores.fold<int>(
                        0,
                        (total, s) => total + (s['skor'] as int),
                      ) /
                      totalSubmissions)
                  .round()
            : 0;
        final maxScore = totalSubmissions > 0
            ? (allScores.first['skor'] as int)
            : 0;
        final minScore = totalSubmissions > 0
            ? (allScores.last['skor'] as int)
            : 0;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          physics: const BouncingScrollPhysics(),
          children: [
            // ── Kartu Ringkasan & Tombol Ekspor CSV ────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: _kGreen.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rekapitulasi Nilai Siswa',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '$totalSubmissions Siswa Telah Mengumpulkan',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: (_isExporting || _isExportingPdf)
                                ? null
                                : () => _exportToPdf(allScores),
                            icon: _isExportingPdf
                                ? const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _kGreen,
                                    ),
                                  )
                                : const Icon(
                                    Icons.picture_as_pdf_rounded,
                                    size: 15,
                                    color: _kGreen,
                                  ),
                            label: Text(
                              _isExportingPdf ? 'Menyusun...' : 'Unduh PDF',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: _kGreen,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: (_isExporting || _isExportingPdf)
                                ? null
                                : () => _exportToCsv(allScores),
                            icon: _isExporting
                                ? const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.table_chart_outlined,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                            label: Text(
                              _isExporting ? 'CSV...' : 'CSV',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white70),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildScoreStatTile(
                        'Rata-Rata',
                        '$avgScore',
                        Icons.analytics_outlined,
                      ),
                      const SizedBox(width: 8),
                      _buildScoreStatTile(
                        'Tertinggi',
                        '$maxScore',
                        Icons.arrow_upward_rounded,
                      ),
                      const SizedBox(width: 8),
                      _buildScoreStatTile(
                        'Terendah',
                        '$minScore',
                        Icons.arrow_downward_rounded,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Search Input ─────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (val) => setState(() => _scoreSearchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Cari nama atau NIS siswa di rekap nilai...',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.grey.shade400,
                  ),
                  suffixIcon: _scoreSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: Colors.grey.shade400,
                          ),
                          onPressed: () =>
                              setState(() => _scoreSearchQuery = ''),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: GoogleFonts.poppins(fontSize: 13),
              ),
            ),

            const SizedBox(height: 12),

            // ── Leaderboard List ──────────────────────────────────
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.assignment_turned_in_outlined,
                        size: 54,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        allScores.isEmpty
                            ? 'Belum ada siswa yang mengumpulkan ujian'
                            : 'Tidak ada siswa yang sesuai pencarian',
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        allScores.isEmpty
                            ? 'Jawaban yang disubmit oleh siswa akan otomatis muncul di sini secara real-time.'
                            : 'Coba periksa kembali ejaan nama atau NIS.',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: Colors.grey.shade400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...List.generate(filtered.length, (idx) {
                final s = filtered[idx];
                final rank = allScores.indexOf(s) + 1;
                return _buildScoreLeaderboardCard(s, rank);
              }),
          ],
        );
      },
    );
  }

  Widget _buildScoreStatTile(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 9.5,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.1,
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

  Widget _buildScoreLeaderboardCard(Map<String, dynamic> s, int rank) {
    final name = s['name'] as String;
    final nis = s['nis'] as String;
    final skor = s['skor'] as int;
    final benar = s['benar'] as int;
    final salah = s['salah'] as int;
    final total = s['totalSoal'] as int;
    final kosong = (total - benar - salah).clamp(0, total);
    final subtestScores = s['subtestScores'] as Map<String, dynamic>;

    Color rankColor = const Color(0xFF64748B);
    Color rankBg = const Color(0xFFF1F5F9);
    String rankEmoji = '#$rank';

    if (rank == 1) {
      rankColor = const Color(0xFFB45309);
      rankBg = const Color(0xFFFEF3C7);
      rankEmoji = '🥇 #1';
    } else if (rank == 2) {
      rankColor = const Color(0xFF475569);
      rankBg = const Color(0xFFE2E8F0);
      rankEmoji = '🥈 #2';
    } else if (rank == 3) {
      rankColor = const Color(0xFF9A3412);
      rankBg = const Color(0xFFFFEDD5);
      rankEmoji = '🥉 #3';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: rankBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rankEmoji,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: rankColor,
              ),
            ),
          ),
          title: Text(
            name,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Text(
                'NIS: $nis',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '•',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'B: $benar | S: $salah | K: $kosong',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: const Color(0xFF475569),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: Text(
              '$skor',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF15803D),
              ),
            ),
          ),
          children: [
            if (subtestScores.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 4),
                    Text(
                      'Rincian Skor Per-Subtest:',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...subtestScores.values.map((v) {
                      final j = v['judul']?.toString() ?? 'Subtest';
                      final b = v['benar'] ?? 0;
                      final t = v['total'] ?? 0;
                      final sVal = v['skor'] ?? 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                j,
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            Text(
                              '$b/$t Benar',
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$sVal',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF15803D),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportToCsv(List<Map<String, dynamic>> scores) async {
    if (scores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada data nilai siswa untuk diekspor.'),
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final buffer = StringBuffer();
      // Tambahkan UTF-8 BOM (\uFEFF) agar Microsoft Excel membaca file CSV dengan karakter rapi tanpa rusak encoding
      buffer.write('\uFEFF');

      // Header CSV
      buffer.writeln(
        'Peringkat,Nama Siswa,NIS,Kategori,Skor Akhir,Jumlah Benar,Jumlah Salah,Jumlah Kosong,Total Soal,Waktu Selesai',
      );

      for (int i = 0; i < scores.length; i++) {
        final s = scores[i];
        final rank = i + 1;
        final name = '"${(s['name'] as String).replaceAll('"', '""')}"';
        final nis = '"${s['nis']}"';
        final kategori = s['kategori'];
        final skor = s['skor'];
        final benar = s['benar'];
        final salah = s['salah'];
        final total = s['totalSoal'] as int;
        final kosong = (total - (benar as int) - (salah as int)).clamp(
          0,
          total,
        );

        String timeStr = '-';
        final ts = s['submittedAt'] as Timestamp?;
        if (ts != null) {
          final d = ts.toDate();
          timeStr =
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        }

        buffer.writeln(
          '$rank,$name,$nis,$kategori,$skor,$benar,$salah,$kosong,$total,"$timeStr"',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final sanitizedTitle = widget.title
          .replaceAll(RegExp(r'[^\w\s\-]'), '_')
          .trim();
      final filePath =
          '${tempDir.path}/Rekap_Nilai_${sanitizedTitle}_${widget.examId}.csv';
      final file = File(filePath);
      await file.writeAsString(buffer.toString(), encoding: utf8);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Rekap Nilai ExamGO - ${widget.title}',
          text:
              'Rekap Nilai Siswa Ujian "${widget.title}" (Token: ${widget.examId}).',
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Berkas CSV berhasil dibuat dan siap dibagikan.'),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor CSV: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportToPdf(List<Map<String, dynamic>> allScores) async {
    if (allScores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada data nilai siswa untuk diunduh.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isExportingPdf = true);
    try {
      await ExamPdfExporter.exportAndSharePdf(
        examTitle: widget.title,
        examId: widget.examId,
        scores: allScores,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dokumen PDF rekap nilai berhasil dibuat dan siap diunduh/dibagikan.',
            ),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Widget _buildExternalUrlDisabledRekapView() {
    final rawUrl = widget.url?.trim() ?? '';
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFBFDBFE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Icon(
                  Icons.link_off_rounded,
                  color: Color(0xFF2563EB),
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Rekap Nilai Otomatis Dinonaktifkan',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Ujian Tautan Eksternal (URL / Web Form)',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1D4ED8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Ujian ini menggunakan lembar soal eksternal dari tautan web (seperti Google Form atau CBT Web sekolah). Jawaban dan penilaian dikirim langsung ke sistem sumber tersebut.\n\n'
                '• Rekap nilai dan lembar respons tersimpan di akun Google Form / Spreadsheet Anda.\n'
                '• Untuk mengaktifkan rekap nilai otomatis & leaderboard real-time di aplikasi ExamGO, silakan terbitkan paket soal melalui menu "Buat & Upload Soal" (Tempel Google Form / Word).',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: const Color(0xFF475569),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (rawUrl.startsWith('http://') ||
                  rawUrl.startsWith('https://')) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(rawUrl);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.open_in_browser_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: Text(
                    'Buka Tautan Ujian di Browser',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirestoreErrorCard(Object? error) {
    final errStr = error?.toString().toLowerCase() ?? '';
    final isPermission =
        errStr.contains('permission-denied') || errStr.contains('permission');

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFFD97706),
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isPermission
                    ? 'Izin Akses Basis Data Diperlukan'
                    : 'Gagal Menghubungkan Nilai',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isPermission
                    ? 'Sistem keamanan Firestore memerlukan pembaruan aturan izin (Firestore Security Rules) agar data nilai siswa dapat dimuat oleh aplikasi.\n\nLembar jawaban siswa yang telah disubmit tetap tersimpan aman di server.'
                    : 'Terjadi kendala jaringan saat memuat data rekap nilai siswa. Silakan periksa koneksi internet Anda dan coba lagi.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF475569),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => setState(() {}),
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  'Muat Ulang Data',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveErrorCard(String? errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'Gagal Memuat Aktivitas Live',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Periksa koneksi internet perangkat atau coba muat ulang sesi monitoring.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh_rounded, size: 16, color: _kGreen),
              label: Text(
                'Coba Lagi',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kGreen,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopMetricRow(
    int active,
    int blocked,
    int finished,
    int offline,
    int total,
  ) {
    return Row(
      children: [
        _buildMetricTile(
          'Aktif',
          active,
          total,
          Icons.wifi_rounded,
          const Color(0xFF2E7D32),
          const Color(0xFFE8F5E9),
        ),
        const SizedBox(width: 10),
        _buildMetricTile(
          'Melanggar',
          blocked,
          total,
          Icons.block_rounded,
          Colors.red.shade700,
          Colors.red.shade50,
        ),
        const SizedBox(width: 10),
        _buildMetricTile(
          'Selesai',
          finished,
          total,
          Icons.check_circle_rounded,
          Colors.blue.shade700,
          Colors.blue.shade50,
        ),
        const SizedBox(width: 10),
        _buildMetricTile(
          'Offline',
          offline,
          total,
          Icons.cloud_off_rounded,
          Colors.grey.shade600,
          Colors.grey.shade100,
        ),
      ],
    );
  }

  Widget _buildMetricTile(
    String label,
    int count,
    int total,
    IconData icon,
    Color color,
    Color bg,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomMetricRow(int violations, int lowBattery, int total) {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            icon: Icons.warning_amber_rounded,
            color: Colors.orange.shade700,
            bg: Colors.orange.shade50,
            label: 'Pelanggaran',
            value: violations.toString(),
            subtitle: 'dari $total siswa',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildInfoCard(
            icon: Icons.battery_alert_rounded,
            color: Colors.red.shade600,
            bg: Colors.red.shade50,
            label: 'Baterai',
            value: lowBattery.toString(),
            subtitle: 'di bawah 20%',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildInfoCard(
            icon: Icons.people_alt_rounded,
            color: Colors.indigo.shade600,
            bg: Colors.indigo.shade50,
            label: 'Peserta',
            value: total.toString(),
            subtitle: 'terdaftar',
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color color,
    required Color bg,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: Colors.grey.shade500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filter) {
    final isSelected = _selectedFilter == filter;
    final filterColors = {
      'Aktif': _kGreen,
      'Melanggar': Colors.red.shade600,
      'Selesai': Colors.blue.shade600,
      'Offline': Colors.grey.shade600,
      'Semua': Colors.blueGrey.shade700,
    };
    final color = filterColors[filter] ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: FilterChip(
          label: Text(
            filter,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? color : Colors.grey.shade600,
            ),
          ),
          selected: isSelected,
          onSelected: (_) => setState(() => _selectedFilter = filter),
          selectedColor: color.withValues(alpha: 0.12),
          checkmarkColor: color,
          backgroundColor: Colors.white,
          elevation: isSelected ? 0 : 1,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: StadiumBorder(
            side: BorderSide(
              color: isSelected ? color : Colors.grey.shade200,
              width: isSelected ? 1.5 : 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Tidak ada siswa ditemukan',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Coba ubah filter atau kata kunci pencarian',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> s) {
    final name = s['name'] as String;
    final nis = s['nis'] as String;
    final status = s['status'] as String;
    final violations = s['violations'] as int;
    final battery = s['battery'] as int;
    final lastPing = s['last_ping'] as Timestamp?;

    // ── Status Config ────────────────────────────────────
    late Color statusColor;
    late Color statusBg;
    late IconData statusIcon;
    late String statusLabel;

    switch (status) {
      case 'ACTIVE':
        statusColor = const Color(0xFF2E7D32);
        statusBg = const Color(0xFFE8F5E9);
        statusIcon = Icons.wifi_rounded;
        statusLabel = 'Aktif';
        break;
      case 'PAUSED':
        statusColor = Colors.orange.shade700;
        statusBg = Colors.orange.shade50;
        statusIcon = Icons.pause_circle_rounded;
        statusLabel = 'Jeda';
        break;
      case 'FINISHED':
        statusColor = Colors.blue.shade700;
        statusBg = Colors.blue.shade50;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Selesai';
        break;
      case 'BLOCKED':
        statusColor = Colors.red.shade700;
        statusBg = Colors.red.shade50;
        statusIcon = Icons.block_rounded;
        statusLabel = 'Diblokir';
        break;
      default:
        statusColor = Colors.grey.shade600;
        statusBg = Colors.grey.shade100;
        statusIcon = Icons.cloud_off_rounded;
        statusLabel = 'Offline';
    }

    final isBlocked = status == 'BLOCKED';
    final hasViolation = violations > 0;

    // Last ping string
    String pingStr = 'Belum ada data';
    if (lastPing != null) {
      final diff = DateTime.now().difference(lastPing.toDate());
      if (diff.inSeconds < 60) {
        pingStr = 'Baru saja';
      } else if (diff.inMinutes < 60) {
        pingStr = '${diff.inMinutes} mnt lalu';
      } else {
        pingStr = '${diff.inHours} jam lalu';
      }
    }

    // Battery icon & color
    final batIcon = battery > 50
        ? Icons.battery_full_rounded
        : battery > 20
        ? Icons.battery_4_bar_rounded
        : Icons.battery_alert_rounded;
    final batColor = battery > 50
        ? Colors.green.shade600
        : battery > 20
        ? Colors.orange.shade600
        : Colors.red.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isBlocked
              ? Colors.red.shade200
              : hasViolation
              ? Colors.orange.shade200
              : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isBlocked
                ? Colors.red.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentActivityLogScreen(
                  examId: widget.examId,
                  nis: nis,
                  name: name,
                  status: status,
                  violations: violations,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    // ── Avatar with status ring ──────────────
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: statusBg,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              statusIcon,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),

                    // ── Name & NIS ───────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'NIS: $nis',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Status Badge ─────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (hasViolation)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.warning_rounded,
                                  color: Colors.white,
                                  size: 10,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$violations Pelanggaran',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // ── Info Row: Battery & Last Ping ────────────
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(batIcon, size: 15, color: batColor),
                      const SizedBox(width: 4),
                      Text(
                        '$battery%',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: batColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        pingStr,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Colors.grey.shade400,
                      ),
                      Text(
                        'Lihat Log',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Unblock Button ─────────────────────────
                if (isBlocked) ...[
                  const SizedBox(height: 12),
                  SlideToUnblock(
                    onAction: () => _showUnblockConfirmation(
                      context,
                      widget.examId,
                      nis,
                      name,
                    ),
                    text: 'Geser untuk Buka Akses',
                    backgroundColor: Colors.red.shade50,
                    sliderColor: Colors.red.shade600,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Halaman Log Aktivitas Siswa ──────────────────────────────────────────────
class StudentActivityLogScreen extends StatefulWidget {
  final String examId;
  final String nis;
  final String name;
  final String status;
  final int violations;

  const StudentActivityLogScreen({
    super.key,
    required this.examId,
    required this.nis,
    required this.name,
    required this.status,
    required this.violations,
  });

  @override
  State<StudentActivityLogScreen> createState() =>
      _StudentActivityLogScreenState();
}

class _StudentActivityLogScreenState extends State<StudentActivityLogScreen> {
  Color get _statusColor {
    switch (widget.status) {
      case 'ACTIVE':
        return const Color(0xFF2E7D32);
      case 'PAUSED':
        return Colors.orange.shade700;
      case 'BLOCKED':
        return Colors.red.shade700;
      case 'FINISHED':
        return Colors.blue.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  String get _statusLabel {
    switch (widget.status) {
      case 'ACTIVE':
        return 'Sedang Aktif';
      case 'PAUSED':
        return 'Dijeda';
      case 'BLOCKED':
        return 'Diblokir';
      case 'FINISHED':
        return 'Selesai Ujian';
      default:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: widget.status == 'BLOCKED'
          ? Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SlideToUnblock(onAction: () => _unblockStudent(context)),
            )
          : null,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── AppBar ─────────────────────────────────────────
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final isCollapsed = constraints.scrollOffset > 130;
              return SliverAppBar(
                expandedHeight: 230,
                pinned: true,
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                title: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isCollapsed ? 1.0 : 0.0,
                  child: Text(
                    widget.name,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(20),
                  child: Container(
                    height: 20,
                    decoration: const BoxDecoration(
                      color: _kBg,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Stack(
                    children: [
                      // Elegant Background Pattern / Gradient
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      Positioned(
                        top: -40,
                        right: -40,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            24,
                            50,
                            20,
                            32,
                          ), // Top padding 50 to avoid title overlap
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Avatar Row
                              Row(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.3,
                                        ),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        widget.name.isNotEmpty
                                            ? widget.name[0].toUpperCase()
                                            : '?',
                                        style: GoogleFonts.poppins(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.name,
                                          style: GoogleFonts.poppins(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            height: 1.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'NIS: ${widget.nis}',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: Colors.white.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              // Status & Violation Badges
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _statusColor,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _statusColor.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      _statusLabel,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (widget.violations > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        border: Border.all(
                                          color: Colors.red.shade200,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.warning_rounded,
                                            size: 14,
                                            color: Colors.red.shade700,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${widget.violations} Pelanggaran',
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // ── Log Timeline Header ───────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.timeline_rounded, size: 18, color: _kGreenL),
                  const SizedBox(width: 8),
                  Text(
                    'Log Aktivitas Real-Time',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF69F0AE).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2E7D32),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Live',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _kGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Log Polling (Tarik Manual) ────────────────────────────────────
          // FIX OPTIMISASI KUOTA: Mengganti StreamBuilder ke FutureBuilder agar
          // guru harus me-refresh manual untuk menghemat bacaan Firestore.
          FutureBuilder<QuerySnapshot>(
            future: MonitoringService.instance.getStudentActivityLog(
              widget.examId,
              widget.nis,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: _kGreenL),
                  ),
                );
              }

              final logs = snapshot.data?.docs ?? [];
              if (logs.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.1),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.history_toggle_off_rounded,
                            size: 56,
                            color: Colors.grey.shade300,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Belum Ada Aktivitas',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Log akan muncul secara otomatis\nketika siswa melakukan aktivitas selama ujian.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final data = logs[i].data() as Map<String, dynamic>;
                    final type = data['activity_type'] as String? ?? 'INFO';
                    final desc = data['description'] as String? ?? '-';
                    final ts = data['timestamp'] as Timestamp?;
                    final at = _getActivityType(type);
                    final timeStr = ts != null ? _formatTime(ts.toDate()) : '–';
                    final dateStr = ts != null ? _formatDate(ts.toDate()) : '';
                    return _LogItem(
                      icon: at.icon,
                      color: at.color,
                      label: at.label,
                      description: desc,
                      time: timeStr,
                      date: dateStr,
                      isFirst: i == 0,
                      isLast: i == logs.length - 1,
                    );
                  }, childCount: logs.length),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _unblockStudent(BuildContext context) {
    _showUnblockConfirmation(
      context,
      widget.examId,
      widget.nis,
      widget.name,
      onSuccess: () {
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Ags',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ─── Widget Log Item (Timeline) ───────────────────────────────────────────────
class _LogItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final String time;
  final String date;
  final bool isFirst;
  final bool isLast;

  const _LogItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.time,
    required this.date,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Timeline Column ──────────────────────────────
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Line above dot (hidden for first)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: isFirst
                          ? Colors.transparent
                          : Colors.grey.shade200,
                    ),
                  ),
                ),
                // Dot
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isFirst ? color : color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: isFirst
                        ? Border.all(color: color, width: 0)
                        : Border.all(
                            color: color.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                    boxShadow: isFirst
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    color: isFirst ? Colors.white : color,
                    size: 17,
                  ),
                ),
                // Line below dot (hidden for last)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : Colors.grey.shade200,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // ── Log Card Content ─────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isFirst ? color.withValues(alpha: 0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isFirst
                        ? color.withValues(alpha: 0.25)
                        : Colors.grey.shade100,
                    width: isFirst ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isFirst ? 0.06 : 0.03,
                      ),
                      blurRadius: isFirst ? 12 : 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label + Time Row
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                label,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: color,
                                ),
                              ),
                              if (isFirst) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Terbaru',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              time,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (date.isNotEmpty)
                              Text(
                                date,
                                style: GoogleFonts.poppins(
                                  fontSize: 9.5,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Description
                    Text(
                      description,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widget Jam Real-Time ─────────────────────────────────────────────────────
class _LiveClockText extends StatefulWidget {
  final Color? color;
  const _LiveClockText({this.color});

  @override
  State<_LiveClockText> createState() => _LiveClockTextState();
}

class _LiveClockTextState extends State<_LiveClockText> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return Text(
      '$h:$m:$s',
      style: GoogleFonts.poppins(
        fontSize: 13,
        color: widget.color ?? Colors.white.withValues(alpha: 0.85),
      ),
    );
  }
}

// ─── Helper Konfirmasi Buka Blokir ────────────────────────────────────────────
Future<void> _showUnblockConfirmation(
  BuildContext context,
  String examId,
  String nis,
  String name, {
  VoidCallback? onSuccess,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_open_rounded,
                color: _kGreen,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Yakin Buka Blokir?',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Akses ujian untuk $name (NIS: $nis) akan dibuka kembali.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Batal',
                      style: GoogleFonts.poppins(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Ya, Buka',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  MonitoringService.instance.setStudentStatusByTeacher(
    examId: examId,
    nis: nis,
    status: 'ACTIVE',
    violations: 0,
  );
  MonitoringService.instance.logActivity(
    examId: examId,
    nis: nis,
    activityType: 'INFO',
    description: 'Pengawas membuka akses siswa',
  );

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.lock_open_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text('Akses $name berhasil dibuka', style: GoogleFonts.poppins()),
        ],
      ),
      backgroundColor: _kGreenL,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    ),
  );

  if (onSuccess != null) {
    onSuccess();
  }
}
