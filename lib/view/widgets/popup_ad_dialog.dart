import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constant/app_colors.dart';
import '../../services/popup_ad_service.dart';
import '../../utils/math_widget_factory.dart';

class PopupAdDialog extends StatelessWidget {
  final PopupAdItem ad;
  final String roleBadge;

  const PopupAdDialog({
    super.key,
    required this.ad,
    this.roleBadge = '',
  });

  static Future<void> show(
    BuildContext context, {
    required PopupAdItem ad,
    String roleBadge = '',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PopupAdDialog(ad: ad, roleBadge: roleBadge),
    );
  }

  Future<void> _launchCta(BuildContext context) async {
    final rawUrl = ad.ctaUrl.trim().isNotEmpty ? ad.ctaUrl.trim() : 'https://lynk.id';
    final uri = Uri.tryParse(rawUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      elevation: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Konten Utama Iklan
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Gambar 1:1 Persegi
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: CachedNetworkImage(
                          imageUrl: ad.imageUrl,
                          httpHeaders: MathHtmlFormatter.networkImageHeaders,
                          fit: BoxFit.cover,
                          placeholder: (ctx, url) => Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                          errorWidget: (ctx, url, err) => Container(
                            color: const Color(0xFFF8FAFC),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.broken_image_rounded, size: 48, color: Color(0xFF94A3B8)),
                                const SizedBox(height: 8),
                                Text(
                                  'Gambar promosi tidak dapat dimuat',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Bagian Bawah: Judul & Tombol CTA Lynk.id
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (ad.title.isNotEmpty) ...[
                            Text(
                              ad.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Tombol CTA Lynk.id
                          ElevatedButton(
                            onPressed: () => _launchCta(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.shopping_bag_outlined, size: 18),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Dapatkan Sekarang di Lynk.id',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_rounded, size: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Tombol Close ('X') Melayang
              Positioned(
                top: -12,
                right: -12,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),

              // Badge Info Role (Opsional)
              if (roleBadge.isNotEmpty)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      roleBadge,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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
}

