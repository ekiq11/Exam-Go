import 'package:examgo/app_colors.dart';
import 'package:examgo/exam_browser.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'qris_web_view.dart';

double _responsiveFontSize(double baseSize, BuildContext context) {
  final shortestSide = MediaQuery.of(context).size.shortestSide;
  final scale = (shortestSide / 360.0).clamp(0.85, 1.25);
  return baseSize * scale;
}

double _responsivePadding(double baseValue, BuildContext context) {
  return _responsiveFontSize(baseValue, context);
}

double _responsiveIconSize(double baseSize, BuildContext context) {
  return _responsiveFontSize(baseSize, context);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _scannedUrl;
  bool _isConnected = true;
  List<String> _scanHistory = [];

  static const String _historyKey = 'scan_history';
  static const int _maxHistory = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkConnectivity();
    _loadScanHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadScanHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? history = prefs.getStringList(_historyKey);
    if (history != null) {
      setState(() {
        _scanHistory = List<String>.from(history.reversed);
      });
    }
  }

  Future<void> _saveToHistory(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> current = prefs.getStringList(_historyKey) ?? [];

    final updated = <String>[url];
    for (final item in current) {
      if (item != url && updated.length < _maxHistory) {
        updated.add(item);
      }
    }

    await prefs.setStringList(_historyKey, updated.take(_maxHistory).toList());
    await _loadScanHistory();
  }

  Future<void> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _isConnected = connectivityResult.isNotEmpty && !connectivityResult.contains(ConnectivityResult.none);
    });
  }

  Future<void> _scanQRCode() async {
    if (!_isConnected) {
      _showErrorDialog(
        'Tidak Ada Koneksi',
        'Pastikan perangkat terhubung ke internet sebelum memulai ujian.',
      );
      return;
    }

    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const QRScannerScreen()),
      );

      if (result != null && result.isNotEmpty && _isValidUrl(result)) {
        setState(() {
          _scannedUrl = result;
        });
        _saveToHistory(result);
        _startExam(result);
      } else if (result != null) {
        _showErrorDialog(
          'QR Code Tidak Valid',
          'QR Code yang dipindai bukan URL yang valid. Silakan coba lagi.',
        );
      }
    } catch (e) {
      debugPrint('Error scanning QR: $e');
      _showErrorDialog(
        'Error',
        'Terjadi kesalahan saat memindai QR Code.',
      );
    }
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  Future<void> _startExam(String url) async {
    final shouldStart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(_responsivePadding(8, context)),
              decoration: BoxDecoration(
                color: AppColors.info,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.info_outline,
                color: Colors.white,
                size: _responsiveIconSize(24, context),
              ),
            ),
            SizedBox(width: _responsivePadding(12, context)),
            Expanded(
              child: Text(
                'Mulai Ujian?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: _responsiveFontSize(16, context)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anda akan memulai ujian dengan fitur:',
              style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context), fontWeight: FontWeight.w600),
            ),
            SizedBox(height: _responsivePadding(16, context)),
            _buildWarningItem('🔒 Mode layar penuh (immersive)'),
            _buildWarningItem('👻 Navigasi sistem disembunyikan'),
            _buildWarningItem('📱 Orientasi terkunci (portrait)'),
            _buildWarningItem('⚠️ Peringatan jika keluar aplikasi'),
            SizedBox(height: _responsivePadding(16, context)),
            Container(
              padding: EdgeInsets.all(_responsivePadding(12, context)),
              decoration: BoxDecoration(
                color: AppColors.paleGreen,
                borderRadius: BorderRadius.circular(_responsivePadding(8, context)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link, size: _responsiveIconSize(16, context), color: AppColors.primaryGreen),
                  SizedBox(width: _responsivePadding(8, context)),
                  Expanded(
                    child: Text(
                      url,
                      style: GoogleFonts.poppins(
                        fontSize: _responsiveFontSize(11, context),
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Batal', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              padding: EdgeInsets.symmetric(vertical: _responsivePadding(12, context)),
            ),
            child: Text('Mulai Ujian', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
          ),
        ],
      ),
    );

    if (shouldStart == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => QRWebViewScreen(url: url)),
      );
    }
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: _responsivePadding(8, context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: _responsivePadding(8, context)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(fontSize: _responsiveFontSize(12, context)),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: _responsiveIconSize(20, context)),
            SizedBox(width: _responsivePadding(8, context)),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: _responsiveFontSize(16, context),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Tutup', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
          ),
        ],
      ),
    );
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    setState(() {
      _scanHistory.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_responsivePadding(24, context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: _responsivePadding(40, context)),
                  Container(
                    padding: EdgeInsets.all(_responsivePadding(32, context)),
                    decoration: BoxDecoration(
                      color: AppColors.paleGreen,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.school,
                      size: _responsiveIconSize(80, context),
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  SizedBox(height: _responsivePadding(32, context)),
                  Text(
                    'ExamGO',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: _responsiveFontSize(32, context),
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  SizedBox(height: _responsivePadding(8, context)),
                  Text(
                    'Secure Exam Browser',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: _responsiveFontSize(14, context),
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: _responsivePadding(48, context)),
                  _buildConnectionStatus(),
                  SizedBox(height: _responsivePadding(24, context)),
                  ElevatedButton.icon(
                    onPressed: _isConnected ? _scanQRCode : null,
                    icon: Icon(Icons.qr_code_scanner, size: _responsiveIconSize(28, context)),
                    label: Text(
                      'Pindai QR Code',
                      style: GoogleFonts.poppins(
                        fontSize: _responsiveFontSize(18, context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: _responsivePadding(20, context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_responsivePadding(12, context)),
                      ),
                      elevation: 2,
                    ),
                  ),
                  if (_scanHistory.isNotEmpty) ...[
                    SizedBox(height: _responsivePadding(24, context)),
                    Row(
                      children: [
                        Text(
                          'Riwayat Terakhir',
                          style: GoogleFonts.poppins(
                            fontSize: _responsiveFontSize(16, context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _clearHistory,
                          child: Text('Hapus', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
                        ),
                      ],
                    ),
                    SizedBox(height: _responsivePadding(8, context)),
                    ..._scanHistory.map((url) {
                      return Card(
                        margin: EdgeInsets.only(bottom: _responsivePadding(8, context)),
                        child: ListTile(
                          title: Text(
                            url,
                            style: GoogleFonts.poppins(fontSize: _responsiveFontSize(12, context)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.play_arrow, color: AppColors.primaryGreen),
                            onPressed: () => _startExam(url),
                            iconSize: _responsiveIconSize(20, context),
                          ),
                          onTap: () => _startExam(url),
                        ),
                      );
                    }).toList(),
                  ],
                  SizedBox(height: _responsivePadding(48, context)),
                  _buildInfoSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(_responsivePadding(16, context)),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Beranda',
            style: GoogleFonts.poppins(
              fontSize: _responsiveFontSize(18, context),
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _checkConnectivity();
            },
            tooltip: 'Refresh',
            iconSize: _responsiveIconSize(24, context),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: EdgeInsets.all(_responsivePadding(16, context)),
      decoration: BoxDecoration(
        color: _isConnected ? AppColors.paleGreen : AppColors.grey100,
        borderRadius: BorderRadius.circular(_responsivePadding(12, context)),
        border: Border.all(
          color: _isConnected ? AppColors.primaryGreen : AppColors.grey300,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            color: _isConnected ? AppColors.success : AppColors.error,
            size: _responsiveIconSize(24, context),
          ),
          SizedBox(width: _responsivePadding(12, context)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConnected ? 'Internet Terhubung' : 'Internet Tidak Terhubung',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: _isConnected ? AppColors.success : AppColors.error,
                    fontSize: _responsiveFontSize(14, context),
                  ),
                ),
                Text(
                  _isConnected ? 'Siap memulai ujian' : 'Periksa koneksi',
                  style: GoogleFonts.poppins(
                    fontSize: _responsiveFontSize(11, context),
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: EdgeInsets.all(_responsivePadding(20, context)),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.1),
        borderRadius: BorderRadius.circular(_responsivePadding(12, context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.info,
                size: _responsiveIconSize(20, context),
              ),
              SizedBox(width: _responsivePadding(8, context)),
              Text(
                'Cara Menggunakan',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: AppColors.info,
                  fontSize: _responsiveFontSize(16, context),
                ),
              ),
            ],
          ),
          SizedBox(height: _responsivePadding(12, context)),
          _buildInfoStep('1', 'Pastikan internet stabil'),
          _buildInfoStep('2', 'Pindai QR Code dari pengawas'),
          _buildInfoStep('3', 'Fokus mengerjakan ujian'),
          _buildInfoStep('4', 'Tekan "Keluar" 5x untuk keluar'),
        ],
      ),
    );
  }

  Widget _buildInfoStep(String number, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: _responsivePadding(8, context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _responsiveIconSize(24, context),
            height: _responsiveIconSize(24, context),
            decoration: BoxDecoration(
              color: AppColors.info,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: GoogleFonts.poppins(
                  fontSize: _responsiveFontSize(12, context),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SizedBox(width: _responsivePadding(12, context)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: _responsivePadding(2, context)),
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: _responsiveFontSize(13, context),
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}