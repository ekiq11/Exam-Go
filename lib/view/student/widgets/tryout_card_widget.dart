import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/utils/indo_date_formatter.dart';

/// Kartu tampilan paket tryout profesional & bebas overflex (Diadaptasi dari myOLCv2 & ExamGO Design System)
class TryoutCardWidget extends StatelessWidget {
  final TryoutSchedule schedule;
  final VoidCallback onTap;

  const TryoutCardWidget({
    super.key,
    required this.schedule,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = schedule.isToday;
    final isUpcoming = schedule.isUpcoming;
    final isLifetime = schedule.isLifetime;

    // Warna status harmonis sesuai tema aplikasi
    final Color statusColor = isLifetime
        ? const Color(0xFF0F766E) // Teal
        : (isToday
            ? AppColors.primaryGreen // Emerald / Forest Green
            : (isUpcoming ? const Color(0xFF0284C7) : const Color(0xFF64748B)));

    final IconData statusIcon = isLifetime
        ? Icons.all_inclusive_rounded
        : (isToday
            ? Icons.play_circle_fill_rounded
            : (isUpcoming ? Icons.alarm_rounded : Icons.check_circle_rounded));

    // Format Hari, Tanggal & Jam Bahasa Indonesia dengan zona waktu
    final dateStr = IndoDateFormatter.formatHariTanggal(schedule.tanggal, shortMonth: true);
    final timeStr = IndoDateFormatter.formatJam(schedule.jamMulai, schedule.jamSelesai, rawDateStr: schedule.tanggal);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday
              ? AppColors.primaryGreen.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
          width: isToday ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isToday
                ? AppColors.primaryGreen.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Icon Avatar
                Container(
                  width: 44,
                  height: 44,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 24),
                ),
                const SizedBox(width: 12),

                // Main Information Area
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Judul Paket Tryout
                      Text(
                        schedule.namaPaket,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: const Color(0xFF0F172A),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Badges Status & Kategori (Menggunakan Wrap agar BEBAS OVERFLEX)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              schedule.badgeStatus,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),

                          // Kategori Badge (SNBT / SKD / TKA SMA, dsb)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              schedule.jenisTest,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF334155),
                              ),
                            ),
                          ),

                          // Badge Bisa Diulang (Jika diizinkan)
                          if (schedule.allowRetake)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Text(
                                'Bisa Diulang',
                                style: GoogleFonts.poppins(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Baris Tanggal & Hari Standar Indonesia
                      Row(
                        children: [
                          Icon(
                            isLifetime ? Icons.all_inclusive_rounded : Icons.calendar_today_rounded,
                            size: 13,
                            color: isLifetime ? const Color(0xFF0F766E) : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              isLifetime ? 'Selalu Aktif (Tanpa Batas Waktu)' : dateStr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: isLifetime ? FontWeight.w600 : FontWeight.w500,
                                color: isLifetime ? const Color(0xFF0F766E) : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Baris Jam Pelaksanaan & Durasi Ujian (Menggunakan Wrap agar BEBAS OVERFLEX)
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Jam Pelaksanaan
                          if (!isLifetime && schedule.tanggal.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  timeStr,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                          // Durasi Pengerjaan
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                '${schedule.durasiMenit} Menit',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),

                          // Jumlah Butir Soal (Jika tersedia)
                          if (schedule.totalSoal > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.format_list_numbered_rounded, size: 13, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  '${schedule.totalSoal} Soal',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
