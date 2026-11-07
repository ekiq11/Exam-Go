import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebGAS & Admin Integrity Tests', () {
    final adminHtmlFile = File('lib/gas_fcm/gas/admin.html');
    final kodeJsFile = File('lib/gas_fcm/gas/Kode.js');

    test('admin.html exists and is readable', () {
      expect(adminHtmlFile.existsSync(), isTrue);
      final content = adminHtmlFile.readAsStringSync();
      expect(content, isNotEmpty);
      expect(content, contains('ExamGO Administrator'));
    });

    test('admin.html has balanced script tags', () {
      final content = adminHtmlFile.readAsStringSync();
      final openMatches = RegExp(r'<script(?![^>]*src)[^>]*>').allMatches(content).length;
      final closeMatches = RegExp(r'</script>').allMatches(content).length;

      // Script tags with src also have </script>
      final srcScriptMatches = RegExp(r'<script[^>]+src=').allMatches(content).length;
      expect(openMatches + srcScriptMatches, equals(closeMatches));
    });

    test('admin.html contains partner school and bulk delete UI elements', () {
      final content = adminHtmlFile.readAsStringSync();

      // Partner school elements
      expect(content, contains('modal-add-partner'));
      expect(content, contains('add-partner-name'));
      expect(content, contains('add-partner-code'));
      expect(content, contains('edit-partner-old-code'));
      expect(content, contains('master-code'));

      // Bulk delete elements
      expect(content, contains('btn-delete-selected-students'));
      expect(content, contains('btn-delete-selected-tryout'));
      expect(content, contains('btn-delete-selected-licenses'));
    });

    test('admin.html contains valid filterTryoutTable function definition', () {
      final content = adminHtmlFile.readAsStringSync();
      // Ensure function filterTryoutTable() is explicitly declared
      expect(content, contains('function filterTryoutTable() {'));
    });

    test('admin.html contains subtest management, preset builder, and upload DOCX elements', () {
      final content = adminHtmlFile.readAsStringSync();

      // UI containers & modals
      expect(content, contains('tryout-subtest-rows-container'));
      expect(content, contains('modal-subtest-detail'));
      expect(content, contains('modal-subtest-docx-upload'));
      expect(content, contains('modal-quick-upload-tryout'));

      // Presets & JS logic
      expect(content, contains('const SUBTEST_PRESET ='));
      expect(content, contains('function onTryoutJenisChange()'));
      expect(content, contains('function openSubtestModal('));
      expect(content, contains('function openUploadDocxForSubtest('));
      expect(content, contains('function saveUploadedQuestionsToSubtest('));
    });

    test('admin.html contains executive dashboard elements and views', () {
      final content = adminHtmlFile.readAsStringSync();

      // Dashboard View and components
      expect(content, contains('id="view-dashboard"'));
      expect(content, contains('id="nav-tab-dashboard"'));
      expect(content, contains('id="dash-stat-exams"'));
      expect(content, contains('id="dash-stat-tryout-total"'));
      expect(content, contains('id="dash-stat-soal-total"'));
      expect(content, contains('id="dash-stat-licenses-total"'));
      expect(content, contains('id="dash-stat-partners-total"'));
      expect(content, contains('id="dash-recent-tryouts-container"'));
      expect(content, contains('id="dash-partners-preview-container"'));

      // Dashboard JS functions
      expect(content, contains('function showDashboardView()'));
      expect(content, contains('function loadDashboardData('));
      expect(content, contains('function renderDashboardSummary('));
      expect(content, contains('function cleanupAbandonedSessionsAction()'));
    });

    test('Kode.js contains required administrative GAS endpoints', () {
      expect(kodeJsFile.existsSync(), isTrue);
      final content = kodeJsFile.readAsStringSync();

      expect(content, contains('function getPartnerSchools('));
      expect(content, contains('function addPartnerSchool('));
      expect(content, contains('function deletePartnerSchool('));
      expect(content, contains('function deleteMultipleStudents('));
      expect(content, contains('function deleteMultipleTryouts('));
      expect(content, contains('function deleteMultipleLicenseTokens('));
      expect(content, contains('function _checkUserLogin('));

      // Subtest endpoints
      expect(content, contains('function getAdminSubtests('));
      expect(content, contains('function saveAdminSubtest('));
      expect(content, contains('function deleteAdminSubtest('));
      expect(content, contains('function saveAdminSubtestQuestions('));

      // Executive Dashboard Summary endpoint
      expect(content, contains('function getAdminDashboardSummary('));
    });

    test('Master Voucher code sanitizer regex cleans input properly', () {
      String sanitizeMasterCode(String raw) {
        return raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      }

      expect(sanitizeMasterCode('man 1 mataram'), equals('MAN1MATARAM'));
      expect(sanitizeMasterCode('SMAN-2-KOTA!'), equals('SMAN2KOTA'));
      expect(sanitizeMasterCode('  mts_01_lombok  '), equals('MTS01LOMBOK'));
      expect(sanitizeMasterCode('ABC 123 @#\$%'), equals('ABC123'));
    });
  });
}
