// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:examgo/qr_payload.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'app_colors.dart';
import 'app_config.dart';
import 'responsive.dart';

class QRGeneratorScreen extends StatefulWidget {
  const QRGeneratorScreen({super.key});

  @override
  State<QRGeneratorScreen> createState() => _QRGeneratorScreenState();
}

class _QRGeneratorScreenState extends State<QRGeneratorScreen> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  String? _qrData;
  String? _errorText;
  bool _generated = false;
  bool _saving = false;

  final _repaintKey = GlobalKey();

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  // ─── Generate ─────────────────────────────────────────────────

  void _generate() {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorText = 'URL tidak boleh kosong');
      return;
    }
    String url = raw;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    try {
      final uri = Uri.parse(url);
      if (!uri.hasAuthority) throw const FormatException('No host');
    } catch (_) {
      setState(() => _errorText = 'URL tidak valid');
      return;
    }
    final signed = QRPayloadService.generate(url);
    setState(() {
      _qrData = signed;
      _errorText = null;
      _generated = true;
    });
  }

  // ─── Save / Share ─────────────────────────────────────────────

  Future<Uint8List?> _captureQrBytes() async {
    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToGallery() async {
    if (_saving || _qrData == null) return;
    setState(() => _saving = true);

    final bytes = await _captureQrBytes();
    if (bytes == null) {
      _showSnack('Gagal memproses gambar QR', isError: true);
      setState(() => _saving = false);
      return;
    }

    try {
      if (kIsWeb) {
        _showSnack(
          'Simpan tidak tersedia di web — gunakan Bagikan',
          isError: true,
        );
        setState(() => _saving = false);
        return;
      }
      final dir = await getTemporaryDirectory();
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim().replaceAll(RegExp(r'[^\w\s]'), '')
          : 'examgo_qr';
      final file = File(
        '${dir.path}/${title}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'QR Ujian ExamGO — $title',
        text:
            'QR Code ujian terenkripsi ExamGO.\nHanya bisa dibuka melalui aplikasi ExamGO.',
      );
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _copyData() {
    if (_qrData == null) return;
    Clipboard.setData(ClipboardData(text: _qrData!));
    _showSnack('Data QR disalin ke clipboard');
  }

  void _reset() => setState(() {
    _qrData = null;
    _generated = false;
    _urlController.clear();
    _titleController.clear();
  });

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: isError ? Colors.red : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: context.rs(20)),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SizedBox(height: context.rs(20)),
                _buildInfoBanner(),
                SizedBox(height: context.rs(16)),
                _buildInputCard(),
                SizedBox(height: context.rs(14)),
                if (!_generated) _buildGenerateBtn(),
                if (_generated && _qrData != null) ...[
                  SizedBox(height: context.rs(6)),
                  _buildQRCard(),
                  SizedBox(height: context.rs(14)),
                  _buildActionRow(),
                ],
                SizedBox(height: context.rs(48)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── AppBar — serasi dengan home (gradient + dekorasi bubble) ───
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: const Color(0xFF1B5E20),
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 15,
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1B5E20),
                    AppColors.primaryGreen,
                    Color(0xFF81C784),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Bubble dekoratif
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
            ),
            Positioned(
              bottom: -10,
              left: -10,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.qr_code_2, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              'Generator QR',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        titlePadding: const EdgeInsetsDirectional.fromSTEB(56, 0, 16, 16),
        collapseMode: CollapseMode.pin,
      ),
    );
  }

  // ── Info banner — mirip guide card di home ─────────────────────
  Widget _buildInfoBanner() {
    return Container(
      padding: EdgeInsets.all(context.rs(14)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.paleGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user,
              color: AppColors.primaryGreen,
              size: 18,
            ),
          ),
          SizedBox(width: context.rs(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QR Terenkripsi HMAC-SHA256',
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(12),
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: context.rs(3)),
                Text(
                  'QR hanya bisa dibuka oleh ExamGO v${AppConfig.appVersion}. '
                  'Aplikasi lain tidak dapat membaca URL ujian.',
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(11),
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Input card — serasi dengan kartu di home ───────────────────
  Widget _buildInputCard() {
    return Container(
      padding: EdgeInsets.all(context.rs(18)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label — mirip section label history di home
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: context.rs(8)),
              Text(
                'Detail Ujian',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(14),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: context.rs(16)),

          // Judul ujian
          Text(
            'Judul Ujian (opsional)',
            style: GoogleFonts.poppins(
              fontSize: context.rs(11),
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: context.rs(6)),
          TextField(
            controller: _titleController,
            enabled: !_generated,
            decoration: InputDecoration(
              hintText: 'mis. UTS Matematika Kelas X',
              hintStyle: GoogleFonts.poppins(
                fontSize: context.rs(12),
                color: Colors.grey.shade400,
              ),
              prefixIcon: const Icon(
                Icons.school,
                color: AppColors.primaryGreen,
                size: 18,
              ),
              filled: true,
              fillColor: _generated
                  ? Colors.grey.shade50
                  : AppColors.paleGreen.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primaryGreen,
                  width: 1.5,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: context.rs(14),
                vertical: context.rs(12),
              ),
            ),
            style: GoogleFonts.poppins(fontSize: context.rs(13)),
          ),
          SizedBox(height: context.rs(14)),

          // URL
          Text(
            'URL Ujian *',
            style: GoogleFonts.poppins(
              fontSize: context.rs(11),
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: context.rs(6)),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            enabled: !_generated,
            decoration: InputDecoration(
              hintText: 'https://ujian.sekolah.sch.id/...',
              hintStyle: GoogleFonts.poppins(
                fontSize: context.rs(12),
                color: Colors.grey.shade400,
              ),
              prefixIcon: const Icon(
                Icons.link,
                color: AppColors.primaryGreen,
                size: 18,
              ),
              errorText: _errorText,
              filled: true,
              fillColor: _generated
                  ? Colors.grey.shade50
                  : AppColors.paleGreen.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primaryGreen,
                  width: 1.5,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: context.rs(14),
                vertical: context.rs(12),
              ),
            ),
            style: GoogleFonts.poppins(fontSize: context.rs(13)),
            onSubmitted: (_) => _generate(),
          ),
        ],
      ),
    );
  }

  // ── Generate button — sama persis dengan scan card di home ─────
  Widget _buildGenerateBtn() {
    return GestureDetector(
      onTap: _generate,
      child: Container(
        padding: EdgeInsets.all(context.rs(20)),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), AppColors.primaryGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withOpacity(0.38),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(context.rs(12)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.qr_code_2,
                color: Colors.white,
                size: context.rs(26),
              ),
            ),
            SizedBox(width: context.rs(16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buat QR Code',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: context.rs(16),
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    'Enkripsi HMAC-SHA256',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: context.rs(11),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(context.rs(8)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: context.rs(13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── QR Result card ─────────────────────────────────────────────
  Widget _buildQRCard() {
    final title = _titleController.text.trim();
    final displayUrl = _urlController.text.trim().startsWith('http')
        ? _urlController.text.trim()
        : 'https://${_urlController.text.trim()}';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header strip — sama seperti header webview
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.rs(18),
              vertical: context.rs(14),
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1B5E20), AppColors.primaryGreen],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Stack(
              children: [
                // Bubble dekoratif kecil
                Positioned(
                  right: -10,
                  top: -10,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.07),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.verified_user,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                    SizedBox(width: context.rs(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isNotEmpty ? title : 'QR Ujian ExamGO',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: context.rs(13),
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Terenkripsi • Hanya ExamGO',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: context.rs(10),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.rs(9),
                        vertical: context.rs(4),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'v${AppConfig.qrFormatVersion}',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: context.rs(10),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // QR Code area
          Padding(
            padding: EdgeInsets.all(context.rs(22)),
            child: RepaintBoundary(
              key: _repaintKey,
              child: Container(
                padding: EdgeInsets.all(context.rs(18)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryGreen.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: _qrData!,
                      version: QrVersions.auto,
                      size: context.rs(230),
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.textPrimary,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: context.rs(14)),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: context.rs(12),
                        vertical: context.rs(10),
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.paleGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          if (title.isNotEmpty) ...[
                            Text(
                              title,
                              style: GoogleFonts.poppins(
                                fontSize: context.rs(12),
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryGreen,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: context.rs(4)),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.lock_rounded,
                                color: AppColors.primaryGreen,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Scan dengan ExamGO',
                                style: GoogleFonts.poppins(
                                  fontSize: context.rs(10),
                                  color: AppColors.primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: context.rs(3)),
                          Text(
                            displayUrl,
                            style: GoogleFonts.poppins(
                              fontSize: context.rs(9),
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Footer note
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.rs(20),
              0,
              context.rs(20),
              context.rs(16),
            ),
            child: Text(
              'QR ini hanya bisa dibuka melalui aplikasi ExamGO.\nAplikasi scanner lain tidak dapat membaca URL ujian.',
              style: GoogleFonts.poppins(
                fontSize: context.rs(10),
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Action row ─────────────────────────────────────────────────
  Widget _buildActionRow() {
    return Column(
      children: [
        // Share — style sama dengan scan button di home
        GestureDetector(
          onTap: _saving ? null : _saveToGallery,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.all(context.rs(18)),
            decoration: BoxDecoration(
              gradient: _saving
                  ? LinearGradient(
                      colors: [Colors.grey.shade400, Colors.grey.shade500],
                    )
                  : const LinearGradient(
                      colors: [Color(0xFF2E7D32), AppColors.primaryGreen],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: _saving
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.primaryGreen.withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.rs(10)),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: context.rs(20),
                          height: context.rs(20),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                          size: context.rs(20),
                        ),
                ),
                SizedBox(width: context.rs(14)),
                Expanded(
                  child: Text(
                    _saving ? 'Memproses…' : 'Simpan / Bagikan QR',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: context.rs(15),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!_saving)
                  Container(
                    padding: EdgeInsets.all(context.rs(7)),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: context.rs(12),
                    ),
                  ),
              ],
            ),
          ),
        ),

        SizedBox(height: context.rs(10)),

        // Buat baru + Salin — style kartu outline seperti generator button di home
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _reset,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: context.rs(13)),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primaryGreen.withOpacity(0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        color: AppColors.primaryGreen,
                        size: 18,
                      ),
                      SizedBox(width: context.rs(6)),
                      Text(
                        'Buat Baru',
                        style: GoogleFonts.poppins(
                          fontSize: context.rs(13),
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: context.rs(10)),
            Expanded(
              child: GestureDetector(
                onTap: _copyData,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: context.rs(13)),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.info.withOpacity(0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.copy_rounded, color: AppColors.info, size: 18),
                      SizedBox(width: context.rs(6)),
                      Text(
                        'Salin Data',
                        style: GoogleFonts.poppins(
                          fontSize: context.rs(13),
                          color: AppColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
