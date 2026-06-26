import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/constant/app_config.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String downloadUrl;
  final DateTime publishedAt;

  // NOTE: tidak pakai `const` — DateTime bukan compile-time constant
  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.publishedAt,
  });

  bool get hasUpdate => _compareVersions(latestVersion, currentVersion) > 0;

  /// true jika major version berbeda → update wajib, tidak bisa skip/dismiss
  // To force all updates according to user request, we return true if there's an update
  bool get isMajorUpdate => hasUpdate;

  static int _compareVersions(String a, String b) {
    final av = a.replaceAll(RegExp(r'[^0-9.]'), '').split('.');
    final bv = b.replaceAll(RegExp(r'[^0-9.]'), '').split('.');
    final len = av.length > bv.length ? av.length : bv.length;
    for (int i = 0; i < len; i++) {
      final ai = i < av.length ? (int.tryParse(av[i]) ?? 0) : 0;
      final bi = i < bv.length ? (int.tryParse(bv[i]) ?? 0) : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }
}

class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  // ── Ganti dengan repo GitHub Anda ─────────────────────────────
  // Format: https://api.github.com/repos/{owner}/{repo}/releases/latest
  static const String _apiUrl =
      'https://api.github.com/repos/kemenag-ri/examgo/releases/latest';

  // Wajib sync manual dengan pubspec.yaml setiap rilis
  static const String _currentVersion = AppConfig.appVersion;

  static const String _skipKey = 'skipped_version';
  static const String _lastCheckKey = 'last_update_check';
  static const Duration _checkInterval = Duration(hours: 6);

  /// Cek update. Return null jika tidak ada update, throttled, atau error.
  Future<UpdateInfo?> checkForUpdate({bool force = true}) async {
    try {
      if (!force && !await _shouldCheck()) return null;

      final response = await http
          .get(
            Uri.parse(_apiUrl),
            headers: {
              'Accept': 'application/vnd.github.v3+json',
              'User-Agent': 'ExamGO-App/$_currentVersion',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      await _saveLastCheckTime();

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      // Guard: tag_name kosong
      final rawTag = json['tag_name'] as String? ?? '';
      if (rawTag.isEmpty) return null;
      // replaceFirst 'v' di depan saja (bukan replaceAll)
      final tagName = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;

      final body = json['body'] as String? ?? '';
      final prerelease = json['prerelease'] as bool? ?? false;
      final publishedAt =
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now();

      if (prerelease) return null;

      // Cari APK download URL dari assets
      final assets = json['assets'] as List<dynamic>? ?? [];
      final apkAsset =
          assets.firstWhere(
                (a) => (a['name'] as String? ?? '').endsWith('.apk'),
                orElse: () => <String, dynamic>{},
              )
              as Map<String, dynamic>;
      final downloadUrl =
          apkAsset['browser_download_url'] as String? ??
          json['html_url'] as String? ??
          'https://github.com/kemenag-ri/examgo/releases/latest';

      final info = UpdateInfo(
        latestVersion: tagName,
        currentVersion: _currentVersion,
        releaseNotes: _parseReleaseNotes(body),
        downloadUrl: downloadUrl,
        publishedAt: publishedAt,
      );

      if (!info.hasUpdate) return null;

      final skipped = await _getSkippedVersion();
      if (skipped == tagName) return null;

      return info;
    } catch (_) {
      return null;
    }
  }

  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipKey, version);
  }

  Future<void> clearSkip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skipKey);
  }

  Future<bool> _shouldCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheck;
    return elapsed > _checkInterval.inMilliseconds;
  }

  Future<void> _saveLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<String?> _getSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_skipKey);
  }

  /// Bersihkan markdown dari release notes GitHub.
  /// FIXED:
  ///   - Tidak pakai backreference r'\1' (tidak valid di Dart replaceAll)
  ///   - Tidak pakai lookbehind (?<!...) (tidak didukung Dart RegExp)
  ///   - String interpolasi benar: ${...} bukan \${...}
  ///   - Gunakan replaceAllMapped untuk capture group
  String _parseReleaseNotes(String raw) {
    if (raw.isEmpty) return 'Perbaikan bug dan peningkatan performa.';

    var s = raw;

    // Hapus heading: ## Title → (kosong)
    s = s.replaceAll(RegExp(r'#{1,6}\s?'), '');

    // Hapus bold/italic — strip marker langsung tanpa backreference
    s = s.replaceAll('**', '');
    s = s.replaceAll('__', '');
    s = s.replaceAll('*', '');
    s = s.replaceAll('_', '');

    // Hapus inline code
    s = s.replaceAll(RegExp(r'`+'), '');

    // Markdown link [text](url) → text
    // FIXED: pakai replaceAllMapped + match.group() bukan r'\1'
    s = s.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m.group(1) ?? '',
    );

    // Normalize line endings
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

    // FIXED: string interpolasi Dart yang benar
    return s.length > 300 ? '${s.substring(0, 297)}...' : s;
  }
}
