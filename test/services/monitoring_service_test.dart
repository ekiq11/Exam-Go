import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:examgo/services/monitoring_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late MonitoringService monitoringService;

  setUp(() {
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
  });
}
