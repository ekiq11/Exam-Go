import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/services/license_service.dart';
import 'package:examgo/services/national_exam_evaluator.dart';
import 'package:examgo/services/student_tryout_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({});
    LicenseService.instance.setMockFirestore(fakeFirestore);
    StudentTryoutHistoryService.instance.setMockFirestore(fakeFirestore);
  });

  group('Cloud Tryout History Sync & Restore Tests for Premium Users', () {
    test('User Premium: Attempt is backed up to Firestore and restored after app reinstall', () async {
      final prefs = await SharedPreferences.getInstance();

      // 1. Set user sebagai siswa premium
      await prefs.setBool('license_student_is_premium', true);
      await prefs.setString('last_token_activated', 'SISWA-PREM-2026');

      final service = StudentTryoutHistoryService.instance;

      const eval = ExamEvaluationResult(
        category: ExamCategory.snbt,
        finalScore: 850,
        maxScore: 1000,
        totalBenar: 42,
        totalSalah: 4,
        totalKosong: 4,
        totalSoal: 50,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'Sangat Memuaskan',
        subtests: {
          'Penalaran Umum': SubtestEvaluation(
            subtestId: 'SUB_01',
            judul: 'Penalaran Umum',
            total: 10,
            benar: 9,
            salah: 1,
            kosong: 0,
            skor: 900,
            maxSkor: 1000,
            passingGrade: 600,
            isPassed: true,
            predikat: 'Sangat Baik',
          ),
        },
      );

      final question = ExamQuestion(
        soalId: 'SOAL_001',
        subtestId: 'SUB_01',
        nomorSoal: 1,
        pertanyaan: 'Berapakah 2 + 2?',
        opsiA: '3',
        opsiB: '4',
        opsiC: '5',
        opsiD: '6',
        opsiE: '7',
        kunci: 'B',
        pembahasan: '2 + 2 = 4.',
      );

      // Simpan attempt di HP pengguna
      await service.saveAttempt(
        token: 'SNBT-01',
        namaPaket: 'Tryout Akbar SNBT 2026',
        kategori: 'SNBT',
        result: eval,
        answers: {'SOAL_001': 'B'},
        questions: [question],
        allowRetake: true,
      );

      // Verifikasi tersimpan di Firestore cloud
      final snap = await fakeFirestore.collection('student_tryout_history').get();
      expect(snap.docs.length, 1);
      final cloudDoc = snap.docs.first.data();
      expect(cloudDoc['token'], 'SNBT-01');
      expect(cloudDoc['final_score'], 850);
      expect(cloudDoc['history_data']['jawaban']['SOAL_001'], 'B');

      // 2. SIMULASI: APLIKASI DIHAPUS DAN DI-INSTALL ULANG
      // SharedPreferences lokal terhapus total
      SharedPreferences.setMockInitialValues({});
      final freshPrefs = await SharedPreferences.getInstance();
      expect(freshPrefs.getStringList('student_tryout_history_list'), isNull);

      // Riwayat lokal sekarang kosong
      final emptyHistory = await service.getHistory();
      expect(emptyHistory.isEmpty, isTrue);

      // 3. User mengaktifkan kembali token premium / device dikenali
      await freshPrefs.setBool('license_student_is_premium', true);
      await freshPrefs.setString('last_token_activated', 'SISWA-PREM-2026');

      // 4. Pulihkan riwayat dari cloud
      final restored = await service.restoreHistoryFromCloud(
        licenseToken: 'SISWA-PREM-2026',
      );

      expect(restored.length, 1);
      final restoredItem = restored.first;
      expect(restoredItem.token, 'SNBT-01');
      expect(restoredItem.namaPaket, 'Tryout Akbar SNBT 2026');
      expect(restoredItem.finalScore, 850);
      expect(restoredItem.jawaban['SOAL_001'], 'B');
      expect(restoredItem.questions.length, 1);
      expect(restoredItem.questions.first.pertanyaan, 'Berapakah 2 + 2?');
      expect(restoredItem.questions.first.pembahasan, '2 + 2 = 4.');

      // 5. Cek bahwa data kini sudah tersimpan kembali di SharedPreferences lokal
      final localAgain = await service.getHistory();
      expect(localAgain.length, 1);
      expect(localAgain.first.jawaban['SOAL_001'], 'B');
    });

    test('Non-Premium User: Attempt is not uploaded to cloud', () async {
      final service = StudentTryoutHistoryService.instance;

      const eval = ExamEvaluationResult(
        category: ExamCategory.umum,
        finalScore: 700,
        maxScore: 1000,
        totalBenar: 35,
        totalSalah: 15,
        totalKosong: 0,
        totalSoal: 50,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'Baik',
        subtests: {},
      );

      // Simpan attempt tanpa status premium
      await service.saveAttempt(
        token: 'FREE-01',
        namaPaket: 'Tryout Gratis 1',
        kategori: 'UMUM',
        result: eval,
        answers: {'1': 'A'},
        questions: [],
      );

      // Verifikasi di cloud tetap kosong
      final snap = await fakeFirestore.collection('student_tryout_history').get();
      expect(snap.docs.isEmpty, isTrue);
    });
  });
}

