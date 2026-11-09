import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constant/app_config.dart';
import '../utils/math_widget_factory.dart';

class PopupAdItem {
  final String imageUrl;
  final String ctaUrl;
  final String title;
  final bool isActive;

  const PopupAdItem({
    required this.imageUrl,
    required this.ctaUrl,
    required this.title,
    required this.isActive,
  });

  factory PopupAdItem.fromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return const PopupAdItem(
        imageUrl: '',
        ctaUrl: 'https://lynk.id',
        title: '',
        isActive: false,
      );
    }

    var imgUrl = data['imageUrl']?.toString().trim() ?? '';
    if (imgUrl.isNotEmpty) {
      imgUrl = MathHtmlFormatter.convertDriveUrl(imgUrl);
      if (!imgUrl.startsWith('http://') && !imgUrl.startsWith('https://')) {
        imgUrl = 'https://$imgUrl';
      }
    }

    var cta = data['ctaUrl']?.toString().trim() ?? 'https://lynk.id';
    if (cta.isEmpty) cta = 'https://lynk.id';
    if (!cta.startsWith('http://') && !cta.startsWith('https://')) {
      cta = 'https://$cta';
    }

    return PopupAdItem(
      imageUrl: imgUrl,
      ctaUrl: cta,
      title: data['title']?.toString().trim() ?? '',
      isActive: data['isActive'] == true || data['isActive']?.toString().toLowerCase() == 'true',
    );
  }

  bool get isValid => isActive && imageUrl.isNotEmpty;
}

class PopupAdsConfig {
  final PopupAdItem student;
  final PopupAdItem teacher;
  final PopupAdItem event;

  const PopupAdsConfig({
    required this.student,
    required this.teacher,
    required this.event,
  });

  factory PopupAdsConfig.empty() {
    return PopupAdsConfig(
      student: PopupAdItem.fromMap(null),
      teacher: PopupAdItem.fromMap(null),
      event: PopupAdItem.fromMap(null),
    );
  }

  factory PopupAdsConfig.fromMap(Map<String, dynamic> data) {
    return PopupAdsConfig(
      student: PopupAdItem.fromMap(data['student'] as Map<String, dynamic>?),
      teacher: PopupAdItem.fromMap(data['teacher'] as Map<String, dynamic>?),
      event: PopupAdItem.fromMap(data['event'] as Map<String, dynamic>?),
    );
  }
}

class PopupAdService {
  PopupAdService._();
  static final PopupAdService instance = PopupAdService._();

  PopupAdsConfig? _cachedConfig;
  DateTime? _lastFetchTime;

  /// Mengambil konfigurasi iklan dari Firestore (prioritas) atau backend GAS (fallback)
  Future<PopupAdsConfig> getAdsConfig({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedConfig != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!).inMinutes < 5) {
      return _cachedConfig!;
    }

    // 1. Coba ambil dari Firestore app_settings/popup_ads
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('popup_ads')
          .get();

      if (doc.exists && doc.data() != null) {
        final config = PopupAdsConfig.fromMap(doc.data()!);
        _cachedConfig = config;
        _lastFetchTime = DateTime.now();
        return config;
      }
    } catch (e) {
      debugPrint('PopupAdService Firestore read error: $e');
    }

    // 2. Fallback: ambil dari GAS REST API
    try {
      final gasUrl = AppConfig.gasUrl;
      if (gasUrl.isNotEmpty) {
        final uri = Uri.parse(gasUrl).replace(queryParameters: {'action': 'get_ads'});
        final resp = await http.get(uri).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map<String, dynamic>) {
            final config = PopupAdsConfig.fromMap(data);
            _cachedConfig = config;
            _lastFetchTime = DateTime.now();
            return config;
          }
        }
      }
    } catch (e) {
      debugPrint('PopupAdService GAS read error: $e');
    }

    return _cachedConfig ?? PopupAdsConfig.empty();
  }
}

