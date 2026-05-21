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

  static Future<Map<String, String>?> show(
    BuildContext context,
    String title,
  ) {
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
            'Nama dan NIS harus diisi',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // Simpan untuk sesi ujian selanjutnya
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_name', name);
    await prefs.setString('student_nis', nis);

    Navigator.of(context).pop({'name': name, 'nis': nis});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(context.rs(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(context.rs(10)),
                    decoration: BoxDecoration(
                      color: AppColors.paleGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_ind_rounded, color: AppColors.primaryGreen, size: 24),
                  ),
                  SizedBox(width: context.rs(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Persiapan Ujian',
                          style: GoogleFonts.poppins(
                            fontSize: context.rs(16),
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          'Lengkapi identitas Anda',
                          style: GoogleFonts.poppins(
                            fontSize: context.rs(11),
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.rs(20)),
              
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppColors.primaryGreen),
                )
              else if (_securityError != null)
                _buildSecurityError()
              else
                _buildChecklistForm(),
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
              colors: [AppColors.primaryGreen.withValues(alpha: 0.05), AppColors.paleGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(context.rs(6)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: const Icon(Icons.school_rounded, color: AppColors.primaryGreen, size: 16),
              ),
              SizedBox(width: context.rs(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sesi Ujian',
                      style: GoogleFonts.poppins(fontSize: context.rs(11), color: Colors.grey.shade600, fontWeight: FontWeight.w600),
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
        SizedBox(height: context.rs(16)),

        // Battery Info
        if (_batteryWarning)
          Container(
            margin: EdgeInsets.only(bottom: context.rs(16)),
            padding: EdgeInsets.all(context.rs(10)),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.battery_alert_rounded, color: Colors.orange.shade800, size: 20),
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
              const Icon(Icons.battery_charging_full_rounded, color: Colors.green, size: 16),
              SizedBox(width: context.rs(6)),
              Text(
                'Status Baterai: $_batteryLevel%',
                style: GoogleFonts.poppins(fontSize: context.rs(12), color: Colors.grey.shade700, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        
        SizedBox(height: context.rs(16)),
        
        // Form
        Text(
          'IDENTITAS PESERTA',
          style: GoogleFonts.poppins(
            fontSize: context.rs(11),
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: context.rs(12)),
        TextField(
          controller: _nameCtrl,
          style: GoogleFonts.poppins(fontSize: context.rs(13), fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'Nama Lengkap',
            labelStyle: GoogleFonts.poppins(fontSize: context.rs(12)),
            hintText: 'Cth: Budi Santoso',
            isDense: true,
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: EdgeInsets.symmetric(horizontal: context.rs(14), vertical: context.rs(10)),
            prefixIcon: const Icon(Icons.person_outline_rounded, color: Colors.grey, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        SizedBox(height: context.rs(12)),
        TextField(
          controller: _nisCtrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.poppins(fontSize: context.rs(13), fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'NIS / Nomor Peserta',
            labelStyle: GoogleFonts.poppins(fontSize: context.rs(12)),
            hintText: 'Masukkan NIS',
            isDense: true,
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: EdgeInsets.symmetric(horizontal: context.rs(14), vertical: context.rs(10)),
            prefixIcon: const Icon(Icons.badge_outlined, color: Colors.grey, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
          ),
        ),

        SizedBox(height: context.rs(20)),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: context.rs(12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: context.rs(12))),
              ),
            ),
            SizedBox(width: context.rs(10)),
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B5E20), AppColors.primaryGreen],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: AppColors.primaryGreen.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _onStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(vertical: context.rs(12)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Mulai Ujian', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: context.rs(13))),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
