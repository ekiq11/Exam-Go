import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'app_config.dart';

/// Decoded & validated ExamGO QR payload.
class ExamQRPayload {
  final String url;
  final String title; // ← nama ujian, bisa kosong
  final int timestamp;
  final String nonce;
  final int version;

  const ExamQRPayload({
    required this.url,
    required this.title,
    required this.timestamp,
    required this.nonce,
    required this.version,
  });
}

class QRPayloadService {
  QRPayloadService._();

  static const _key = AppConfig.qrSecretKey;
  static const _prefix = AppConfig.qrPrefix;

  // ─── Generate ─────────────────────────────────────────────────

  /// [url] wajib. [title] opsional — nama ujian yang ditampilkan ke user.
  static String generate(String url, {String title = ''}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nonce = _randomNonce(8);
    final version = AppConfig.qrFormatVersion;

    final data = jsonEncode({
      'v': version,
      'url': url,
      'title': title,
      'ts': timestamp,
      'nonce': nonce,
    });

    return jsonEncode({'app': _prefix, 'data': data, 'sig': _sign(data)});
  }

  // ─── Validate ─────────────────────────────────────────────────

  static ExamQRPayload? validate(String raw) {
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      if (envelope['app'] != _prefix) return null;

      final dataJson = envelope['data'] as String;
      final sig = envelope['sig'] as String;
      if (!_verify(dataJson, sig)) return null;

      final data = jsonDecode(dataJson) as Map<String, dynamic>;
      final version = (data['v'] as num?)?.toInt() ?? 0;
      if (version != AppConfig.qrFormatVersion) return null;

      if (AppConfig.qrExpiryMinutes > 0) {
        final ts = (data['ts'] as num).toInt();
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (now - ts > AppConfig.qrExpiryMinutes * 60) return null;
      }

      final url = data['url'] as String? ?? '';
      if (url.isEmpty) return null;

      return ExamQRPayload(
        url: url,
        title: (data['title'] as String?) ?? '',
        timestamp: (data['ts'] as num).toInt(),
        nonce: data['nonce'] as String,
        version: version,
      );
    } catch (_) {
      return null;
    }
  }

  static bool looksLikeExamQR(String raw) =>
      raw.contains('"app"') && raw.contains(_prefix);

  // ─── Internals ────────────────────────────────────────────────

  static String _sign(String data) {
    final hmac = Hmac(sha256, utf8.encode(_key));
    return hmac.convert(utf8.encode(data)).toString();
  }

  static bool _verify(String data, String sig) => _sign(data) == sig;

  static String _randomNonce(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
  }
}
