import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Menampilkan modal dialog interaktif ketika siswa mencoba membuka Pembahasan & Kunci
/// namun waktu ujian resmi belum berakhir.
Future<void> showExamTimeLockDialog(
  BuildContext context, {
  required DateTime endTime,
  String? examTitle,
}) async {
  final now = DateTime.now();
  final diff = endTime.difference(now);
  final remainingMinutes = diff.isNegative
      ? 0
      : (diff.inSeconds > 0 && diff.inMinutes == 0 ? 1 : diff.inMinutes);

  final hourStr = endTime.hour.toString().padLeft(2, '0');
  final minuteStr = endTime.minute.toString().padLeft(2, '0');
  final formattedTime = '$hourStr:$minuteStr WIB';

  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon Badge
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFDE68A),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.lock_clock_rounded,
                color: Color(0xFFD97706),
                size: 32,
              ),
            ),
            const SizedBox(height: 18),

            // Judul
            Text(
              'Waktu Ujian Belum Berakhir',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),

            // Penjelasan Integritas Ujian
            Text(
              'Demi menjaga kejujuran dan kerahasiaan ujian bersama peserta lain, Pembahasan & Kunci Jawaban baru dapat diakses setelah waktu ujian resmi selesai.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: const Color(0xFF475569),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),

            // Card Jadwal Terbuka
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Kunci Terbuka Pukul',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        formattedTime,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.timelapse_rounded,
                            size: 16,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Sisa Waktu Tunggu',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        remainingMinutes > 0
                            ? '$remainingMinutes Menit Lagi'
                            : 'Kurang dari 1 Menit',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Info Hint
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Anda dapat melihat kembali pembahasan melalui menu Riwayat Ujian setelah waktu di atas tiba.',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tombol Aksi
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Mengerti',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
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
