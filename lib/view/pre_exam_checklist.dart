// ignore_for_file: use_build_context_synchronously, avoid_print
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/constant/responsive.dart';
import 'package:examgo/constant/security_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreExamChecklistDialog extends StatefulWidget {
  final String examTitle;
  const PreExamChecklistDialog({super.key, required this.examTitle});

  static Future<Map<String, String>?> show(BuildContext context, String title) {
    return showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PreExamChecklistDialog(examTitle: title),
    );
  }

  @override
  State<PreExamChecklistDialog> createState() => _PreExamChecklistDialogState();
}

class _PreExamChecklistDialogState extends State<PreExamChecklistDialog> {
  final _nameCtrl = TextEditingController();
  final _nisCtrl = TextEditingController();

  bool _isLoading = true;
  String? _securityError;
  int _batteryLevel = 100;
  bool _batteryWarning = false;
  bool _agreedToRules = false;

  @override
  void initState() {
    super.initState();
    _loadSavedIdentity();
    _runDiagnostics();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nisCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameCtrl.text = prefs.getString('student_name') ?? '';
        _nisCtrl.text = prefs.getString('student_nis') ?? '';
      });
    }
  }

  Future<void> _runDiagnostics() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Cek Root & Dev Mode
      final secError = await SecurityService.instance.checkDeviceIntegrity();
      if (secError != null) {
        if (mounted) {
          setState(() {
            _securityError = secError;
            _isLoading = false;
          });
        }
        return;
      }

      // 2. Cek Baterai
      if (Platform.isAndroid || Platform.isIOS) {
        final battery = Battery();
        final level = await battery.batteryLevel;
        if (mounted) {
          setState(() {
            _batteryLevel = level;
            _batteryWarning = level < 20;
          });
        }
      }
    } catch (e) {
      print('Diagnostics error: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _onStart() async {
    final name = _nameCtrl.text.trim();
    final nis = _nisCtrl.text.trim();

    if (name.isEmpty || nis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nama dan NIS harus diisi terlebih dahulu',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (!_agreedToRules) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Harap baca dan centang persetujuan regulasi anti-curang',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    // Simpan untuk sesi ujian selanjutnya
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_name', name);
    await prefs.setString('student_nis', nis);

    // FIX CRASH-C6: mounted check wajib setelah await — user bisa saja dismiss dialog
    // saat SharedPreferences sedang menyimpan data, menyebabkan widget unmount
    // dan Navigator.of(context) crash dengan "Looking up a deactivated widget's ancestor".
    if (!mounted) return;
    Navigator.of(context).pop({'name': name, 'nis': nis});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: context.rs(16),
        vertical: context.rs(20),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 36,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Gradient Banner
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  vertical: context.rs(20),
                  horizontal: context.rs(20),
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1B5E20), AppColors.primaryGreen],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: context.rs(52),
                      height: context.rs(52),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: context.rs(26),
                      ),
                    ),
                    SizedBox(height: context.rs(10)),
                    Text(
                      'Persiapan & Regulasi Ujian',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(16.5),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: context.rs(3)),
                    Text(
                      'Sistem Anti-Kecurangan ExamGo Aktif',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(11.5),
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: CircularProgressIndicator(
                    color: AppColors.primaryGreen,
                  ),
                )
              else if (_securityError != null)
                Padding(
                  padding: EdgeInsets.all(context.rs(20)),
                  child: _buildSecurityError(),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      context.rs(18),
                      context.rs(16),
                      context.rs(18),
                      context.rs(18),
                    ),
                    child: _buildChecklistForm(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityError() {
    return Column(
      children: [
        Icon(Icons.gpp_bad_rounded, color: Colors.red.shade700, size: 48),
        SizedBox(height: context.rs(16)),
        Text(
          'Akses Ditolak',
          style: GoogleFonts.poppins(
            fontSize: context.rs(16),
            fontWeight: FontWeight.bold,
            color: Colors.red.shade700,
          ),
        ),
        SizedBox(height: context.rs(8)),
        Text(
          _securityError!,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: context.rs(13)),
        ),
        SizedBox(height: context.rs(24)),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(null),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade200,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Tutup'),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Exam Title Card
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(context.rs(12)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primaryGreen.withValues(alpha: 0.05),
                AppColors.paleGreen,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryGreen.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(context.rs(6)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: AppColors.primaryGreen,
                  size: 16,
                ),
              ),
              SizedBox(width: context.rs(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sesi Ujian / Tryout',
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(11),
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.examTitle,
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(13),
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryGreen,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.rs(12)),

        // Battery Info
        if (_batteryWarning)
          Container(
            margin: EdgeInsets.only(bottom: context.rs(12)),
            padding: EdgeInsets.all(context.rs(10)),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.battery_alert_rounded,
                  color: Colors.orange.shade800,
                  size: 20,
                ),
                SizedBox(width: context.rs(8)),
                Expanded(
                  child: Text(
                    'Baterai lemah ($_batteryLevel%). Sebaiknya charge perangkat Anda.',
                    style: GoogleFonts.poppins(
                      fontSize: context.rs(12),
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.battery_charging_full_rounded,
                color: Colors.green,
                size: 16,
              ),
              SizedBox(width: context.rs(6)),
              Text(
                'Status Baterai: $_batteryLevel%',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(12),
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

        SizedBox(height: context.rs(14)),

        // Divider: Data Identitas Peserta
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.rs(8)),
              child: Text(
                'DATA IDENTITAS PESERTA',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(10),
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
          ],
        ),
        SizedBox(height: context.rs(10)),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.poppins(
            fontSize: context.rs(13),
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            labelText: 'Nama Lengkap',
            labelStyle: GoogleFonts.poppins(
              fontSize: context.rs(11.5),
              color: const Color(0xFF64748B),
            ),
            hintText: 'Cth: Budi Santoso',
            hintStyle: GoogleFonts.poppins(
              fontSize: context.rs(12),
              color: const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            prefixIcon: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.primaryGreen,
              size: 20,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: context.rs(14),
              vertical: context.rs(12),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primaryGreen,
                width: 2,
              ),
            ),
          ),
        ),
        SizedBox(height: context.rs(10)),
        TextField(
          controller: _nisCtrl,
          keyboardType: TextInputType.text,
          style: GoogleFonts.poppins(
            fontSize: context.rs(13),
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            labelText: 'NIS / Nomor Peserta',
            labelStyle: GoogleFonts.poppins(
              fontSize: context.rs(11.5),
              color: const Color(0xFF64748B),
            ),
            hintText: 'Masukkan NIS',
            hintStyle: GoogleFonts.poppins(
              fontSize: context.rs(12),
              color: const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            prefixIcon: const Icon(
              Icons.badge_outlined,
              color: AppColors.primaryGreen,
              size: 20,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: context.rs(14),
              vertical: context.rs(12),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primaryGreen,
                width: 2,
              ),
            ),
          ),
        ),

        // Box Regulasi Anti-Curang a, b, c, d
        _buildAntiCheatCard(),

        // Checkbox Persetujuan
        _buildAgreementCheckbox(),

        SizedBox(height: context.rs(18)),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Batal',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: context.rs(12.5),
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: context.rs(10)),
            Expanded(
              flex: 2,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _agreedToRules
                        ? [const Color(0xFF1B5E20), AppColors.primaryGreen]
                        : [Colors.grey.shade400, Colors.grey.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _agreedToRules
                      ? [
                          BoxShadow(
                            color: AppColors.primaryGreen.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: ElevatedButton(
                  onPressed: _onStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Saya Paham & Mulai',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: context.rs(12.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAntiCheatCard() {
    return Container(
      margin: EdgeInsets.only(top: context.rs(14), bottom: context.rs(10)),
      padding: EdgeInsets.all(context.rs(12)),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB), // Warm amber background
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(context.rs(5)),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.gpp_maybe_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              SizedBox(width: context.rs(8)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TATA TERTIB ANTI-KECURANGAN',
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(11),
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF78350F),
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      'Ketahui 4 aturan ketat ini sebelum memulai ujian:',
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(10),
                        color: const Color(0xFF92400E),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: context.rs(8)),
          const Divider(height: 1, color: Color(0xFFFDE68A)),
          SizedBox(height: context.rs(8)),
          _buildRuleRow(
            letter: 'a',
            title: 'Dilarang Berpindah Aplikasi / Split Screen',
            desc:
                'Menekan tombol Home, Recent Apps, notifikasi, floating apps, atau split-screen langsung terdeteksi sebagai pelanggaran.',
          ),
          SizedBox(height: context.rs(6)),
          _buildRuleRow(
            letter: 'b',
            title: 'Larangan Screenshot & Rekam Layar',
            desc:
                'Fitur tangkapan layar dan rekam layar diblokir otomatis oleh sistem keamanan OS perangkat.',
          ),
          SizedBox(height: context.rs(6)),
          _buildRuleRow(
            letter: 'c',
            title: 'Pelaporan Pelanggaran Real-Time',
            desc:
                'Setiap percobaan keluar atau kecurangan otomatis tercatat dan dilaporkan langsung ke dashboard pengawas/guru.',
          ),
          SizedBox(height: context.rs(6)),
          _buildRuleRow(
            letter: 'd',
            title: 'Batas Toleransi Maksimal 3 Kali',
            desc:
                'Pelanggaran ke-3 membuat ujian TERKUNCI PERMANEN (BLOCKED) dan hasil ujian dianggap gugur.',
            isCritical: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRuleRow({
    required String letter,
    required String title,
    required String desc,
    bool isCritical = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: context.rs(18),
          height: context.rs(18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isCritical
                ? const Color(0xFFDC2626)
                : const Color(0xFFD97706),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            letter,
            style: GoogleFonts.poppins(
              fontSize: context.rs(10),
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(width: context.rs(8)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: context.rs(11),
                  fontWeight: FontWeight.w700,
                  color: isCritical
                      ? const Color(0xFF991B1B)
                      : const Color(0xFF451A03),
                ),
              ),
              Text(
                desc,
                style: GoogleFonts.poppins(
                  fontSize: context.rs(10),
                  color: const Color(0xFF78350F).withValues(alpha: 0.9),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAgreementCheckbox() {
    return Container(
      decoration: BoxDecoration(
        color: _agreedToRules
            ? AppColors.paleGreen.withValues(alpha: 0.5)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _agreedToRules ? AppColors.primaryGreen : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          value: _agreedToRules,
          onChanged: (val) => setState(() => _agreedToRules = val ?? false),
          title: Text(
            'Saya paham seluruh aturan di atas & siap mengerjakan ujian secara jujur.',
            style: GoogleFonts.poppins(
              fontSize: context.rs(11),
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: context.rs(6),
            vertical: 0,
          ),
          activeColor: AppColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
