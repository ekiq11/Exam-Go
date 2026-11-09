import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tryout_schedule_model.dart';
import 'license_service.dart';
import 'student_tryout_history_service.dart';

/// Channel khusus untuk notifikasi pengingat & evaluasi tryout
const AndroidNotificationChannel kTryoutReminderChannel = AndroidNotificationChannel(
  'tryout_reminders',
  'Pengingat & Evaluasi Tryout',
  description: 'Notifikasi pengingat pengerjaan paket tryout dan saran perbaikan nilai',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

/// Service cerdas untuk memantau paket tryout baru, tryout belum selesai,
/// pengingat pengulangan nilai belum maksimal, dan menangani push FCM.
class TryoutReminderService {
  TryoutReminderService._();
  static final TryoutReminderService instance = TryoutReminderService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _kSeenTryoutIdsKey = 'seen_tryout_package_ids';
  static const String _kLastReminderTimestampKey = 'last_tryout_reminder_time_ms';

  /// Inisialisasi channel notifikasi
  Future<void> init() async {
    try {
      final androidPlatform = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlatform?.createNotificationChannel(kTryoutReminderChannel);
    } catch (_) {}
  }

  /// Ambil ID paket tryout yang sudah pernah dilihat siswa
  Future<Set<String>> getSeenTryoutIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kSeenTryoutIdsKey) ?? [];
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  /// Tandai paket-paket tryout sebagai sudah pernah dilihat
  Future<void> markTryoutsAsSeen(List<String> paketIds) async {
    if (paketIds.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getSeenTryoutIds();
      final updated = {...current, ...paketIds}.toList();
      await prefs.setStringList(_kSeenTryoutIdsKey, updated);
    } catch (_) {}
  }

  /// Menghitung berapa paket tryout aktif yang belum dikerjakan dan masih baru/belum dilihat
  Future<int> getNewUnattemptedCount({List<TryoutSchedule>? preloadedSchedules}) async {
    try {
      final isPremium = await LicenseService.instance.isStudentPremium();
      if (!isPremium) return 0;

      final history = await StudentTryoutHistoryService.instance.getHistory();
      final attemptedTokens = history.map((e) => e.token).toSet();
      final attemptedNames = history.map((e) => e.namaPaket.trim().toLowerCase()).toSet();

      final schedules = preloadedSchedules ?? await _fetchActiveSchedules();
      final seenIds = await getSeenTryoutIds();

      int count = 0;
      final now = DateTime.now();

      for (final s in schedules) {
        final isAttempted = attemptedTokens.contains(s.paketId) ||
            attemptedNames.contains(s.namaPaket.trim().toLowerCase());
        if (isAttempted) continue;

        // Cek jika tryout baru (belum pernah dilihat atau rilis dalam 7 hari terakhir)
        bool isNew = !seenIds.contains(s.paketId);
        if (!isNew && s.tanggal.isNotEmpty) {
          final dt = DateTime.tryParse(s.tanggal);
          if (dt != null) {
            final diff = now.difference(dt).inDays;
            if (diff >= -1 && diff <= 7) isNew = true;
          }
        }

        if (isNew) count++;
      }

      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Cek kondisi dan picu notifikasi lokal pengingat otomatis jika cooldown sudah terpenuhi
  /// - Prioritas 1: Paket tryout baru yang belum dikerjakan
  /// - Prioritas 2: Tryout yang sudah dikerjakan tetapi nilainya belum lulus/belum maksimal (< 70%)
  Future<bool> checkAndSendLocalReminder({
    List<TryoutSchedule>? preloadedSchedules,
    bool ignoreCooldown = false,
  }) async {
    try {
      final isPremium = await LicenseService.instance.isStudentPremium();
      if (!isPremium) return false;

      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_kLastReminderTimestampKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Cooldown minimal 12 jam antar notifikasi otomatis agar tidak spam
      const cooldownMs = 12 * 60 * 60 * 1000;
      if (!ignoreCooldown && (nowMs - lastMs < cooldownMs)) {
        return false;
      }

      final history = await StudentTryoutHistoryService.instance.getHistory();
      final attemptedTokens = history.map((e) => e.token).toSet();
      final attemptedNames = history.map((e) => e.namaPaket.trim().toLowerCase()).toSet();

      final schedules = preloadedSchedules ?? await _fetchActiveSchedules();

      // Prioritas 1: Cari tryout aktif yang belum dikerjakan
      TryoutSchedule? unattemptedSchedule;
      for (final s in schedules) {
        final done = attemptedTokens.contains(s.paketId) ||
            attemptedNames.contains(s.namaPaket.trim().toLowerCase());
        if (!done) {
          unattemptedSchedule = s;
          break;
        }
      }

      if (unattemptedSchedule != null) {
        await showReminderNotification(
          title: '📚 Tryout Siap Dikerjakan!',
          body:
              'Paket "${unattemptedSchedule.namaPaket}" belum kamu kerjakan. Uji kemampuanmu sekarang yuk!',
          payload: jsonEncode({'type': 'unattempted', 'paketId': unattemptedSchedule.paketId}),
        );
        await prefs.setInt(_kLastReminderTimestampKey, nowMs);
        return true;
      }

      // Prioritas 2: Cari tryout yang sudah dikerjakan tetapi nilai belum maksimal dan bisa diulang
      StudentTryoutHistoryItem? retakeCandidate;
      for (final h in history) {
        final scorePct = h.maxScore > 0 ? (h.finalScore / h.maxScore) : 0.0;
        final needsImprovement = !h.isPassed || scorePct < 0.70;
        if (needsImprovement && h.allowRetake) {
          retakeCandidate = h;
          break;
        }
      }

      if (retakeCandidate != null) {
        await showReminderNotification(
          title: '🎯 Tingkatkan Skor Tryout!',
          body:
              'Skor "${retakeCandidate.namaPaket}" kamu (${retakeCandidate.finalScore}) masih bisa ditingkatkan. Ulangi untuk hasil maksimal!',
          payload: jsonEncode({'type': 'retake', 'token': retakeCandidate.token}),
        );
        await prefs.setInt(_kLastReminderTimestampKey, nowMs);
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Menampilkan notifikasi lokal Android & iOS via FlutterLocalNotifications
  Future<void> showReminderNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final id = (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 2147483647;
      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'tryout_reminders',
            'Pengingat & Evaluasi Tryout',
            channelDescription:
                'Notifikasi pengingat pengerjaan paket tryout dan saran perbaikan nilai',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (_) {}
  }

  /// Menangani pesan FCM RemoteMessage jika mengandung instruksi pengingat tryout
  Future<void> handleFcmReminder(
    Map<String, dynamic> data,
    String? notificationTitle,
    String? notificationBody,
  ) async {
    final type = (data['type'] ?? data['action'] ?? '').toString();
    if (type == 'tryout_reminder' ||
        type == 'unattempted_reminder' ||
        type == 'retake_reminder') {
      final title = notificationTitle ?? data['title'] ?? '📚 Pengingat Tryout ExamGO';
      final body = notificationBody ??
          data['body'] ??
          'Ada paket tryout yang menunggumu. Buka aplikasi untuk mengerjakan!';
      await showReminderNotification(
        title: title.toString(),
        body: body.toString(),
        payload: jsonEncode(data),
      );
    }
  }

  Future<List<TryoutSchedule>> _fetchActiveSchedules() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('paket_tryout')
          .where('status', isEqualTo: 'aktif')
          .get();
      return snap.docs
          .map((doc) => TryoutSchedule.fromMap(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
