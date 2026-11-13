import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebGAS & Admin Integrity Tests', () {
    final adminHtmlFile = File('lib/gas_fcm/gas/admin.html');
    final landingHtmlFile = File('lib/gas_fcm/gas/landing.html');
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

      // Event tryout results endpoint
      expect(content, contains('function getEventTryoutResults('));
    });

    test('admin.html contains event tryout results modal, pagination and export functions', () {
      final content = adminHtmlFile.readAsStringSync();
      expect(content, contains('modal-event-results'));
      expect(content, contains('event-results-table-body'));
      expect(content, contains('openEventResultsModal('));
      expect(content, contains('renderEventResultsTable('));
      expect(content, contains('exportEventResultsToExcel('));
      expect(content, contains('printEventResultsReport('));
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

    test('landing.html exists, has high-converting sales structure and valid elements', () {
      expect(landingHtmlFile.existsSync(), isTrue);
      final content = landingHtmlFile.readAsStringSync();

      // Brand & Hero elements
      expect(content, contains('ExamGO'));
      expect(content, contains('hero-title-text'));
      expect(content, contains('hero-subtitle-text'));
      expect(content, anyOf(contains('btn-hero-lynkid'), contains('btn-hero-siswa-lynkid')));
      expect(content, isNot(contains('github.com/ekiq11/Exam-Go/releases')));

      // Official Store download links check (Verified Store Downloads)
      expect(content, contains('https://play.google.com/store/apps/details?id=com.kemenag.examgo'));
      expect(content, contains('https://apps.apple.com/id/app/examgo/id6759708435'));
      expect(content, contains('btn-hero-playstore'));
      expect(content, contains('btn-hero-appstore'));

      // Social Proof & Testimonials
      expect(content, contains('id="testimoni"'));
      expect(content, contains('Fathir Ramadhan'));
      expect(content, contains('Arya Pratama'));
      expect(content, contains('Zahra Nadhira'));

      // Realtime Live Purchase Activity Toast
      expect(content, contains('id="live-purchase-toast"'));
      expect(content, contains('livePurchases'));
      expect(content, contains('showLivePurchaseToast'));

      // Event Promo showcase
      expect(content, contains('featured-event-title'));
      expect(content, contains('featured-event-desc'));
      expect(content, contains('featured-event-date'));
      expect(content, contains('promo-price-discount'));
      expect(content, contains('btn-promo-lynkid'));

      // Value props & Pricing
      expect(content, contains('100% Kiosk Mode Terkunci'));
      expect(content, contains('Penalaran Umum (TPS)'));
      expect(content, contains('Siswa Premium Lifetime'));
      expect(content, contains('Guru & Proktor Premium'));
      expect(content, contains('FAQ'));

      // Hidden Admin Portal check (must not be visible to students/public)
      expect(content, isNot(contains('?page=admin')));
      expect(content, isNot(contains('Portal Admin')));

      // Logo & WhatsApp check
      expect(content, contains('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFwAAABc'));
      expect(content, contains('6289693652230'));

      // KaTeX LaTeX support check
      expect(content, contains('katex.min.css'));
      expect(content, contains('katex.min.js'));
      expect(content, contains('renderAllMath()'));

      // Official Store download links check
      // Store links & Lynk.id checkout URL
      expect(content, contains('https://lynk.id/examgo'));
      expect(content, contains('https://play.google.com/store/apps/details?id=com.kemenag.examgo'));
      expect(content, contains('https://apps.apple.com/id/app/examgo/id6759708435'));
      expect(content, contains('btn-hero-playstore'));
      expect(content, contains('btn-hero-appstore'));
      expect(content, contains('btn-mobile-lynkid'));

      // Script hydration
      expect(content, contains('google.script.run'));
      expect(content, contains('getLandingPageSettings()'));
    });

    test('admin.html contains landing page configuration tab, views and handlers', () {
      final content = adminHtmlFile.readAsStringSync();

      // Navigation & Header
      expect(content, contains('id="nav-tab-landing-config"'));
      expect(content, contains('Setting Landing Page'));
      expect(content, contains('btn-open-landing-page'));
      expect(content, contains('openLandingPage(event)'));
      expect(content, contains('function getActualLandingUrl()'));

      // Logo & WhatsApp in admin
      expect(content, contains('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFwAAABc'));
      expect(content, contains('6289693652230'));

      // View & Form elements
      expect(content, contains('id="view-landing-config"'));
      expect(content, contains('id="set-hero-title"'));
      expect(content, contains('id="set-event-title"'));
      expect(content, contains('id="set-event-active"'));
      expect(content, contains('id="set-lynkid-url"'));
      expect(content, contains('id="set-playstore-url"'));
      expect(content, contains('id="set-appstore-url"'));
      expect(content, contains('id="set-wa-number"'));
      expect(content, contains('id="btn-save-landing-settings"'));

      // JS controller functions
      expect(content, contains('function showLandingConfigView()'));
      expect(content, contains('function loadLandingSettingsToForm()'));
      expect(content, contains('function submitLandingSettingsForm()'));
    });

    test('Kode.js contains landing page routing and settings endpoints', () {
      final content = kodeJsFile.readAsStringSync();

      // Routing in doGet
      expect(content, contains('function doGet(e)'));
      expect(content, contains("HtmlService.createHtmlOutputFromFile('landing')"));
      expect(content, contains("HtmlService.createHtmlOutputFromFile('admin')"));

      // Settings Endpoints
      expect(content, contains('function getLandingPageSettings()'));
      expect(content, contains('playstore_url:'));
      expect(content, contains('appstore_url:'));
      expect(content, contains('function saveLandingPageSettings('));
    });

    test('Kode.js and admin.html contain Google Sheets tryout sync and delta detection', () {
      final kodeContent = kodeJsFile.readAsStringSync();
      final adminContent = adminHtmlFile.readAsStringSync();

      // Kode.js endpoints and helpers
      expect(kodeContent, contains('function previewTryoutFromSheets('));
      expect(kodeContent, contains('function syncTryoutSheetsToFirestore('));
      expect(kodeContent, contains('1VLByNy1aYrfY1gXiATg-sqzR3KH8HkHMdIUJw4bboMg'));
      expect(kodeContent, contains('370672055')); // Soal GID
      expect(kodeContent, contains('1773556508')); // Paket GID
      expect(kodeContent, contains('1806613765')); // Subtest GID
      expect(kodeContent, contains('1401624701')); // Jadwal GID
      expect(kodeContent, contains('_formatDriveImageUrl'));

      // admin.html UI and modal
      expect(adminContent, contains('openSheetSyncModal()'));
      expect(adminContent, contains('id="modal-sheet-sync"'));
      expect(adminContent, contains('id="sheet-sync-url-input"'));
      expect(adminContent, contains('id="btn-fetch-sheet-preview"'));
      expect(adminContent, contains('id="sheet-staging-tbody"'));
      expect(adminContent, contains('id="btn-commit-sheet-sync"'));

      // admin.html JS controller functions
      expect(adminContent, contains('function openSheetSyncModal()'));
      expect(adminContent, contains('function closeSheetSyncModal()'));
      expect(adminContent, contains('function fetchSheetPreview()'));
      expect(adminContent, contains('function renderSheetPreview('));
      expect(adminContent, contains('function renderSheetStagingTable()'));
      expect(adminContent, contains('function commitSheetSyncToFirestore()'));
      expect(adminContent, contains('function selectOnlyNewSheetRows()'));

      // Question Preview & Scrollable Table features
      expect(adminContent, contains('id="modal-sheet-question-preview"'));
      expect(adminContent, contains('id="preview-sheet-questions-list"'));
      expect(adminContent, contains('function openSheetQuestionsPreviewModal('));
      expect(adminContent, contains('function closeSheetQuestionsPreviewModal()'));
      expect(adminContent, contains('function renderSheetQuestionsContent('));
      expect(adminContent, contains('function renderTablePreview('));
      expect(adminContent, contains('function renderQuestionImage('));
      expect(adminContent, contains('overflow-y-auto shadow-sm max-h-[52vh]'));

      // User-friendly Indonesian Date Formatting
      expect(adminContent, contains('function parseDateFlexible('));
      expect(adminContent, contains('function formatIndoDate('));
      expect(adminContent, contains('function toYmdDate('));
      expect(kodeContent, contains('function _formatSheetDateToYMD('));
    });

    test('Lynk.id token generation and landing page settings auth are properly wired', () {
      final kodeContent = kodeJsFile.readAsStringSync();
      final adminContent = adminHtmlFile.readAsStringSync();

      // Lynk.id token generation
      expect(adminContent, contains('id="generated-count-badge"'));
      expect(adminContent, contains('function downloadTokensAsTxt()'));
      expect(adminContent, contains('copyTokensForWhatsApp()'));
      expect(adminContent, contains('function onTokenTypeChange()'));
      expect(adminContent, contains('function copySingleToken('));
      expect(adminContent, contains('TEACHER_PREMIUM'));
      expect(adminContent, contains('STUDENT_LIFETIME'));
      expect(kodeContent, contains('setValues(rows)'));

      // Landing page settings save auth & link persistence
      expect(adminContent, contains('.saveLandingPageSettings(settings, creds.username || creds.user, creds.password || creds.pass);'));
      expect(kodeContent, contains('playstore_url'));
      expect(kodeContent, contains('appstore_url'));
    });

    test('Lynk.id Webhook integration endpoints and UI are properly wired', () {
      final kodeContent = kodeJsFile.readAsStringSync();
      final adminContent = adminHtmlFile.readAsStringSync();

      // Kode.js webhook router & handlers
      expect(kodeContent, contains('function handleLynkIdWebhook('));
      expect(kodeContent, contains('action === \'webhook_lynk\''));
      expect(kodeContent, contains('function _findAssignedLynkToken('));
      expect(kodeContent, contains('function _claimOrCreateLynkToken('));
      expect(kodeContent, contains('function _sendBuyerTokenEmail('));
      expect(kodeContent, contains('function _recordLynkTransaction('));
      expect(kodeContent, contains('function getLynkTransactions('));
      expect(kodeContent, contains('MailApp.sendEmail'));
      expect(kodeContent, contains('lynk_transactions'));

      // admin.html Webhook UI elements
      expect(adminContent, contains('id="lynk-webhook-url-input"'));
      expect(adminContent, contains('copyLynkWebhookUrl()'));
      expect(adminContent, contains('id="modal-lynk-transactions"'));
      expect(adminContent, contains('openLynkTransactionsModal()'));
      expect(adminContent, contains('renderLynkTransactions('));
      expect(adminContent, contains('https://examgo.id/webhook'));
    });

    test('cloudflare_worker.js routes to examgo.id without myolc.my.id and proxies webhook', () {
      final workerFile = File('lib/gas_fcm/cloudflare_worker.js');
      expect(workerFile.existsSync(), isTrue);
      final workerContent = workerFile.readAsStringSync();

      // Ensure old unwanted DNS is completely eliminated
      expect(workerContent, isNot(contains('myolc.my.id')));

      // Ensure /admin embeds iframe on-domain and does NOT 302 redirect away from examgo.id
      expect(workerContent, contains('path === "/admin"'));
      expect(workerContent, contains('iframe id="admin-frame"'));
      expect(workerContent, isNot(contains('Response.redirect(GAS_ADMIN_URL, 302)')));

      // Ensure routes
      expect(workerContent, contains('GAS_ADMIN_URL = "https://script.google.com/macros/s/'));
      expect(workerContent, contains('GAS_WEBHOOK_URL = "https://script.google.com/macros/s/'));
      expect(workerContent, contains('/webhook'));
      expect(workerContent, contains('redirect: "follow"'));
    });

    test('guru.html, worker routes, and Kode.js create_teacher_exam are properly wired', () {
      final guruHtmlFile = File('lib/gas_fcm/gas/guru.html');
      final workerFile = File('lib/gas_fcm/cloudflare_worker.js');
      final kodeFile = File('lib/gas_fcm/gas/Kode.js');

      expect(guruHtmlFile.existsSync(), isTrue);
      expect(workerFile.existsSync(), isTrue);
      expect(kodeFile.existsSync(), isTrue);

      final guruContent = guruHtmlFile.readAsStringSync();
      final workerContent = workerFile.readAsStringSync();
      final kodeContent = kodeFile.readAsStringSync();

      // guru.html verification
      expect(guruContent, contains('ExamGO Guru'));
      expect(guruContent, contains('input-auth-token'));
      expect(guruContent, contains('file-docx-input'));
      expect(guruContent, contains('gform-url-input'));
      expect(guruContent, contains('btn-publish-exam'));
      expect(guruContent, contains('modal-published'));
      expect(guruContent, contains('qrcode-box'));
      expect(guruContent, contains('toggleProjectorMode()'));
      expect(guruContent, contains('renderMathInElement'));
      expect(guruContent, contains('_laptopDeviceId'));
      expect(guruContent, contains('laptop_id'));
      expect(guruContent, contains('wrapProxiedImageUrl'));
      expect(guruContent, contains('preview-pagination-top'));
      expect(guruContent, contains('preview-pagination-bottom'));
      expect(guruContent, contains('setPreviewPage'));

      // landing.html fail-safe verification
      final landingContent = landingHtmlFile.readAsStringSync();
      expect(landingContent, contains("p === '/guru'"));

      // cloudflare_worker.js verification
      expect(workerContent, contains('path === "/guru"'));
      expect(workerContent, contains('path === "/api/proxy-gform"'));
      expect(workerContent, contains('path === "/api/proxy-image"'));
      expect(workerContent, contains('path === "/template-soal-examgo.docx"'));
      expect(workerContent, contains('path === "/api/teacher-exam"'));
      expect(workerContent, contains('GITHUB_GURU_PAGE_URL'));

      // Kode.js verification
      expect(kodeContent, contains("reqAction === 'create_teacher_exam'"));
      expect(kodeContent, contains('function createTeacherExamFromWeb('));
      expect(kodeContent, contains("e.parameter.page === 'guru'"));
      expect(kodeContent, contains('laptop_device_id'));
      expect(kodeContent, contains('mobile_device_id'));
    });

    test('guru.html & Kode.js support multi-subtest, category selection & clean error sanitization', () {
      final guruHtmlFile = File('lib/gas_fcm/gas/guru.html');
      final kodeJsFile = File('lib/gas_fcm/gas/Kode.js');
      final guruContent = guruHtmlFile.readAsStringSync();
      final kodeContent = kodeJsFile.readAsStringSync();

      // UI Subtest & Kategori elements
      expect(guruContent, contains('id="exam-category"'));
      expect(guruContent, contains('id="exam-time-mode"'));
      expect(guruContent, contains('id="subtest-manager-section"'));
      expect(guruContent, contains('function addSubtest('));
      expect(guruContent, contains('function removeSubtest('));
      expect(guruContent, contains('function onExamCategoryChanged('));

      // Auto-detection tags from DOCX
      expect(guruContent, contains('SUBTEST|BABAK|SECTION'));
      expect(guruContent, contains('DURASI_SUBTEST|DURASI_BABAK'));
      expect(guruContent, contains('KATEGORI|CATEGORY'));

      // Clean error sanitization in guru.html & Kode.js
      expect(guruContent, contains('Kode lisensi guru tidak valid atau tidak terdaftar'));
      expect(kodeContent, contains('subtests_meta'));
      expect(kodeContent, contains('data.jenis_waktu'));
    });
  });
}
