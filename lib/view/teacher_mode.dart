// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/services/qr_generator.dart';
import 'package:examgo/view/teacher_monitoring_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────
// Konstanta
// ─────────────────────────────────────────────────────────────
const _kPinKey = 'teacher_pin_hash';

String _hashPin(String pin) =>
    sha256.convert(utf8.encode('examgo_teacher_$pin')).toString();

// ─────────────────────────────────────────────────────────────
// Entry point: cek apakah PIN sudah diset, lalu arahkan
// ─────────────────────────────────────────────────────────────
Future<void> openTeacherMode(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final hasPin = prefs.getString(_kPinKey) != null;

  if (!context.mounted) return;

  if (hasPin) {
    // Sudah ada PIN → minta verifikasi
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _TeacherPinScreen(mode: _PinMode.verify),
      ),
    );
  } else {
    // Belum ada PIN → minta buat baru
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _TeacherPinScreen(mode: _PinMode.create),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PIN Screen
// ─────────────────────────────────────────────────────────────
enum _PinMode { create, verify }

class _TeacherPinScreen extends StatefulWidget {
  final _PinMode mode;
  const _TeacherPinScreen({required this.mode});

  @override
  State<_TeacherPinScreen> createState() => _TeacherPinScreenState();
}

class _TeacherPinScreenState extends State<_TeacherPinScreen> {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _hasError = false;
  String _errorMsg = '';
  bool _biometricAvailable = false;
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    if (widget.mode == _PinMode.verify) {
      _checkBiometricAndPrompt();
    }
  }

  Future<void> _checkBiometricAndPrompt() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (canCheck && isSupported) {
        setState(() => _biometricAvailable = true);
        // Langsung picu biometrik saat layar dibuka
        await Future.delayed(const Duration(milliseconds: 400));
        _authenticateWithBiometric();
      }
    } catch (_) {
      // Biometrik tidak tersedia, fallback ke PIN
    }
  }

  Future<void> _authenticateWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Verifikasi sidik jari / Face ID untuk masuk Mode Guru',
        options: const AuthenticationOptions(
          biometricOnly: false, // Izinkan fallback ke PIN device jika biometrik gagal
          stickyAuth: true,     // Jangan batalkan saat app ke background
          useErrorDialogs: true,
        ),
      );
      if (authenticated && mounted) {
        _goToDashboard();
      }
    } catch (_) {
      // Gagal → user masukkan PIN manual
    }
  }

  void _onDigit(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _hasError = false;
    });
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), _onPinComplete);
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _onPinComplete() async {
    if (widget.mode == _PinMode.create) {
      if (!_isConfirming) {
        // Simpan PIN pertama, minta konfirmasi
        setState(() {
          _confirmPin = _pin;
          _pin = '';
          _isConfirming = true;
        });
      } else {
        // Verifikasi konfirmasi
        if (_pin == _confirmPin) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kPinKey, _hashPin(_pin));
          if (!mounted) return;
          _goToDashboard();
        } else {
          setState(() {
            _pin = '';
            _confirmPin = '';
            _isConfirming = false;
            _hasError = true;
            _errorMsg = 'PIN tidak cocok. Coba lagi.';
          });
        }
      }
    } else {
      // Verify mode
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_kPinKey);
      if (_hashPin(_pin) == stored) {
        if (!mounted) return;
        _goToDashboard();
      } else {
        setState(() {
          _pin = '';
          _hasError = true;
          _errorMsg = 'PIN salah. Coba lagi.';
        });
        HapticFeedback.heavyImpact();
      }
    }
  }

  void _goToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TeacherDashboardScreen()),
    );
  }

  String get _title {
    if (widget.mode == _PinMode.create) {
      return _isConfirming ? 'Konfirmasi PIN' : 'Buat PIN Guru';
    }
    return 'Masuk Mode Guru';
  }

  String get _subtitle {
    if (widget.mode == _PinMode.create) {
      return _isConfirming
          ? 'Masukkan PIN yang sama sekali lagi'
          : 'Buat PIN 4 digit untuk akses guru';
    }
    return 'Masukkan PIN 4 digit Anda';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Mode Guru', style: GoogleFonts.poppins()),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 48,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                _title,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hasError
                          ? Colors.red
                          : filled
                              ? AppColors.primaryGreen
                              : Colors.grey.shade300,
                    ),
                  );
                }),
              ),

              // Error message
              if (_hasError) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMsg,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.red,
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // Numpad
              _buildNumpad(),

              // Tombol Biometrik (hanya di mode verify & jika tersedia)
              if (widget.mode == _PinMode.verify && _biometricAvailable) ...[
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _authenticateWithBiometric,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primaryGreen.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.fingerprint_rounded,
                          size: 36,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Gunakan Sidik Jari / Face ID',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    final digits = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: digits.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((d) {
            // Di mode verify, slot kosong di bawah ganti jadi ikon biometrik (jika tersedia)
            if (d.isEmpty && widget.mode == _PinMode.verify && _biometricAvailable) {
              return GestureDetector(
                onTap: _authenticateWithBiometric,
                child: Container(
                  width: 80,
                  height: 60,
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primaryGreen.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.fingerprint_rounded,
                        color: AppColors.primaryGreen, size: 28),
                  ),
                ),
              );
            }
            if (d.isEmpty) return const SizedBox(width: 80, height: 60);
            return GestureDetector(
              onTap: () {
                if (d == '⌫') {
                  _onDelete();
                } else {
                  _onDigit(d);
                }
              },
              child: Container(
                width: 80,
                height: 60,
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: d == '⌫' ? Colors.red.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    d,
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: d == '⌫' ? Colors.red : Colors.black87,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Teacher Dashboard Screen
// ─────────────────────────────────────────────────────────────
class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('Dashboard Guru', style: GoogleFonts.poppins()),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset_rounded),
            tooltip: 'Reset PIN',
            onPressed: () => _resetPin(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), AppColors.primaryGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school_rounded, color: Colors.white, size: 36),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConfig.appName,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Versi ${AppConfig.appVersion} — Mode Guru',
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'Menu',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),

            // Menu tiles
            _MenuTile(
              icon: Icons.qr_code_2_rounded,
              color: AppColors.primaryGreen,
              title: 'Buat QR Ujian',
              subtitle: 'Generate QR Code untuk peserta',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QRGeneratorScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.monitor_heart_rounded,
              color: Colors.orange,
              title: 'Monitoring Ujian',
              subtitle: 'Pantau aktivitas peserta ujian',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TeacherMonitoringListScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.info_outline_rounded,
              color: Colors.blue,
              title: 'Tentang Aplikasi',
              subtitle: 'Versi, lisensi, dan informasi app',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: AppConfig.appName,
                applicationVersion: AppConfig.appVersion,
                applicationLegalese: '© Kemenag — Secure Exam Browser',
              ),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.logout_rounded,
              color: Colors.red,
              title: 'Keluar Mode Guru',
              subtitle: 'Kembali ke tampilan siswa',
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPin(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reset PIN?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          'PIN akan dihapus. Anda harus membuat PIN baru.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Batal', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Reset', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinKey);
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

// ─────────────────────────────────────────────────────────────
// Widget pembantu
// ─────────────────────────────────────────────────────────────
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
