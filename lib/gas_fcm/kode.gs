// ═══════════════════════════════════════════════════════════════════
// ExamGO — GAS Backend for FCM Push Notification
// ═══════════════════════════════════════════════════════════════════
//
// Script Properties yang harus diset di GAS:
//   PROJECT_ID      → examgo-31b5b
//   SA_EMAIL        → firebase-adminsdk-fbsvc@examgo-31b5b.iam.gserviceaccount.com
//   SA_PRIVATE_KEY  → -----BEGIN PRIVATE KEY-----\nMIIEv...  (full key dari JSON)
//   API_KEY         → string rahasia bebas, harus sama di Flutter --dart-define=GAS_API_KEY
//   SHEET_ID        → (opsional) ID Google Sheet untuk log pelanggaran
//
// TEACHER_FCM_TOKEN → diset otomatis saat guru buka Teacher Mode di app
//
// Cara deploy:
//   1. Buka GAS Editor → Deploy → New Deployment
//   2. Type: Web App | Execute as: Me | Access: Anyone
//   3. Copy URL → masukkan di --dart-define=GAS_URL saat flutter build
// ═══════════════════════════════════════════════════════════════════

// ── Entry point utama ───────────────────────────────────────────────
function doPost(e) {
  var props = PropertiesService.getScriptProperties();
  var data;

  try {
    data = JSON.parse(e.postData.contents);
  } catch (err) {
    return _json({ error: 'invalid_json' });
  }

  // Validasi API key
  if (!data.apiKey || data.apiKey !== props.getProperty('API_KEY')) {
    Logger.log('⛔ Unauthorized request');
    return _json({ error: 'unauthorized' });
  }

  var action = data.action || 'notify';

  // ── Guru daftar FCM token ───────────────────────────────────────
  if (action === 'registerToken') {
    if (!data.token) return _json({ error: 'missing_token' });
    props.setProperty('TEACHER_FCM_TOKEN', data.token);
    Logger.log('✅ Teacher token registered: ' + data.token.substring(0, 20) + '...');
    return _json({ success: true, action: 'registerToken' });
  }

  // ── Siswa melanggar → kirim notifikasi ke guru ──────────────────
  if (action === 'notify') {
    var teacherToken = props.getProperty('TEACHER_FCM_TOKEN');
    if (!teacherToken) {
      Logger.log('⚠️ No teacher FCM token registered. Guru belum membuka Teacher Mode.');
      return _json({ error: 'no_teacher_token' });
    }

    var violations  = data.violations  || 1;
    var studentName = data.studentName || 'Siswa';
    var studentNis  = data.studentNis  || '-';
    var examTitle   = data.examTitle   || 'Ujian';
    var examId      = data.examId      || '-';

    var title = '⚠️ Pelanggaran Ujian ke-' + violations;
    var body  = studentName + ' (' + studentNis + ') keluar dari: ' + examTitle;

    var fcmResult = _sendFcm(teacherToken, title, body, {
      examId:      examId,
      examTitle:   examTitle,
      studentName: studentName,
      studentNis:  studentNis,
      violations:  String(violations),
    });

    _logToSheet(data);

    return _json({ success: true, fcm: fcmResult });
  }

  return _json({ error: 'unknown_action', action: action });
}

// ── GET: health check (opsional) ───────────────────────────────────
function doGet(e) {
  return ContentService.createTextOutput(JSON.stringify({
    status: 'ok',
    service: 'ExamGO GAS FCM Backend',
    timestamp: new Date().toISOString(),
  })).setMimeType(ContentService.MimeType.JSON);
}

// ══════════════════════════════════════════════════════════════════
// FCM v1 API
// ══════════════════════════════════════════════════════════════════

function _sendFcm(token, title, body, dataPayload) {
  var props     = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');

  try {
    var accessToken = _getAccessToken();
    var url = 'https://fcm.googleapis.com/v1/projects/' + projectId + '/messages:send';

    var payload = {
      message: {
        token: token,
        notification: {
          title: title,
          body:  body,
        },
        android: {
          priority: 'high',
          notification: {
            sound:          'default',
            channelId:      'exam_violations',
            notificationPriority: 'PRIORITY_HIGH',
            defaultSound:   true,
            defaultVibrateTimings: true,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
        // Data payload — dapat diakses di Flutter onMessage handler
        data: dataPayload || {},
      },
    };

    var resp = UrlFetchApp.fetch(url, {
      method:          'post',
      contentType:     'application/json',
      headers:         { Authorization: 'Bearer ' + accessToken },
      payload:         JSON.stringify(payload),
      muteHttpExceptions: true,
    });

    var respText = resp.getContentText();
    var respCode = resp.getResponseCode();
    Logger.log('FCM response [' + respCode + ']: ' + respText);

    if (respCode === 200) {
      return { ok: true };
    } else {
      return { ok: false, code: respCode, detail: respText };
    }
  } catch (err) {
    Logger.log('❌ FCM error: ' + err.message);
    return { ok: false, error: err.message };
  }
}

// ══════════════════════════════════════════════════════════════════
// OAuth2 via Service Account JWT
// ══════════════════════════════════════════════════════════════════

function _getAccessToken() {
  var props  = PropertiesService.getScriptProperties();

  // FIX FCM-2: Cek cached token sebelum generate baru.
  // Token valid 1 jam, kita cache dengan buffer 60 detik untuk keamanan.
  var cached = props.getProperty('ACCESS_TOKEN');
  var expiry = props.getProperty('ACCESS_TOKEN_EXP');
  var now    = Math.floor(Date.now() / 1000);
  if (cached && expiry && parseInt(expiry) > now + 60) {
    Logger.log('✅ Menggunakan cached access token');
    return cached;
  }

  var email  = props.getProperty('SA_EMAIL');
  var rawKey = props.getProperty('SA_PRIVATE_KEY');

  if (!email || !rawKey) throw new Error('SA_EMAIL atau SA_PRIVATE_KEY belum diset di Script Properties.');

  // Konversi \n literal → newline sebenarnya
  var key = rawKey.replace(/\\n/g, '\n');

  var header = Utilities.base64EncodeWebSafe(
    JSON.stringify({ alg: 'RS256', typ: 'JWT' })
  );
  var claim = Utilities.base64EncodeWebSafe(
    JSON.stringify({
      iss:   email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud:   'https://oauth2.googleapis.com/token',
      exp:   now + 3600,
      iat:   now,
    })
  );

  var toSign   = header + '.' + claim;
  var sig      = Utilities.base64EncodeWebSafe(
    Utilities.computeRsaSha256Signature(toSign, key)
  );
  var jwt      = toSign + '.' + sig;

  var tokenResp = UrlFetchApp.fetch('https://oauth2.googleapis.com/token', {
    method:  'post',
    payload: {
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion:  jwt,
    },
    muteHttpExceptions: true,
  });

  var tokenData = JSON.parse(tokenResp.getContentText());
  if (!tokenData.access_token) {
    throw new Error('Gagal dapat access_token: ' + tokenResp.getContentText());
  }

  // Simpan ke cache dengan expiry
  props.setProperty('ACCESS_TOKEN',     tokenData.access_token);
  props.setProperty('ACCESS_TOKEN_EXP', String(now + 3600));
  Logger.log('✅ Access token baru berhasil di-cache');

  return tokenData.access_token;
}

// ══════════════════════════════════════════════════════════════════
// Log pelanggaran ke Google Sheets (opsional)
// ══════════════════════════════════════════════════════════════════

function _logToSheet(data) {
  try {
    var sheetId = PropertiesService.getScriptProperties().getProperty('SHEET_ID');
    if (!sheetId) return; // SHEET_ID tidak diset → skip logging

    var ss    = SpreadsheetApp.openById(sheetId);
    var sheet = ss.getSheets()[0]; // sheet pertama

    // Tambah header jika sheet masih kosong
    if (sheet.getLastRow() === 0) {
      sheet.appendRow([
        'Waktu', 'Exam ID', 'Judul Ujian', 'Nama Siswa', 'NIS', 'Ke-Pelanggaran'
      ]);
      sheet.getRange(1, 1, 1, 6).setFontWeight('bold');
    }

    sheet.appendRow([
      new Date(),
      data.examId      || '-',
      data.examTitle   || '-',
      data.studentName || '-',
      data.studentNis  || '-',
      data.violations  || 1,
    ]);
  } catch (err) {
    Logger.log('⚠️ Sheet log error: ' + err.message);
    // Jangan throw — log error tidak boleh gagalkan notifikasi
  }
}

// ── Helper ─────────────────────────────────────────────────────────
function _json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

// ══════════════════════════════════════════════════════════════════
// Test function — jalankan manual dari GAS Editor untuk verifikasi
// ══════════════════════════════════════════════════════════════════

function testSendNotification() {
  var props        = PropertiesService.getScriptProperties();
  var teacherToken = props.getProperty('TEACHER_FCM_TOKEN');

  if (!teacherToken) {
    Logger.log('❌ TEACHER_FCM_TOKEN belum ada. Buka Teacher Mode di app terlebih dahulu.');
    return;
  }

  var result = _sendFcm(
    teacherToken,
    '🧪 Test Notifikasi ExamGO',
    'Ini adalah notifikasi uji coba dari GAS.',
    { test: 'true' }
  );

  Logger.log('Test result: ' + JSON.stringify(result));
}

function testGetToken() {
  try {
    var token = _getAccessToken();
    Logger.log('✅ Access token berhasil: ' + token.substring(0, 30) + '...');
  } catch (e) {
    Logger.log('❌ Error: ' + e.message);
  }
}
