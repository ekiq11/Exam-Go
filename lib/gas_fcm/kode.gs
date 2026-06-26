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
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
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
 * Validasi Username & Password via Spreadsheet
 */
function _checkUserLogin(username, password) {
  var props = PropertiesService.getScriptProperties();
  var ssId = props.getProperty('SPREADSHEET_ID');
  var ss;
  
  try {
    if (ssId) {
      ss = SpreadsheetApp.openById(ssId);
    } else {
      ss = SpreadsheetApp.getActiveSpreadsheet();
    }
  } catch(e) {
    // Fallback jika tidak ada akses ke spreadsheet
    return (username === 'admin' && password === 'admin123');
  }
  
  if (!ss) {
    return (username === 'admin' && password === 'admin123');
  }
  
  var sheet = ss.getSheetByName('user');
  if (!sheet) {
    // Buat tabel otomatis jika belum ada
    sheet = ss.insertSheet('user');
  }
  
  var data = sheet.getDataRange().getValues();
  
  // Jika sheet kosong melompong (hanya ada 1 baris kosong atau tidak ada data sama sekali)
  if (data.length === 0 || (data.length === 1 && String(data[0][0]).trim() === "")) {
    sheet.clear();
    sheet.appendRow(['Username', 'Password']);
    sheet.appendRow(['admin', 'admin123']);
    sheet.getRange("A1:B1").setFontWeight("bold");
    sheet.setFrozenRows(1);
    sheet.autoResizeColumns(1, 2);
    
    // Ambil ulang data setelah diisi
    data = sheet.getDataRange().getValues();
  }
  for (var i = 1; i < data.length; i++) {
    if (String(data[i][0]).trim() === String(username).trim() && String(data[i][1]).trim() === String(password).trim()) {
      return true;
    }
  }
  
  return false;
}

/**
 * Mengambil daftar sesi ujian dari Firestore
 */
function getExamSessions(username, password, pageToken) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };
  
  // Ambil semua dokumen (max 1000) untuk diurutkan secara global di memori
  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/exam_sessions?pageSize=1000';
  
  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { 
        Authorization: 'Bearer ' + accessToken,
        'Cache-Control': 'no-cache'
      },
      muteHttpExceptions: true
    });
    
    if (resp.getResponseCode() === 200) {
      var data = JSON.parse(resp.getContentText());
      var allDocuments = data.documents || [];
      
      // 1. Sort global berdasarkan createTime (terbaru di atas)
      allDocuments.sort(function(a, b) {
        return new Date(b.createTime) - new Date(a.createTime);
      });
      
      // 2. Terapkan Paginasi Manual
      var page = parseInt(pageToken) || 1;
      var pageSize = 25;
      var startIndex = (page - 1) * pageSize;
      var pageDocuments = allDocuments.slice(startIndex, startIndex + pageSize);
      
      // 3. Hanya ambil jumlah peserta untuk 25 dokumen di halaman ini (sangat cepat)
      var countRequests = pageDocuments.map(function(doc) {
        var parts = doc.name.split('/');
        var examId = parts[parts.length - 1];
        return {
          url: 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/exam_sessions/' + encodeURIComponent(examId) + '/students?pageSize=1000',
          method: 'get',
          headers: { Authorization: 'Bearer ' + accessToken },
          muteHttpExceptions: true
        };
      });
      
      var counts = [];
      if (countRequests.length > 0) {
        var batchSize = 10;
        for (var i = 0; i < countRequests.length; i += batchSize) {
          var batch = countRequests.slice(i, i + batchSize);
          try {
            var responses = UrlFetchApp.fetchAll(batch);
            responses.forEach(function(r) {
              if (r.getResponseCode() === 200) {
                var sData = JSON.parse(r.getContentText());
                counts.push(sData.documents ? sData.documents.length : 0);
              } else {
                counts.push(0);
              }
            });
          } catch(e) {
            for (var j = 0; j < batch.length; j++) {
              try {
                var r = UrlFetchApp.fetch(batch[j].url, batch[j]);
                if (r.getResponseCode() === 200) {
                  var sData = JSON.parse(r.getContentText());
                  counts.push(sData.documents ? sData.documents.length : 0);
                } else {
                  counts.push(0);
                }
              } catch(err) {
                counts.push(0);
              }
            }
          }
        }
      }
      
      var mappedDocs = pageDocuments.map(function(doc, index) {
        var parts = doc.name.split('/');
        var examId = parts[parts.length - 1];
        
        return {
          id: examId,
          title: doc.fields && doc.fields.title && doc.fields.title.stringValue ? doc.fields.title.stringValue : 'Tanpa Judul',
          createdAt: doc.createTime,
          studentCount: counts[index] || 0
        };
      });
      
      var nextPage = (startIndex + pageSize < allDocuments.length) ? String(page + 1) : null;
      
      return {
        documents: mappedDocs,
        nextPageToken: nextPage
      };
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
function deleteExamSession(examId, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

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
function deleteMultipleExams(examIds, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!Array.isArray(examIds)) return { error: 'Invalid input' };

  var count = 0;
  for (var i = 0; i < examIds.length; i++) {
    var res = deleteExamSession(examIds[i], username, password);
    if (res.success) count++;
  }
  return { success: true, count: count };
}

/**
 * Menghapus SELURUH sesi ujian (Mass Clean Up)
 */
function deleteAllExams(username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var exams = getExamSessions(username, password);
  if (exams.error) return exams;
  
  var count = 0;
  for (var i = 0; i < exams.length; i++) {
    // FIX BUG: Terlupa mengirim parameter auth saat loop hapus
    var res = deleteExamSession(exams[i].id, username, password);
    if (res.success) count++;
  }
  return { success: true, count: count };
}

// ══════════════════════════════════════════════════════════════════
// AUTO PING (Keep Alive) - Solusi tanpa update APK
// ══════════════════════════════════════════════════════════════════

/**
 * Fungsi ini dijalankan otomatis oleh GAS Time-driven Trigger (misal setiap 5 menit).
 * Akan mencari semua siswa berstatus 'ACTIVE' dan memperbarui 'last_ping' mereka
 * agar tidak dianggap OFFLINE oleh layar monitoring Guru.
 * Dioptimasi dengan UrlFetchApp.fetchAll agar tidak Exceeded maximum execution time.
 */
function keepAliveActiveStudents() {
  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return;
  
  try {
    var accessToken = _getAccessToken();
    var baseUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/exam_sessions';
    
    // 1. Ambil semua sesi ujian aktif
    var examResp = UrlFetchApp.fetch(baseUrl + '?pageSize=300', {
      method: 'get',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });
    
    if (examResp.getResponseCode() !== 200) return;
    var examData = JSON.parse(examResp.getContentText());
    var exams = examData.documents || [];
    if (exams.length === 0) return;
    
    var nowTimestamp = new Date().toISOString();
    
    // 2. Siapkan request untuk ambil siswa per exam secara paralel
    var studentRequests = exams.map(function(exam) {
      return {
        url: 'https://firestore.googleapis.com/v1/' + exam.name + '/students?pageSize=300',
        method: 'get',
        headers: { Authorization: 'Bearer ' + accessToken },
        muteHttpExceptions: true
      };
    });
    
    // Fetch semua siswa dari semua exam secara paralel
    var studentResponses = UrlFetchApp.fetchAll(studentRequests);
    var patchRequests = [];
    
    // 3. Kumpulkan siswa dengan status 'ACTIVE'
    for (var i = 0; i < studentResponses.length; i++) {
      if (studentResponses[i].getResponseCode() === 200) {
        var studentData = JSON.parse(studentResponses[i].getContentText());
        var students = studentData.documents || [];
        
        students.forEach(function(student) {
          var fields = student.fields || {};
          var status = fields.status && fields.status.stringValue ? fields.status.stringValue : 'OFFLINE';
          
          if (status === 'ACTIVE') {
            patchRequests.push({
              url: 'https://firestore.googleapis.com/v1/' + student.name + '?updateMask.fieldPaths=last_ping',
              method: 'patch',
              headers: { 
                Authorization: 'Bearer ' + accessToken,
                'Content-Type': 'application/json' 
              },
              payload: JSON.stringify({
                fields: {
                  last_ping: { timestampValue: nowTimestamp }
                }
              }),
              muteHttpExceptions: true
            });
          }
        });
      }
    }
    
    // 4. Lakukan PATCH secara paralel (batch max 500 requests per call)
    var batchSize = 500;
    for (var j = 0; j < patchRequests.length; j += batchSize) {
      var batch = patchRequests.slice(j, j + batchSize);
      UrlFetchApp.fetchAll(batch);
    }
    
    Logger.log('✅ Berhasil menjalankan Keep Alive untuk ' + patchRequests.length + ' siswa aktif pada: ' + nowTimestamp);
  } catch (e) {
    Logger.log('❌ Error pada keepAliveActiveStudents: ' + e.message);
  }
}

// ══════════════════════════════════════════════════════════════════
// ADMIN DASHBOARD STUDENT MANAGEMENT FUNCTIONS
// ══════════════════════════════════════════════════════════════════

/**
 * Mengambil daftar siswa untuk satu sesi ujian
 */
function getStudentsList(examId, username, password, pageToken) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  
  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  var accessToken = _getAccessToken();
  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/exam_sessions/' + examId + '/students?pageSize=1000';
  
  try {
    var resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { 
        Authorization: 'Bearer ' + accessToken,
        'Cache-Control': 'no-cache'
      },
      muteHttpExceptions: true
    });
    
    if (resp.getResponseCode() === 200) {
      var data = JSON.parse(resp.getContentText());
      var allDocuments = data.documents || [];
      
      var mappedDocs = allDocuments.map(function(doc) {
        var parts = doc.name.split('/');
        var studentId = parts[parts.length - 1];
        var fields = doc.fields || {};
        var vCount = fields.violations && fields.violations.integerValue ? parseInt(fields.violations.integerValue) : 0;
        return {
          id: studentId,
          name: fields.name && fields.name.stringValue ? fields.name.stringValue : '-',
          nis: fields.nis && fields.nis.stringValue ? fields.nis.stringValue : '-',
          status: fields.status && fields.status.stringValue ? fields.status.stringValue : 'OFFLINE',
          last_ping: fields.last_ping && fields.last_ping.timestampValue ? fields.last_ping.timestampValue : null,
          violationCount: vCount
        };
      });
      
      // Sort manual JS agar pasti urut abjad
      mappedDocs.sort(function(a, b) {
        return a.name.localeCompare(b.name);
      });
      
      // Terapkan Paginasi Manual
      var page = parseInt(pageToken) || 1;
      var pageSize = 50;
      var startIndex = (page - 1) * pageSize;
      var pageDocuments = mappedDocs.slice(startIndex, startIndex + pageSize);
      
      var nextPage = (startIndex + pageSize < mappedDocs.length) ? String(page + 1) : null;

      return {
        documents: pageDocuments,
        nextPageToken: nextPage
      };
    } else {
      return { error: 'Gagal memuat data siswa: ' + resp.getContentText() };
    }
  } catch (e) {
    return { error: 'Server error: ' + e.message };
  }
}

/**
 * Mengubah status siswa (contoh: BLOCKED / ACTIVE)
 */
function updateStudentStatus(examId, studentId, status, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  var accessToken = _getAccessToken();
  var studentPath = 'projects/' + projectId + '/databases/(default)/documents/exam_sessions/' + examId + '/students/' + studentId;
  var url = 'https://firestore.googleapis.com/v1/' + studentPath + '?updateMask.fieldPaths=status';

  try {
    var payload = {
      fields: {
        status: { stringValue: status }
      }
    };
    
    var resp = UrlFetchApp.fetch(url, {
      method: 'patch',
      headers: { 
        Authorization: 'Bearer ' + accessToken,
        'Content-Type': 'application/json'
      },
      payload: JSON.stringify(payload),
      muteHttpExceptions: true
    });
    
    if (resp.getResponseCode() === 200) {
      return { success: true };
    } else {
      return { error: 'Gagal update status: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Update data siswa (Name, NIS)
 */
function updateStudentData(examId, studentId, newName, newNis, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  var accessToken = _getAccessToken();
  var studentPath = 'projects/' + projectId + '/databases/(default)/documents/exam_sessions/' + examId + '/students/' + studentId;
  var url = 'https://firestore.googleapis.com/v1/' + studentPath + '?updateMask.fieldPaths=name&updateMask.fieldPaths=nis';

  try {
    var payload = {
      fields: {
        name: { stringValue: newName },
        nis: { stringValue: newNis }
      }
    };
    
    var resp = UrlFetchApp.fetch(url, {
      method: 'patch',
      headers: { 
        Authorization: 'Bearer ' + accessToken,
        'Content-Type': 'application/json'
      },
      payload: JSON.stringify(payload),
      muteHttpExceptions: true
    });
    
    if (resp.getResponseCode() === 200) {
      return { success: true };
    } else {
      return { error: 'Gagal update data: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Menghapus satu siswa beserta lognya
 */
function deleteStudentSingle(examId, studentId, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  var accessToken = _getAccessToken();
  var studentPath = 'projects/' + projectId + '/databases/(default)/documents/exam_sessions/' + examId + '/students/' + studentId;
  var url = 'https://firestore.googleapis.com/v1/' + studentPath;

  try {
    // Coba hapus log
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
    var resp = UrlFetchApp.fetch(url, {
      method: 'delete',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200) {
      return { success: true };
    } else {
      return { error: 'Gagal hapus siswa: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}
