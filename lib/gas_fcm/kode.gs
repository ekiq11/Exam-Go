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

    // FIX MULTI-TEACHER: Simpan array of tokens agar lebih dari 1 guru bisa menerima notifikasi
    var tokensStr = props.getProperty('TEACHER_FCM_TOKENS') || '[]';
    var tokens = JSON.parse(tokensStr);
    
    // Tambahkan token jika belum ada
    if (tokens.indexOf(data.token) === -1) {
      tokens.push(data.token);
      // Batasi maksimal 20 guru agar ukuran string tidak membebani Script Properties
      if (tokens.length > 20) tokens.shift();
      props.setProperty('TEACHER_FCM_TOKENS', JSON.stringify(tokens));
    }

    if (data.examId) {
      var key = 'TEACHER_TOKENS_' + data.examId;
      var examTokensStr = props.getProperty(key) || '[]';
      var examTokens = JSON.parse(examTokensStr);
      if (examTokens.indexOf(data.token) === -1) {
        examTokens.push(data.token);
        if (examTokens.length > 10) examTokens.shift();
        props.setProperty(key, JSON.stringify(examTokens));
        props.setProperty(key + '_TS', String(Date.now()));
      }
      Logger.log('✅ Token registered for examId [' + data.examId + ']: ' + data.token.substring(0, 20) + '...');
    }

    // Tetap simpan token tunggal sebagai fallback (backward-compat)
    props.setProperty('TEACHER_FCM_TOKEN', data.token);
    Logger.log('✅ Global teacher token updated: ' + data.token.substring(0, 20) + '...');

    // Bersihkan token lama (>7 hari) agar Script Properties tidak penuh
    _cleanupStaleTokens(props);

    return _json({ success: true, action: 'registerToken' });
  }

  // ── Siswa melanggar → kirim notifikasi ke guru ──────────────────
  if (action === 'notify') {
    var examId = data.examId || '';

    // Ambil target token (multi-guru)
    var targetTokens = [];
    
    if (examId) {
      var examTokensStr = props.getProperty('TEACHER_TOKENS_' + examId);
      if (examTokensStr) {
        try { targetTokens = JSON.parse(examTokensStr); } catch(e) {}
      }
    }

    if (targetTokens.length === 0) {
      Logger.log('⚠️ Tidak ada teacher FCM token spesifik untuk ujian ini. Guru belum membuka layar monitoring.');
      return _json({ error: 'no_teacher_token' });
    }

    var violations  = data.violations  || 1;
    var studentName = data.studentName || 'Siswa';
    var studentNis  = data.studentNis  || '-';
    var examTitle   = data.examTitle   || 'Ujian';

    var title = '⚠️ Pelanggaran Ujian ke-' + violations;
    var body  = studentName + ' (' + studentNis + ') keluar dari: ' + examTitle;

    var results = [];
    for (var i = 0; i < targetTokens.length; i++) {
      var fcmResult = _sendFcm(targetTokens[i], title, body, {
        examId:      examId,
        examTitle:   examTitle,
        studentName: studentName,
        studentNis:  studentNis,
        violations:  String(violations),
      });
      results.push(fcmResult);
    }

    _logToSheet(data);

    return _json({ success: true, results: results });
  }

  return _json({ error: 'unknown_action', action: action });
}

// ── Hapus token examId yang sudah lebih dari 7 hari ────────────────
function _cleanupStaleTokens(props) {
  try {
    var allProps = props.getProperties();
    var now = Date.now();
    var sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
    Object.keys(allProps).forEach(function(key) {
      if ((key.indexOf('TEACHER_TOKEN') === 0) && key.indexOf('_TS') === -1) {
        var tsKey = key + '_TS';
        var ts = parseInt(allProps[tsKey] || '0');
        if (ts > 0 && (now - ts) > sevenDaysMs) {
          props.deleteProperty(key);
          props.deleteProperty(tsKey);
          Logger.log('🧹 Token kadaluarsa dihapus: ' + key);
        }
      }
    });
  } catch (e) {
    Logger.log('⚠️ Cleanup error (abaikan): ' + e.message);
  }
}


// ── GET: Render Dashboard HTML ───────────────────────────────────
function doGet(e) {
  // Untuk kompatibilitas jika ada yang ping GET, kita bisa kembalikan JSON,
  // tapi secara default kita kembalikan halaman Web App Dashboard.
  if (e.parameter.api === 'true') {
    return ContentService.createTextOutput(JSON.stringify({
      status: 'ok',
      service: 'ExamGO GAS Backend',
      timestamp: new Date().toISOString(),
    })).setMimeType(ContentService.MimeType.JSON);
  }
  
  // Render file admin.html
  return HtmlService.createHtmlOutputFromFile('admin')
    .setTitle('ExamGO Administrator')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
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
  var cached = props.getProperty('ACCESS_TOKEN_V2');
  var expiry = props.getProperty('ACCESS_TOKEN_EXP_V2');
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
      scope: 'https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore',
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
  props.setProperty('ACCESS_TOKEN_V2',     tokenData.access_token);
  props.setProperty('ACCESS_TOKEN_EXP_V2', String(now + 3600));
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

// ══════════════════════════════════════════════════════════════════
// ADMIN DASHBOARD FUNCTIONS (Dipanggil via google.script.run)
// ══════════════════════════════════════════════════════════════════

/**
 * Validasi PIN Admin. 
 * Default: 'admin123' jika DASHBOARD_PIN belum di-set di Script Properties.
 */
function _checkAdminPin(pin) {
  var props = PropertiesService.getScriptProperties();
  var correctPin = props.getProperty('DASHBOARD_PIN') || 'admin123';
  return pin === correctPin;
}

/**
 * Mengambil daftar sesi ujian dari Firestore
 */
function getExamSessions(pin) {
  if (!_checkAdminPin(pin)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };
  
  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/exam_sessions?pageSize=300';
  
  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });
    
    if (resp.getResponseCode() === 200) {
      var data = JSON.parse(resp.getContentText());
      var documents = data.documents || [];
      return documents.map(function(doc) {
        var parts = doc.name.split('/');
        var examId = parts[parts.length - 1];
        
        return {
          id: examId,
          title: doc.fields && doc.fields.title && doc.fields.title.stringValue ? doc.fields.title.stringValue : 'Tanpa Judul',
          createdAt: doc.createTime
        };
      }).sort(function(a, b) {
        return new Date(b.createdAt) - new Date(a.createdAt);
      });
    } else {
      return { error: 'Gagal memuat data: ' + resp.getContentText() };
    }
  } catch (e) {
    return { error: 'Server error: ' + e.message };
  }
}

/**
 * Menghapus satu sesi ujian beserta subkoleksinya (Recursive Delete)
 */
function deleteExamSession(examId, pin) {
  if (!_checkAdminPin(pin)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  var accessToken = _getAccessToken();
  var baseUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/exam_sessions/' + examId;
  
  try {
    // 1. HAPUS DOKUMEN ROOT TERLEBIH DAHULU!
    // Ini memastikan bahwa meskipun nanti gagal saat menghapus subkoleksi karena limit kuota harian (RESOURCE_EXHAUSTED),
    // ujian ini sudah hilang dari UI dan aplikasi Flutter.
    var delResp = UrlFetchApp.fetch(baseUrl, {
      method: 'delete',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });
    
    // Bersihkan script properties yang terkait
    props.deleteProperty('TEACHER_TOKENS_' + examId);
    props.deleteProperty('TEACHER_TOKENS_' + examId + '_TS');

    if (delResp.getResponseCode() !== 200) {
       var errData = JSON.parse(delResp.getContentText());
       var isQuotaError = errData.error && errData.error.status === 'RESOURCE_EXHAUSTED';
       if (isQuotaError) {
         return { error: 'Kuota Firebase Gratis Anda habis untuk hari ini (Limit 20.000 hapus/hari). Silakan coba lagi besok.' };
       }
       return { error: 'Gagal hapus dokumen root: ' + delResp.getContentText() };
    }
    
    // 2. Ambil semua siswa & coba hapus subkoleksinya (Best Effort)
    try {
      var studentsResp = UrlFetchApp.fetch(baseUrl + '/students?pageSize=300', {
        method: 'get',
        headers: { Authorization: 'Bearer ' + accessToken },
        muteHttpExceptions: true
      });
      
      if (studentsResp.getResponseCode() === 200) {
        var studentsData = JSON.parse(studentsResp.getContentText());
        var students = studentsData.documents || [];
        
        students.forEach(function(student) {
          var studentPath = student.name;
          
          // Hapus Logs siswa tersebut
          var logsUrl = 'https://firestore.googleapis.com/v1/' + studentPath + '/logs?pageSize=300';
          var logsResp = UrlFetchApp.fetch(logsUrl, {
            method: 'get',
            headers: { Authorization: 'Bearer ' + accessToken },
            muteHttpExceptions: true
          });
          if (logsResp.getResponseCode() === 200) {
            var logsData = JSON.parse(logsResp.getContentText());
            var logs = logsData.documents || [];
            logs.forEach(function(log) {
              UrlFetchApp.fetch('https://firestore.googleapis.com/v1/' + log.name, {
                method: 'delete',
                headers: { Authorization: 'Bearer ' + accessToken },
                muteHttpExceptions: true
              });
            });
          }
          
          // Hapus dokumen siswa
          UrlFetchApp.fetch('https://firestore.googleapis.com/v1/' + studentPath, {
            method: 'delete',
            headers: { Authorization: 'Bearer ' + accessToken },
            muteHttpExceptions: true
          });
        });
      }
    } catch (ignored) {
      // Abaikan jika gagal menghapus subkoleksi (biasanya karena limit kuota), 
      // karena dokumen root sudah berhasil dihapus.
      Logger.log('Gagal menghapus subkoleksi (kemungkinan limit kuota), tapi root berhasil dihapus.');
    }
    
    return { success: true };
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Menghapus beberapa sesi ujian sekaligus (Bulk Delete)
 */
function deleteMultipleExams(examIds, pin) {
  if (!_checkAdminPin(pin)) return { error: 'unauthorized' };
  if (!Array.isArray(examIds)) return { error: 'Invalid input' };

  var count = 0;
  for (var i = 0; i < examIds.length; i++) {
    var res = deleteExamSession(examIds[i], pin);
    if (res.success) count++;
  }
  return { success: true, count: count };
}

/**
 * Menghapus SELURUH sesi ujian (Mass Clean Up)
 */
function deleteAllExams(pin) {
  if (!_checkAdminPin(pin)) return { error: 'unauthorized' };

  var exams = getExamSessions(pin);
  if (exams.error) return exams;
  
  var count = 0;
  for (var i = 0; i < exams.length; i++) {
    // FIX BUG: Terlupa mengirim parameter pin saat loop hapus
    var res = deleteExamSession(exams[i].id, pin);
    if (res.success) count++;
  }
  return { success: true, count: count };
}
