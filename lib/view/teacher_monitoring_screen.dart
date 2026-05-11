// ignore_for_file: deprecated_member_use
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/services/monitoring_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Konfigurasi Tipe Log ────────────────────────────────────────────────────
class _ActivityType {
  final IconData icon;
  final Color color;
  final String label;
  const _ActivityType({required this.icon, required this.color, required this.label});
}

const _activityTypes = <String, _ActivityType>{
  'EXIT_APP':       _ActivityType(icon: Icons.exit_to_app_rounded,    color: Color(0xFFE53935), label: 'Keluar Aplikasi'),
  'EXIT_ATTEMPT':   _ActivityType(icon: Icons.logout_rounded,          color: Color(0xFFFF6F00), label: 'Percobaan Keluar'),
  'SCREENSHOT':     _ActivityType(icon: Icons.screenshot_monitor,      color: Color(0xFF8E24AA), label: 'Percobaan Screenshot'),
  'SCREEN_HIDDEN':  _ActivityType(icon: Icons.visibility_off_rounded,  color: Color(0xFF1565C0), label: 'Layar Tersembunyi'),
  'ACTIVE':         _ActivityType(icon: Icons.wifi_rounded,            color: Color(0xFF2E7D32), label: 'Mulai Ujian'),
  'FINISHED':       _ActivityType(icon: Icons.check_circle_rounded,    color: Color(0xFF1976D2), label: 'Selesai Ujian'),
  'BLOCKED':        _ActivityType(icon: Icons.block_rounded,           color: Color(0xFFE53935), label: 'Diblokir'),
};

_ActivityType _getActivityType(String type) =>
    _activityTypes[type] ??
    const _ActivityType(icon: Icons.info_outline_rounded, color: Color(0xFF607D8B), label: 'Aktivitas');

// ─── Daftar Sesi Ujian (List Screen) ─────────────────────────────────────────
class TeacherMonitoringListScreen extends StatefulWidget {
  const TeacherMonitoringListScreen({super.key});
  @override
  State<TeacherMonitoringListScreen> createState() => _TeacherMonitoringListScreenState();
}

class _TeacherMonitoringListScreenState extends State<TeacherMonitoringListScreen> {
  List<Map<String, String>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('teacher_exam_history') ?? [];
    final parsed = list.map((item) {
      final parts = item.split('|');
      return {
        'examId':    parts.isNotEmpty       ? parts[0] : '',
        'title':     parts.length > 1 ? parts[1] : 'Ujian',
        'timestamp': parts.length > 2 ? parts[2] : '0',
      };
    }).toList();
    setState(() { _history = parsed; _loading = false; });
  }

  Future<void> _confirmDelete(Map<String, String> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Hapus Sesi Ujian?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ujian: ${item['title']}',
                style: GoogleFonts.poppins(fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                'Semua data siswa dan log aktivitas ujian ini akan dihapus permanen dari Firestore.',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.red.shade700),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Batal', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Ya, Hapus',
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _deleteSession(item['examId']!);
  }

  Future<void> _deleteSession(String examId) async {
    // 1. Hapus dari Firestore
    await MonitoringService.instance.deleteExamSession(examId);

    // 2. Hapus dari local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('teacher_exam_history') ?? [];
    list.removeWhere((e) => e.startsWith(examId));
    await prefs.setStringList('teacher_exam_history', list);

    // 3. Refresh UI
    setState(() {
      _history.removeWhere((e) => e['examId'] == examId);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sesi ujian berhasil dihapus',
            style: GoogleFonts.poppins()),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('Monitoring Ujian', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          if (_history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Geser item ke kiri untuk hapus',
                child: Icon(Icons.swipe_left_rounded,
                    color: Colors.white.withOpacity(0.7), size: 20),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_rounded, size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Belum ada QR ujian yang dibuat',
                          style: GoogleFonts.poppins(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  itemBuilder: (context, i) {
                    final item = _history[i];
                    final date = DateTime.fromMillisecondsSinceEpoch(
                      int.tryParse(item['timestamp']!) ?? 0,
                    );
                    return Dismissible(
                      key: Key(item['examId']!),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        await _confirmDelete(item);
                        return false; // kita handle state sendiri di _deleteSession
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_rounded, color: Colors.white, size: 28),
                            SizedBox(height: 4),
                            Text('Hapus', style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryGreen.withOpacity(0.12),
                            child: const Icon(Icons.qr_code, color: AppColors.primaryGreen),
                          ),
                          title: Text(item['title']!,
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _confirmDelete(item),
                                icon: Icon(Icons.delete_outline_rounded,
                                    color: Colors.red.shade300, size: 20),
                                tooltip: 'Hapus sesi',
                              ),
                              const Icon(Icons.chevron_right, color: AppColors.primaryGreen),
                            ],
                          ),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => TeacherMonitoringDetailScreen(
                              examId: item['examId']!,
                              title: item['title']!,
                            ),
                          )),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ─── Detail Sesi (Daftar Siswa) ──────────────────────────────────────────────
class TeacherMonitoringDetailScreen extends StatelessWidget {
  final String examId;
  final String title;

  const TeacherMonitoringDetailScreen({
    super.key,
    required this.examId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
            Text('Ketuk siswa untuk lihat log aktivitas',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: MonitoringService.instance.streamExamStudents(examId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline_rounded, size: 72, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('Belum ada siswa yang bergabung',
                      style: GoogleFonts.poppins(color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text('Minta siswa scan QR ujian',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400)),
                ],
              ),
            );
          }

          int activeCount = 0;
          for (var d in docs) {
            final data = d.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? 'OFFLINE';
            final lastPing = data['last_ping'] as Timestamp?;
            final isOffline = lastPing == null ||
                DateTime.now().difference(lastPing.toDate()).inMinutes > 2;
            if (status == 'ACTIVE' && !isOffline) activeCount++;
          }

          return Column(
            children: [
              // ── Summary Bar ──────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    _SummaryChip(
                      icon: Icons.people_rounded,
                      label: '${docs.length} Siswa',
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 10),
                    _SummaryChip(
                      icon: Icons.wifi_rounded,
                      label: '$activeCount Online',
                      color: Colors.green,
                    ),
                    const SizedBox(width: 10),
                    _SummaryChip(
                      icon: Icons.warning_amber_rounded,
                      label: '${docs.length - activeCount} Offline',
                      color: Colors.orange,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // ── Daftar Siswa ─────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final rawName = data['name'] as String?;
                    final name = (rawName == null || rawName.trim().isEmpty) ? 'Anonim' : rawName;
                    final rawNis = data['nis'] as String?;
                    final nis = (rawNis == null || rawNis.trim().isEmpty) ? '-' : rawNis;
                    final status = data['status'] as String? ?? 'OFFLINE';
                    final violations = data['violations'] as int? ?? 0;
                    final battery = data['battery_level'] as int? ?? 0;
                    final lastPing = data['last_ping'] as Timestamp?;

                    final isOffline = lastPing == null ||
                        DateTime.now().difference(lastPing.toDate()).inMinutes > 2;
                    final displayStatus = isOffline ? 'OFFLINE' : status;

                    Color statusColor;
                    IconData statusIcon;
                    switch (displayStatus) {
                      case 'ACTIVE':
                        statusColor = Colors.green;
                        statusIcon = Icons.wifi_rounded;
                        break;
                      case 'PAUSED':
                        statusColor = Colors.orange;
                        statusIcon = Icons.pause_circle_rounded;
                        break;
                      case 'FINISHED':
                        statusColor = Colors.blue;
                        statusIcon = Icons.check_circle_rounded;
                        break;
                      case 'BLOCKED':
                        statusColor = Colors.red;
                        statusIcon = Icons.block_rounded;
                        break;
                      default:
                        statusColor = Colors.grey;
                        statusIcon = Icons.cloud_off_rounded;
                    }

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: violations > 0
                              ? Colors.red.withOpacity(0.3)
                              : Colors.grey.shade200,
                          width: violations > 0 ? 1.5 : 1,
                        ),
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => StudentActivityLogScreen(
                            examId: examId,
                            nis: nis,
                            name: name,
                            status: displayStatus,
                            violations: violations,
                          ),
                        )),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              // Status Circle
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(statusIcon, color: statusColor, size: 20),
                              ),
                              const SizedBox(width: 12),
                              // Nama & NIS
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text('NIS: $nis',
                                        style: GoogleFonts.poppins(
                                            fontSize: 12, color: Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                              // Baterai + Pelanggaran
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        battery > 20 ? Icons.battery_full_rounded : Icons.battery_alert_rounded,
                                        size: 13,
                                        color: battery > 20 ? Colors.green : Colors.red,
                                      ),
                                      const SizedBox(width: 3),
                                      Text('$battery%',
                                          style: GoogleFonts.poppins(fontSize: 12)),
                                    ],
                                  ),
                                  if (violations > 0) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.red.shade200),
                                      ),
                                      child: Text('$violations ⚠️',
                                          style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              color: Colors.red.shade700,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.chevron_right_rounded,
                                  color: Colors.grey.shade400, size: 18),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Halaman Log Aktivitas Siswa ──────────────────────────────────────────────
class StudentActivityLogScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    Color statusColor;
    switch (status) {
      case 'ACTIVE':   statusColor = Colors.green;     break;
      case 'PAUSED':   statusColor = Colors.orange;    break;
      case 'BLOCKED':  statusColor = Colors.red;       break;
      case 'FINISHED': statusColor = Colors.blue;      break;
      default:         statusColor = Colors.grey;
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
            Text('NIS: $nis',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        actions: [
          if (status == 'BLOCKED')
            IconButton(
              icon: const Icon(Icons.lock_open_rounded),
              tooltip: 'Buka Kunci Layar',
              onPressed: () {
                MonitoringService.instance.updateStudentStatus(
                  examId: examId,
                  nis: nis,
                  name: name,
                  status: 'ACTIVE',
                  violations: 0,
                );
                MonitoringService.instance.logActivity(
                  examId: examId,
                  nis: nis,
                  activityType: 'INFO',
                  description: 'Pengawas membuka kunci layar ujian',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Layar siswa berhasil dibuka', style: GoogleFonts.poppins()),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Status Header Card ────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: statusColor),
                      const SizedBox(width: 6),
                      Text(status,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (violations > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text('$violations Pelanggaran',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700)),
                  ),
                const Spacer(),
                Text('Log Real-Time',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Log List (Stream) ─────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: MonitoringService.instance.streamStudentActivityLog(examId, nis),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final logs = snapshot.data?.docs ?? [];
                if (logs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_rounded, size: 60, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('Belum ada aktivitas tercatat',
                            style: GoogleFonts.poppins(color: Colors.grey)),
                        const SizedBox(height: 6),
                        Text('Log akan muncul saat siswa melakukan aktivitas di aplikasi',
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: Colors.grey.shade400),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: logs.length,
                  itemBuilder: (context, i) {
                    final data = logs[i].data() as Map<String, dynamic>;
                    final type = data['activity_type'] as String? ?? 'INFO';
                    final desc = data['description'] as String? ?? '-';
                    final ts = data['timestamp'] as Timestamp?;

                    final at = _getActivityType(type);
                    final timeStr = ts != null
                        ? _formatTime(ts.toDate())
                        : '–';

                    return _LogItem(
                      icon: at.icon,
                      color: at.color,
                      label: at.label,
                      description: desc,
                      time: timeStr,
                      isFirst: i == 0,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ─── Widget Helpers ───────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SummaryChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final String time;
  final bool isFirst;

  const _LogItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.time,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot + line
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(isFirst ? 0.2 : 0.1),
                  shape: BoxShape.circle,
                  border: isFirst
                      ? Border.all(color: color.withOpacity(0.5), width: 1.5)
                      : null,
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              Container(
                width: 1.5,
                height: 22,
                color: Colors.grey.shade200,
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFirst ? color.withOpacity(0.3) : Colors.grey.shade200,
                  width: isFirst ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: color)),
                      ),
                      Text(time,
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(description,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
