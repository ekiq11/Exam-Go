import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/services/license_service.dart';
import 'package:examgo/view/pre_exam_checklist.dart';
import 'package:examgo/view/student/student_exam_session_screen.dart';
import 'package:examgo/view/widgets/premium_token_dialog.dart';

/// Bottom Sheet untuk detail paket tryout dan konfirmasi sebelum ujian (Diadaptasi dari myOLCv2)
class TryoutDetailSheet extends StatelessWidget {
  final TryoutSchedule schedule;

  const TryoutDetailSheet({super.key, required this.schedule});

  static void show(BuildContext context, TryoutSchedule schedule) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TryoutDetailSheet(schedule: schedule),
    );
  }

  Future<void> _handleStart(BuildContext context) async {
    Navigator.of(context).pop(); // Tutup bottom sheet

    // Cek kuota ujian siswa
    final canTake = await LicenseService.instance.canStudentTakeExam();
    if (!canTake) {
      if (context.mounted) {
        PremiumTokenDialog.show(context, userType: 'STUDENT_LIFETIME');
      }
      return;
    }

    if (!context.mounted) return;

    // Tampilkan Pre-Exam Checklist (Cek baterai, integritas perangkat, identitas siswa)
    final identity = await PreExamChecklistDialog.show(context, schedule.namaPaket);
    if (identity == null || !context.mounted) return;

    final name = identity['name'] ?? 'Siswa';
    final nis = identity['nis'] ?? '-';

    // Catat pemakaian 1 kuota ujian
    await LicenseService.instance.recordExamAttempt();

    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentExamSessionScreen(
          token: schedule.paketId,
          studentName: name,
          studentNis: nis,
          initialSchedule: schedule,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isToday = schedule.isToday;
    final isUpcoming = schedule.isUpcoming;

    final Color statusColor = isToday
        ? const Color(0xFF16A34A)
        : (isUpcoming ? const Color(0xFF0284C7) : const Color(0xFF64748B));

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 12,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isToday ? Icons.play_arrow_rounded : Icons.event_note_rounded,
                  color: statusColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.namaPaket,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            schedule.badgeStatus,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          schedule.jenisTest,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          schedule.isLifetime ? Icons.all_inclusive_rounded : Icons.calendar_today_rounded,
                          size: 13,
                          color: AppColors.primaryGreen,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            schedule.isLifetime
                                ? 'Selalu Aktif (Tanpa Batas Waktu)'
                                : '${schedule.formattedDate} • ${schedule.formattedTime}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Info Tiles Grid (Durasi, Total Soal, Sistem Waktu)
          Row(
            children: [
              _buildInfoBox(
                icon: Icons.timer_outlined,
                label: 'Durasi',
                value: '${schedule.durasiMenit} Menit',
              ),
              const SizedBox(width: 10),
              _buildInfoBox(
                icon: Icons.format_list_numbered_rounded,
                label: 'Total Soal',
                value: schedule.totalSoal > 0 ? '${schedule.totalSoal} Butir' : 'Lengkap',
              ),
              const SizedBox(width: 10),
              _buildInfoBox(
                icon: Icons.tune_rounded,
                label: 'Sistem Waktu',
                value: schedule.jenisWaktu == 'per_subtest' ? 'Per Subtest' : 'Total Waktu',
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Subtests Preview (jika tersedia)
          if (schedule.subtests.isNotEmpty) ...[
            Text(
              'Cakupan Subtest Materi:',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: schedule.subtests.map((s) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    s,
                    style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Rules Reminder Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Color(0xFFD97706), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kiosk mode aktif: Pindah aplikasi atau split screen akan otomatis tercatat sebagai pelanggaran.',
                    style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => _handleStart(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: isToday ? AppColors.primaryGreen : const Color(0xFF0284C7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                isToday ? 'Mulai Ujian Sekarang' : 'Kerjakan Ujian (Akses Premium)',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF64748B)),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.poppins(fontSize: 10.5, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 2),
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
        ),
      ),
    );
  }
}

