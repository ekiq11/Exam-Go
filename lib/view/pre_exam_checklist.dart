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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(context.rs(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Persiapan Ujian',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: context.rs(16)),
              
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
        // Exam Title
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(context.rs(12)),
          decoration: BoxDecoration(
            color: AppColors.paleGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.school, color: AppColors.primaryGreen, size: 16),
              SizedBox(width: context.rs(8)),
              Expanded(
                child: Text(
                  widget.examTitle,
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(13),
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryGreen,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.rs(16)),

        // Battery Warning
        if (_batteryWarning)
          Container(
            margin: EdgeInsets.only(bottom: context.rs(16)),
            padding: EdgeInsets.all(context.rs(12)),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.battery_alert, color: Colors.orange.shade800, size: 20),
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
            children: [
              const Icon(Icons.battery_charging_full, color: Colors.green, size: 16),
              SizedBox(width: context.rs(6)),
              Text(
                'Baterai: $_batteryLevel%',
                style: GoogleFonts.poppins(fontSize: context.rs(12)),
              ),
            ],
          ),
        
        SizedBox(height: context.rs(20)),
        Text(
          'Identitas Peserta',
          style: GoogleFonts.poppins(
            fontSize: context.rs(14),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: context.rs(8)),
        
        // Form
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: 'Nama Lengkap',
            hintText: 'Masukkan nama Anda',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        SizedBox(height: context.rs(12)),
        TextField(
          controller: _nisCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'NIS / Nomor Peserta',
            hintText: 'Masukkan NIS',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        SizedBox(height: context.rs(24)),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(null),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: context.rs(13)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Batal', style: GoogleFonts.poppins()),
              ),
            ),
            SizedBox(width: context.rs(12)),
            Expanded(
              child: ElevatedButton(
                onPressed: _onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  padding: EdgeInsets.symmetric(vertical: context.rs(13)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Mulai Ujian', style: GoogleFonts.poppins()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
