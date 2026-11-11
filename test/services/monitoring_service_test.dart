import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:examgo/services/monitoring_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late MonitoringService monitoringService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeFirestore = FakeFirebaseFirestore();
    monitoringService = MonitoringService.createForTest(fakeFirestore);
  });

  group('MonitoringService Tests', () {
    test('updateStudentStatus should set correct values', () async {
      await monitoringService.updateStudentStatus(
        examId: 'exam_123',
        nis: '1001',
        name: 'Andi',
        status: 'ACTIVE',
        violations: 2,
      );

      final docSnap = await fakeFirestore
          .collection('exam_sessions')
          .doc('exam_123')
          .collection('students')
          .doc('1001')
          .get();

      expect(docSnap.exists, true);
      final data = docSnap.data()!;
      expect(data['name'], 'Andi');
      expect(data['nis'], '1001');
      expect(data['status'], 'ACTIVE');
      expect(data['violations'], 2);
      expect(data['last_ping'], isNotNull);
    });

    test('logActivity should add log entry to student logs', () async {
      await monitoringService.logActivity(
        examId: 'exam_123',
        nis: '1001',
        activityType: 'EXIT_APP',
        description: 'Keluar aplikasi (ke-1x)',
      );

      final logsQuery = await fakeFirestore
          .collection('exam_sessions')
          .doc('exam_123')
          .collection('students')
          .doc('1001')
          .collection('logs')
          .get();

      expect(logsQuery.docs.length, 1);
      final logData = logsQuery.docs.first.data();
      expect(logData['activity_type'], 'EXIT_APP');
      expect(logData['description'], 'Keluar aplikasi (ke-1x)');
    });

    test('createExamSession should set TTL expires_at', () async {
      await monitoringService.createExamSession(
        examId: 'exam_123',
        title: 'Ujian Akhir',
        url: 'https://test.com',
      );

      final docSnap = await fakeFirestore
          .collection('exam_sessions')
          .doc('exam_123')
          .get();

      expect(docSnap.exists, true);
      final data = docSnap.data()!;
      expect(data['title'], 'Ujian Akhir');
      expect(data['url'], 'https://test.com');
      expect(data['expires_at'], isA<Timestamp>());
    });

    test('deleteExamSession should delete session and subcollections via batching', () async {
      // 1. Setup mock data
      await fakeFirestore
          .collection('exam_sessions')
          .doc('exam_123')
          .set({'title': 'To be deleted'});
      
      await fakeFirestore
          .collection('exam_sessions')
          .doc('exam_123')
          .collection('students')
          .doc('1001')
          .set({'name': 'Andi'});
          
      await fakeFirestore
          .collection('exam_sessions')
          .doc('exam_123')
          .collection('students')
          .doc('1001')
          .collection('logs')
          .add({'activity_type': 'test'});

      // 2. Perform deletion
      await monitoringService.deleteExamSession('exam_123');

      // 3. Verify deletion
      final sessionDoc = await fakeFirestore.collection('exam_sessions').doc('exam_123').get();
      expect(sessionDoc.exists, false);

      final studentsSnap = await fakeFirestore
          .collection('exam_sessions')
          .doc('exam_123')
          .collection('students')
          .get();
      expect(studentsSnap.docs.isEmpty, true);
    });

    test('Anti-Cheat: records multiple exit attempts and sets status BLOCKED at threshold', () async {
      const examId = 'event_tryout_999';
      const nis = 'NIS_007';

      // 1. Pelanggaran pertama
      await monitoringService.logActivity(
        examId: examId,
        nis: nis,
        activityType: 'EXIT_ATTEMPT',
        description: 'Peserta mencoba keluar dari aplikasi ujian (Pelanggaran ke-1)',
      );
      await monitoringService.updateStudentStatus(
        examId: examId,
        nis: nis,
        name: 'Budi',
        status: 'ONLINE',
        violations: 1,
      );

      var snap = await fakeFirestore
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis)
          .get();
      expect(snap.data()!['violations'], 1);
      expect(snap.data()!['status'], 'ONLINE');

      // 2. Pelanggaran kedua
      await monitoringService.logActivity(
        examId: examId,
        nis: nis,
        activityType: 'EXIT_ATTEMPT',
        description: 'Peserta mencoba keluar dari aplikasi ujian (Pelanggaran ke-2)',
      );
      await monitoringService.updateStudentStatus(
        examId: examId,
        nis: nis,
        name: 'Budi',
        status: 'ONLINE',
        violations: 2,
      );

      // 3. Pelanggaran ketiga (mencapai batas toleransi -> BLOCKED)
      await monitoringService.logActivity(
        examId: examId,
        nis: nis,
        activityType: 'EXIT_ATTEMPT',
        description: 'Peserta mencoba keluar dari aplikasi ujian (Pelanggaran ke-3)',
      );
      await monitoringService.updateStudentStatus(
        examId: examId,
        nis: nis,
        name: 'Budi',
        status: 'BLOCKED',
        violations: 3,
      );

      snap = await fakeFirestore
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis)
          .get();
      expect(snap.data()!['violations'], 3);
      expect(snap.data()!['status'], 'BLOCKED');

      final logs = await fakeFirestore
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis)
          .collection('logs')
          .get();
      expect(logs.docs.length, 3);

      // 4. Guru membuka blokir siswa
      await monitoringService.setStudentStatusByTeacher(
        examId: examId,
        nis: nis,
        status: 'ACTIVE',
        violations: 0,
      );

      snap = await fakeFirestore
          .collection('exam_sessions')
          .doc(examId)
          .collection('students')
          .doc(nis)
          .get();
      expect(snap.data()!['status'], 'ACTIVE');
      expect(snap.data()!['violations'], 0);
    });

    test('updateStudentStatus increments student_count only once per student', () async {
      await monitoringService.updateStudentStatus(
        examId: 'exam_count_1',
        nis: '2001',
        name: 'Citra',
        status: 'ONLINE',
        violations: 0,
      );
      await monitoringService.updateStudentStatus(
        examId: 'exam_count_1',
        nis: '2001',
        name: 'Citra',
        status: 'ONLINE',
        violations: 0,
      );

      final sessionDoc = await fakeFirestore
          .collection('exam_sessions')
          .doc('exam_count_1')
          .get();
      expect(sessionDoc.data()?['student_count'], 1);
    });
  });
}
