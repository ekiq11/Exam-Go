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

  // ── Upload File/Gambar ke Google Drive ────────────────────────────
  if (action === 'uploadFileToDrive') {
    if (!data.base64 || !data.filename) {
      return _json({ error: 'missing_file_data' });
    }
    try {
      var contentType = data.mimeType || 'image/png';
      var decodedBytes = Utilities.base64Decode(data.base64);
      var blob = Utilities.newBlob(decodedBytes, contentType, data.filename);
      
      // Simpan di folder target Google Drive (default: 1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ)
      var targetFolderId = data.folderId || '1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ';
      var targetFolder;
      try {
        targetFolder = DriveApp.getFolderById(targetFolderId);
      } catch (fErr) {
        var folderName = 'ExamGO_Uploads';
        var folders = DriveApp.getFoldersByName(folderName);
        targetFolder = folders.hasNext() ? folders.next() : DriveApp.createFolder(folderName);
      }
      targetFolder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      
      var file = targetFolder.createFile(blob);
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      var fileId = file.getId();
      var directUrl = 'https://drive.google.com/uc?export=view&id=' + fileId;
      
      return _json({
        success: true,
        fileId: fileId,
        url: directUrl,
        filename: data.filename
      });
    } catch (e) {
      return _json({ error: 'upload_failed', message: e.message });
    }
  }

  // ── Verifikasi License Token (Server-side fallback via Service Account) ──
  if (action === 'verifyLicense') {
    var rawToken = (data.token || '').trim().toUpperCase();
    var deviceId = (data.deviceId || '').trim();
    var userType = (data.userType || '').trim();
    if (!rawToken) return _json({ isSuccess: false, message: 'Kode token kosong' });

    var projectId = props.getProperty('PROJECT_ID');
    if (!projectId) return _json({ isSuccess: false, message: 'PROJECT_ID belum diset.' });

    var tokenDocUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/license_tokens/' + encodeURIComponent(rawToken);
    try {
      var accessToken = _getAccessToken();
      var resp = UrlFetchApp.fetch(tokenDocUrl, {
        method: 'get',
        headers: { Authorization: 'Bearer ' + accessToken },
        muteHttpExceptions: true
      });

      if (resp.getResponseCode() === 404) {
        return _json({ isSuccess: false, message: 'Kode token tidak ditemukan atau salah ketik.' });
      }
      if (resp.getResponseCode() !== 200) {
        return _json({ isSuccess: false, message: 'Gagal verifikasi lisensi (HTTP ' + resp.getResponseCode() + ')' });
      }

      var doc = JSON.parse(resp.getContentText());
      var f = doc.fields || {};
      var isUsed = f.is_used && f.is_used.booleanValue;
      var assignedDevice = (f.device_id && f.device_id.stringValue) || '';
      var tokenType = (f.type && f.type.stringValue) || 'STUDENT_LIFETIME';
      var targetExamId = (f.target_exam_id && f.target_exam_id.stringValue) || '';

      if (userType && userType !== tokenType && tokenType !== 'EVENT') {
        return _json({
          isSuccess: false,
          message: 'Token ini khusus untuk ' + (tokenType === 'TEACHER_PREMIUM' ? 'Guru Premium' : (tokenType === 'EVENT' ? 'Peserta Event' : 'Siswa Lifetime'))
        });
      }

      var isGroup = f.is_group_voucher && f.is_group_voucher.booleanValue;
      if (isGroup) {
        var maxAct = (f.max_activations && f.max_activations.integerValue) ? parseInt(f.max_activations.integerValue) : 1000;
        var curAct = (f.current_activations && f.current_activations.integerValue) ? parseInt(f.current_activations.integerValue) : 0;
        var school = (f.school && f.school.stringValue) || 'Sekolah Mitra';

        if (curAct >= maxAct) {
          return _json({
            isSuccess: false,
            message: 'Kuota aktivasi lisensi untuk ' + school + ' (' + maxAct + ' perangkat) sudah penuh.'
          });
        }

        // Increment current_activations
        var patchUrl = tokenDocUrl + '?updateMask.fieldPaths=current_activations&updateMask.fieldPaths=last_activated_at';
        UrlFetchApp.fetch(patchUrl, {
          method: 'patch',
          contentType: 'application/json',
          headers: { Authorization: 'Bearer ' + accessToken },
          payload: JSON.stringify({
            fields: {
              current_activations: { integerValue: (curAct + 1) },
              last_activated_at: { timestampValue: new Date().toISOString() }
            }
          }),
          muteHttpExceptions: true
        });

        return _json({
          isSuccess: true,
          message: 'Selamat! Akun ' + (tokenType === 'TEACHER_PREMIUM' ? 'Guru Premium' : 'Siswa Lifetime') + ' ' + school + ' aktif!',
          tokenType: tokenType,
          targetExamId: targetExamId
        });
      }

      if (isUsed && assignedDevice && assignedDevice !== deviceId) {
        return _json({
          isSuccess: false,
          message: 'Kode lisensi sudah digunakan pada perangkat lain.'
        });
      }

      var patchUrl = tokenDocUrl + '?updateMask.fieldPaths=is_used&updateMask.fieldPaths=device_id&updateMask.fieldPaths=activated_at';
      UrlFetchApp.fetch(patchUrl, {
        method: 'patch',
        contentType: 'application/json',
        headers: { Authorization: 'Bearer ' + accessToken },
        payload: JSON.stringify({
          fields: {
            is_used: { booleanValue: true },
            device_id: { stringValue: deviceId },
            activated_at: { timestampValue: new Date().toISOString() }
          }
        }),
        muteHttpExceptions: true
      });

      return _json({
        isSuccess: true,
        message: 'Aktivasi lisensi berhasil!',
        tokenType: tokenType,
        targetExamId: targetExamId
      });
    } catch(err) {
      return _json({ isSuccess: false, message: 'Error verifikasi: ' + err.message });
    }
  }

  // ── Ambil Jadwal Paket Tryout untuk Siswa Premium ─────────────
  if (action === 'getJadwalTryout') {
    var projectId = props.getProperty('PROJECT_ID');
    if (!projectId) return _json({ status: 'error', message: 'PROJECT_ID belum diset.' });

    var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/paket_tryout?pageSize=100';
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
        var dataResp = JSON.parse(resp.getContentText());
        var docs = dataResp.documents || [];
        var list = [];
        docs.forEach(function(d) {
          var f = d.fields || {};
          var status = (f.status && f.status.stringValue) || 'aktif';
          if (status === 'aktif') {
            list.push({
              paket_id: (f.paket_id && f.paket_id.stringValue) || d.name.split('/').pop(),
              nama_paket: (f.nama_paket && f.nama_paket.stringValue) || 'Tryout Akbar',
              deskripsi: (f.deskripsi && f.deskripsi.stringValue) || '',
              jenis_test: (f.jenis_test && f.jenis_test.stringValue) || 'SNBT',
              jenis_waktu: (f.jenis_waktu && f.jenis_waktu.stringValue) || 'total',
              tanggal: (f.tanggal && f.tanggal.stringValue) || '',
              jam_mulai: (f.jam_mulai && f.jam_mulai.stringValue) || '08:00',
              jam_selesai: (f.jam_selesai && f.jam_selesai.stringValue) || '23:59',
              durasi_menit: parseInt((f.durasi_menit && f.durasi_menit.integerValue) || '120', 10),
              total_soal: parseInt((f.total_soal && f.total_soal.integerValue) || '50', 10),
              status: status,
              target_exam_id: (f.target_exam_id && f.target_exam_id.stringValue) || '',
              pass_percentage: parseInt((f.pass_percentage && f.pass_percentage.integerValue) || '65', 10),
              is_premium_only: f.is_premium_only ? (f.is_premium_only.booleanValue !== false) : true
            });
          }
        });
        return _json({ status: 'success', data: list });
      } else {
        return _json({ status: 'error', message: 'HTTP ' + resp.getResponseCode() });
      }
    } catch(err) {
      return _json({ status: 'error', message: err.message });
    }
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
  if (e && e.parameter && (e.parameter.action === 'check_drive' || e.parameter.api === 'check_drive')) {
    var check = checkDriveApiStatus();
    return ContentService.createTextOutput(JSON.stringify(check)).setMimeType(ContentService.MimeType.JSON);
  }

  if (e && e.parameter && (e.parameter.action === 'cleanup_sessions' || e.parameter.api === 'cleanup_sessions')) {
    var cleanRes = cleanupAbandonedExamSessions();
    return ContentService.createTextOutput(JSON.stringify(cleanRes)).setMimeType(ContentService.MimeType.JSON);
  }

  if (e && e.parameter && (e.parameter.action === 'remove_triggers' || e.parameter.api === 'remove_triggers')) {
    var delTrig = removeAllTimeDrivenTriggers();
    return ContentService.createTextOutput(JSON.stringify(delTrig)).setMimeType(ContentService.MimeType.JSON);
  }

  // Untuk kompatibilitas jika ada yang ping GET, kita bisa kembalikan JSON,
  // tapi secara default kita kembalikan halaman Web App Dashboard.
  if (e && e.parameter && e.parameter.api === 'true') {
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
            channel_id:     'exam_violations',
            notification_priority: 'PRIORITY_HIGH',
            default_sound:  true,
            default_vibrate_timings: true,
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
 * Menghapus semua trigger time-driven di proyek ini
 * Menghilangkan beban eksekusi latar belakang 24/7 dan menghemat kuota 100%!
 */
function removeAllTimeDrivenTriggers() {
  try {
    var triggers = ScriptApp.getProjectTriggers();
    var deletedNames = [];
    triggers.forEach(function(trigger) {
      var funcName = trigger.getHandlerFunction();
      deletedNames.push(funcName);
      ScriptApp.deleteTrigger(trigger);
    });
    Logger.log('✅ Berhasil menghapus ' + deletedNames.length + ' trigger: ' + deletedNames.join(', '));
    return {
      success: true,
      deletedCount: deletedNames.length,
      triggers: deletedNames,
      message: 'Semua trigger time-driven berhasil dihapus permanen. Kuota kini 100% hemat!'
    };
  } catch (err) {
    Logger.log('Gagal menghapus trigger: ' + err.toString());
    return { success: false, error: err.message };
  }
}

/**
 * DEPRECATED & DILUMPUHKAN:
 * Keep-alive sudah 100% ditangani oleh aplikasi siswa di HP masing-masing (Client-Driven Heartbeat).
 * Fungsi ini dikosongkan agar jika pemicu waktu Google (time-driven trigger) lama masih menyala,
 * fungsi ini selesai dalam 0 ms tanpa membaca storage / kuota, dan TIDAK AKAN PERNAH menghasilkan error lagi.
 */
function keepAliveActiveStudents() {
  return;
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

/**
 * Menghapus banyak siswa sekaligus (Bulk Delete)
 */
function deleteMultipleStudents(examId, studentIds, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!Array.isArray(studentIds)) return { error: 'Invalid input studentIds' };

  var count = 0;
  for (var i = 0; i < studentIds.length; i++) {
    var res = deleteStudentSingle(examId, studentIds[i], username, password);
    if (res && res.success) count++;
  }
  return { success: true, count: count };
}

// ══════════════════════════════════════════════════════════════════
// LISENSI & TOKEN LYNK.ID (Admin Web Dashboard)
// ══════════════════════════════════════════════════════════════════

/**
 * Generate Token Lynk.id secara batch dan simpan ke Firestore
 * @param {string} username
 * @param {string} password
 * @param {string} type 'TEACHER_PREMIUM' atau 'STUDENT_LIFETIME'
 * @param {number} count Jumlah token (1 - 100)
 */
function generateLicenseTokens(username, password, type, count, targetExamId, school) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set di Script Properties.' };

  var validCount = parseInt(count) || 10;
  if (validCount > 100) validCount = 100;
  if (validCount < 1) validCount = 1;

  var prefix = (type === 'TEACHER_PREMIUM') ? 'GURU' : (type === 'EVENT' ? 'EVENT' : 'SISWA');
  var cleanSchool = school ? String(school).trim() : 'UMUM';
  var chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  var generatedTokens = [];
  var writes = [];
  var cleanTargetId = targetExamId ? String(targetExamId).trim().toUpperCase() : '';

  for (var i = 0; i < validCount; i++) {
    var seg1 = '';
    var seg2 = '';
    for (var j = 0; j < 4; j++) {
      seg1 += chars.charAt(Math.floor(Math.random() * chars.length));
      seg2 += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    var code = prefix + '-' + seg1 + '-' + seg2;
    generatedTokens.push(code);

    var docPath = 'projects/' + projectId + '/databases/(default)/documents/license_tokens/' + code;
    var fieldsObj = {
      token: { stringValue: code },
      type: { stringValue: type },
      school: { stringValue: cleanSchool },
      is_used: { booleanValue: false },
      device_id: { nullValue: null },
      used_by_email: { nullValue: null },
      created_at: { timestampValue: new Date().toISOString() }
    };

    if (cleanTargetId) {
      fieldsObj.target_exam_id = { stringValue: cleanTargetId };
    }

    writes.push({
      update: {
        name: docPath,
        fields: fieldsObj
      }
    });
  }

  try {
    var accessToken = _getAccessToken();
    var commitUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents:commit';
    var resp = UrlFetchApp.fetch(commitUrl, {
      method: 'post',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + accessToken },
      payload: JSON.stringify({ writes: writes }),
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200) {
      _logTokensToSheet(generatedTokens, type, cleanSchool);
      return {
        success: true,
        count: generatedTokens.length,
        tokens: generatedTokens,
        type: type,
        school: cleanSchool
      };
    } else {
      return { error: 'Gagal commit ke Firestore: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Buat atau update Master Voucher Sekolah (1 kode berkuota untuk ribuan siswa)
 * @param {string} username
 * @param {string} password
 * @param {string} tokenCode Kode voucher (misal: MAN1MATARAM)
 * @param {string} school Nama sekolah (misal: MAN 1 Mataram)
 * @param {string} type 'STUDENT_LIFETIME' atau 'TEACHER_PREMIUM'
 * @param {number} maxQuota Kuota aktivasi perangkat (misal: 1200)
 */
function createMasterSchoolVoucher(username, password, tokenCode, school, type, maxQuota) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set di Script Properties.' };

  var cleanCode = String(tokenCode || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (!cleanCode) return { error: 'Kode voucher tidak boleh kosong.' };

  var cleanSchool = String(school || 'Sekolah Mitra').trim();
  var quota = parseInt(maxQuota) || 1000;
  var tokenType = (type === 'TEACHER_PREMIUM') ? 'TEACHER_PREMIUM' : (type === 'EVENT' ? 'EVENT' : 'STUDENT_LIFETIME');

  var docUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/license_tokens/' + encodeURIComponent(cleanCode);

  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(docUrl, {
      method: 'patch',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + accessToken },
      payload: JSON.stringify({
        fields: {
          token: { stringValue: cleanCode },
          type: { stringValue: tokenType },
          school: { stringValue: cleanSchool },
          is_group_voucher: { booleanValue: true },
          max_activations: { integerValue: quota },
          current_activations: { integerValue: 0 },
          created_at: { timestampValue: new Date().toISOString() }
        }
      }),
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200) {
      _logTokensToSheet([cleanCode], tokenType, cleanSchool + ' [Master Voucher Kuota ' + quota + ']');
      return {
        success: true,
        token: cleanCode,
        school: cleanSchool,
        type: tokenType,
        maxQuota: quota
      };
    } else {
      return { error: 'Gagal membuat Master Voucher: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Mengambil daftar token lisensi dari Firestore untuk dashboard admin
 */
function getLicenseTokens(username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/license_tokens?pageSize=500';

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
      var docs = data.documents || [];
      var tokens = [];
      var used = 0;
      var available = 0;

      docs.forEach(function(doc) {
        var f = doc.fields || {};
        var tokenCode = f.token ? f.token.stringValue : doc.name.split('/').pop();
        var isUsed = f.is_used ? (f.is_used.booleanValue === true) : false;
        var tokenType = f.type ? f.type.stringValue : '';
        var deviceId = (f.device_id && f.device_id.stringValue) ? f.device_id.stringValue : '-';
        var email = (f.used_by_email && f.used_by_email.stringValue) ? f.used_by_email.stringValue : '-';
        var targetExam = (f.target_exam_id && f.target_exam_id.stringValue) ? f.target_exam_id.stringValue : '-';
        var school = (f.school && f.school.stringValue) ? f.school.stringValue : 'UMUM';
        var isGroup = f.is_group_voucher ? (f.is_group_voucher.booleanValue === true) : false;
        var maxAct = (f.max_activations && f.max_activations.integerValue) ? parseInt(f.max_activations.integerValue) : (isGroup ? 1000 : 1);
        var curAct = (f.current_activations && f.current_activations.integerValue) ? parseInt(f.current_activations.integerValue) : (isUsed ? 1 : 0);
        var createdAt = (f.created_at && f.created_at.timestampValue) ? f.created_at.timestampValue : doc.createTime;
        var activatedAt = (f.activated_at && f.activated_at.timestampValue) ? f.activated_at.timestampValue : '-';

        if (isUsed || (isGroup && curAct >= maxAct)) {
          used++;
        } else {
          available++;
        }

        tokens.push({
          token: tokenCode,
          type: tokenType,
          school: school,
          isGroup: isGroup,
          maxActivations: maxAct,
          currentActivations: curAct,
          targetExam: targetExam,
          isUsed: isUsed,
          deviceId: deviceId,
          email: email,
          createdAt: createdAt,
          activatedAt: activatedAt
        });
      });

      tokens.sort(function(a, b) {
        return new Date(b.createdAt) - new Date(a.createdAt);
      });

      return {
        success: true,
        tokens: tokens,
        total: docs.length,
        used: used,
        available: available
      };
    } else {
      return { error: 'Gagal mengambil token dari Firestore: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Mengambil daftar sekolah mitra dari Firestore collection 'partner_schools'
 * Fallback ke daftar sekolah default jika belum ada di Firestore.
 */
function getPartnerSchools(username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var defaultSchools = [
    { name: 'MAN 1 Mataram', code: 'MAN1MATARAM', quota: 1200 },
    { name: 'MAN 2 Mataram', code: 'MAN2MATARAM', quota: 1500 },
    { name: 'MTsN 1 Mataram', code: 'MTS1MATARAM', quota: 900 }
  ];

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { success: true, schools: defaultSchools };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/partner_schools?pageSize=100';

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
      var docs = data.documents || [];
      if (docs.length === 0) {
        return { success: true, schools: defaultSchools };
      }

      var schools = [];
      docs.forEach(function(d) {
        var f = d.fields || {};
        var name = (f.name && f.name.stringValue) || '';
        var code = (f.code && f.code.stringValue) || '';
        var quota = (f.quota && f.quota.integerValue) ? parseInt(f.quota.integerValue) : 1000;
        if (name) {
          schools.push({ name: name, code: code, quota: quota });
        }
      });

      // Pastikan sekolah default tetap ada
      defaultSchools.forEach(function(def) {
        var exists = schools.some(function(s) { return s.name.toLowerCase() === def.name.toLowerCase(); });
        if (!exists) schools.unshift(def);
      });

      return { success: true, schools: schools };
    } else {
      return { success: true, schools: defaultSchools };
    }
  } catch (e) {
    return { success: true, schools: defaultSchools, error: e.message };
  }
}

/**
 * Menyimpan / menambahkan sekolah mitra baru ke Firestore 'partner_schools'
 */
function addPartnerSchool(username, password, name, code, defaultQuota, oldCode) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var cleanName = String(name || '').trim();
  var cleanCode = String(code || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
  var quota = parseInt(defaultQuota) || 1000;

  if (!cleanName) return { error: 'Nama sekolah mitra tidak boleh kosong.' };
  if (!cleanCode) cleanCode = cleanName.toUpperCase().replace(/[^A-Z0-9]/g, '').substring(0, 16);

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var accessToken = _getAccessToken();

  // Jika nama/kode diubah dari kode lama, hapus dokumen lama agar tidak duplikat
  if (oldCode) {
    var cleanOldCode = String(oldCode || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (cleanOldCode && cleanOldCode !== cleanCode) {
      try {
        var oldUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/partner_schools/' + encodeURIComponent(cleanOldCode);
        UrlFetchApp.fetch(oldUrl, {
          method: 'delete',
          headers: { Authorization: 'Bearer ' + accessToken },
          muteHttpExceptions: true
        });
      } catch (_) {}
    }
  }

  var docUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/partner_schools/' + encodeURIComponent(cleanCode);

  try {
    var resp = UrlFetchApp.fetch(docUrl, {
      method: 'patch',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + accessToken },
      payload: JSON.stringify({
        fields: {
          name: { stringValue: cleanName },
          code: { stringValue: cleanCode },
          quota: { integerValue: quota },
          updated_at: { timestampValue: new Date().toISOString() }
        }
      }),
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200) {
      return {
        success: true,
        school: { name: cleanName, code: cleanCode, quota: quota }
      };
    } else {
      return { error: 'Gagal menyimpan sekolah mitra: ' + resp.getContentText() };
    }
  } catch (e) {
    return { error: e.message };
  }
}

/**
 * Menghapus sekolah mitra dari Firestore 'partner_schools'
 */
function deletePartnerSchool(username, password, code) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var cleanCode = String(code || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (!cleanCode) return { error: 'Kode sekolah tidak valid.' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var docUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/partner_schools/' + encodeURIComponent(cleanCode);

  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(docUrl, {
      method: 'delete',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });

    var c = resp.getResponseCode();
    if (c === 200 || c === 204) {
      return { success: true, message: 'Sekolah mitra ' + cleanCode + ' berhasil dihapus.' };
    } else {
      return { error: 'Gagal menghapus mitra: ' + resp.getContentText() };
    }
  } catch (e) {
    return { error: e.message };
  }
}

/**
 * Menghapus banyak token lisensi sekaligus (Bulk Delete)
 */
function deleteMultipleLicenseTokens(tokens, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!Array.isArray(tokens)) return { error: 'Invalid input tokens' };

  var count = 0;
  for (var i = 0; i < tokens.length; i++) {
    var res = deleteLicenseToken(tokens[i], username, password);
    if (res && res.success) count++;
  }
  return { success: true, count: count };
}

/**
 * Menghapus token lisensi dari Firestore secara permanen
 */
function deleteLicenseToken(token, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var cleanToken = String(token || '').trim();
  if (!cleanToken) return { error: 'Token tidak boleh kosong.' };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/license_tokens/' + encodeURIComponent(cleanToken);

  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'delete',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });

    var code = resp.getResponseCode();
    if (code === 200 || code === 204) {
      return { success: true, message: 'Token ' + cleanToken + ' berhasil dihapus dari Firestore.' };
    } else {
      return { error: 'Gagal menghapus token di Firestore (' + code + '): ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Memperbarui data token lisensi di Firestore
 * updates: { type, targetExam, resetStatus: boolean }
 */
function updateLicenseToken(token, updates, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var cleanToken = String(token || '').trim();
  if (!cleanToken) return { error: 'Token tidak boleh kosong.' };

  var fields = {};
  var updateMasks = [];

  if (updates && updates.type) {
    fields.type = { stringValue: updates.type };
    updateMasks.push('updateMask.fieldPaths=type');
  }

  if (updates && updates.targetExam !== undefined) {
    var cleanTarget = String(updates.targetExam || '').trim().toUpperCase();
    if (cleanTarget) {
      fields.target_exam_id = { stringValue: cleanTarget };
    } else {
      fields.target_exam_id = { nullValue: null };
    }
    updateMasks.push('updateMask.fieldPaths=target_exam_id');
  }

  if (updates && updates.resetStatus === true) {
    fields.is_used = { booleanValue: false };
    fields.device_id = { nullValue: null };
    fields.used_by_email = { nullValue: null };
    fields.activated_at = { nullValue: null };
    updateMasks.push('updateMask.fieldPaths=is_used');
    updateMasks.push('updateMask.fieldPaths=device_id');
    updateMasks.push('updateMask.fieldPaths=used_by_email');
    updateMasks.push('updateMask.fieldPaths=activated_at');
  }

  if (updateMasks.length === 0) {
    return { error: 'Tidak ada perubahan yang diberikan.' };
  }

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/license_tokens/' + encodeURIComponent(cleanToken) + '?' + updateMasks.join('&');

  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'patch',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + accessToken },
      payload: JSON.stringify({ fields: fields }),
      muteHttpExceptions: true
    });

    var code = resp.getResponseCode();
    if (code === 200) {
      return { success: true, message: 'Token ' + cleanToken + ' berhasil diperbarui di Firestore.' };
    } else {
      return { error: 'Gagal memperbarui token di Firestore (' + code + '): ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Backup token yang digenerate ke tab Sheet 'license_tokens'
 */
function _logTokensToSheet(tokens, type, school) {
  try {
    var props = PropertiesService.getScriptProperties();
    var ssId = props.getProperty('SPREADSHEET_ID');
    var ss = ssId ? SpreadsheetApp.openById(ssId) : SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) return;
    
    var sheet = ss.getSheetByName('license_tokens');
    if (!sheet) {
      sheet = ss.insertSheet('license_tokens');
      sheet.appendRow(['Waktu Generate', 'Kode Token', 'Tipe', 'Sekolah / Mitra', 'Status', 'Catatan']);
      sheet.getRange('A1:F1').setFontWeight('bold');
      sheet.setFrozenRows(1);
    }
    
    var now = new Date();
    var sch = school || 'UMUM';
    tokens.forEach(function(code) {
      sheet.appendRow([now, code, type, sch, 'TERSEDIA', 'Generated via WebGAS']);
    });
  } catch(e) {
    Logger.log('Sheet backup token error (abaikan): ' + e.message);
  }
}

// ─────────────────────────────────────────────────────────────
// PAKET & JADWAL TRYOUT MANAGEMENT (WebGAS Admin)
// ─────────────────────────────────────────────────────────────

/**
 * Mengambil seluruh paket tryout untuk ditampilkan di Admin WebGAS
 */
function getAdminPaketTryout(username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/paket_tryout?pageSize=200';

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
      var docs = data.documents || [];
      var packages = [];
      var activeCount = 0;

      docs.forEach(function(d) {
        var f = d.fields || {};
        var docId = d.name.split('/').pop();
        var status = (f.status && f.status.stringValue) || 'aktif';
        if (status === 'aktif') activeCount++;

        packages.push({
          id: docId,
          paket_id: (f.paket_id && f.paket_id.stringValue) || docId,
          nama_paket: (f.nama_paket && f.nama_paket.stringValue) || '',
          deskripsi: (f.deskripsi && f.deskripsi.stringValue) || '',
          jenis_test: (f.jenis_test && f.jenis_test.stringValue) || 'SNBT',
          jenis_waktu: (f.jenis_waktu && f.jenis_waktu.stringValue) || 'total',
          tanggal: (f.tanggal && f.tanggal.stringValue) || '',
          jam_mulai: (f.jam_mulai && f.jam_mulai.stringValue) || '08:00',
          jam_selesai: (f.jam_selesai && f.jam_selesai.stringValue) || '23:59',
          durasi_menit: parseInt((f.durasi_menit && f.durasi_menit.integerValue) || '120', 10),
          total_soal: parseInt((f.total_soal && f.total_soal.integerValue) || '50', 10),
          status: status,
          target_exam_id: (f.target_exam_id && f.target_exam_id.stringValue) || '',
          pass_percentage: parseInt((f.pass_percentage && f.pass_percentage.integerValue) || '65', 10),
          is_premium_only: f.is_premium_only ? (f.is_premium_only.booleanValue !== false) : true,
          is_lifetime: f.is_lifetime ? (f.is_lifetime.booleanValue === true) : false,
          allow_retake: f.allow_retake ? (f.allow_retake.booleanValue !== false) : true
        });
      });

      return {
        packages: packages,
        total: packages.length,
        active: activeCount,
        inactive: packages.length - activeCount
      };
    } else {
      return { error: 'Gagal memuat paket tryout dari Firestore: ' + resp.getResponseCode() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * JALANKAN SALAH SATU FUNGSI INI DI EDITOR (testDrivePermission ATAU authorizeDrive)
 * Keduanya dibuat TANPA try-catch agar Google Apps Script langsung menampilkan dialog persetujuan:
 * "Otorisasi Diperlukan (Authorization required)" -> Tinjau Izin -> Izinkan.
 */
function testDrivePermission() {
  Logger.log('1. Memeriksa akses ke folder Google Drive resmi (1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ)...');
  var folderId = '1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ';
  var folder = DriveApp.getFolderById(folderId);
  Logger.log('2. SUKSES terhubung ke folder: ' + folder.getName());

  var testFile = folder.createFile('test_auth_' + Date.now() + '.txt', 'ExamGO Google Drive Access OK');
  try { testFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (e) {}
  var testId = testFile.getId();
  Logger.log('3. SUKSES membuat file uji coba ID: ' + testId);

  testFile.setTrashed(true);
  Logger.log('4. File tes dibersihkan. STATUS: IZIN GOOGLE DRIVE SUDAH 100% DIBERIKAN!');
  return 'IZIN GOOGLE DRIVE AKTIF!';
}

function authorizeDrive() {
  return testDrivePermission();
}

/**
 * Diagnostic tool untuk API web app (dengan try-catch agar mengembalikan JSON saat di-ping)
 */
function checkDriveApiStatus() {
  try {
    var props = PropertiesService.getScriptProperties();
    var folderId = props.getProperty('DRIVE_FOLDER_SOAL_IMAGE') || '1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ';
    var folder = DriveApp.getFolderById(folderId);
    var folderName = folder.getName();
    var testBlob = Utilities.newBlob('OK - Drive permission verified at ' + new Date().toISOString(), 'text/plain', 'test_auth.txt');
    var testFile = folder.createFile(testBlob);
    var fileId = testFile.getId();
    try { testFile.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (eSh) {}
    testFile.setTrashed(true);
    return {
      success: true,
      folderId: folderId,
      folderName: folderName,
      canWrite: true,
      testFileId: fileId,
      message: 'Izin Google Drive aktif & berhasil menulis ke folder resmi!'
    };
  } catch (err) {
    return {
      success: false,
      folderId: '1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ',
      error: err.toString(),
      message: 'Gagal mengakses Google Drive: ' + err.message
    };
  }
}

/**
 * Upload gambar base64 ke folder Google Drive resmi
 */
function uploadImageToDriveFolder(base64Data, filename) {
  try {
    var props = PropertiesService.getScriptProperties();
    var targetFolderId = props.getProperty('DRIVE_FOLDER_SOAL_IMAGE') || '1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ';
    var targetFolder;
    try {
      targetFolder = DriveApp.getFolderById(targetFolderId);
    } catch (e) {
      var folders = DriveApp.getFoldersByName('ExamGO_Uploads');
      targetFolder = folders.hasNext() ? folders.next() : DriveApp.createFolder('ExamGO_Uploads');
    }
    try { targetFolder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (eSh) {}

    var match = (base64Data || '').match(/^data:image\/([^;]+);base64,(.+)$/);
    var ext = match ? match[1] : 'png';
    var raw = match ? match[2] : base64Data;
    var decoded = Utilities.base64Decode(raw);
    var cleanName = (filename || ('soal_img_' + Date.now())) + '.' + ext;
    var blob = Utilities.newBlob(decoded, 'image/' + ext, cleanName);
    var file = targetFolder.createFile(blob);
    try { file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); } catch (eSh2) {}
    var fileId = file.getId();
    return {
      success: true,
      fileId: fileId,
      url: 'https://drive.google.com/uc?export=view&id=' + fileId
    };
  } catch (err) {
    return { success: false, error: err.message };
  }
}

/**
 * Menyimpan atau memperbarui paket tryout ke Firestore
 */
function saveAdminPaketTryout(paketData, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!paketData || !paketData.nama_paket) return { error: 'Nama paket harus diisi.' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var paketId = (paketData.paket_id || '').trim().toUpperCase();
  if (!paketId) {
    paketId = 'TO-' + Date.now().toString(36).toUpperCase();
  }

  var totalSoalCount = (paketData.soal && Array.isArray(paketData.soal) && paketData.soal.length > 0)
    ? paketData.soal.length
    : parseInt(paketData.total_soal || '50', 10);

  var fields = {
    paket_id: { stringValue: paketId },
    nama_paket: { stringValue: String(paketData.nama_paket).trim() },
    deskripsi: { stringValue: String(paketData.deskripsi || '').trim() },
    jenis_test: { stringValue: String(paketData.jenis_test || 'SNBT').trim().toUpperCase() },
    jenis_waktu: { stringValue: String(paketData.jenis_waktu || 'total').trim() },
    tanggal: { stringValue: String(paketData.tanggal || '').trim() },
    jam_mulai: { stringValue: String(paketData.jam_mulai || '08:00').trim() },
    jam_selesai: { stringValue: String(paketData.jam_selesai || '23:59').trim() },
    durasi_menit: { integerValue: String(parseInt(paketData.durasi_menit || '120', 10)) },
    total_soal: { integerValue: String(totalSoalCount) },
    status: { stringValue: String(paketData.status || 'aktif').trim() },
    target_exam_id: { stringValue: String(paketData.target_exam_id || '').trim().toUpperCase() },
    pass_percentage: { integerValue: String(parseInt(paketData.pass_percentage || '65', 10)) },
    is_premium_only: { booleanValue: paketData.is_premium_only !== false },
    is_lifetime: { booleanValue: paketData.is_lifetime === true },
    allow_retake: { booleanValue: paketData.allow_retake !== false },
    updated_at: { timestampValue: new Date().toISOString() }
  };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/paket_tryout/' + encodeURIComponent(paketId);

  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'patch',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + accessToken },
      payload: JSON.stringify({ fields: fields }),
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200) {
      _logPaketToSheet(fields);

      var writes = [];
      var subtestsToSave = (paketData.subtests && Array.isArray(paketData.subtests) && paketData.subtests.length > 0)
        ? paketData.subtests
        : [{
            subtest_id: paketId + '_ST1',
            judul: String(paketData.nama_paket || 'Tryout Akbar').trim(),
            durasi: parseInt(paketData.durasi_menit || '120', 10)
          }];

      var primarySubtestId = subtestsToSave[0].subtest_id || (paketId + '_ST1');

      // 1. Simpan seluruh subtest paket ke koleksi /subtest
      for (var stIdx = 0; stIdx < subtestsToSave.length; stIdx++) {
        var st = subtestsToSave[stIdx];
        var stId = st.subtest_id || (paketId + '_ST' + (stIdx + 1));
        if (stIdx === 0) primarySubtestId = stId;
        var stDocPath = 'projects/' + projectId + '/databases/(default)/documents/subtest/' + encodeURIComponent(stId);
        writes.push({
          update: {
            name: stDocPath,
            fields: {
              subtest_id: { stringValue: stId },
              paket_id: { stringValue: paketId },
              judul_subtest: { stringValue: String(st.judul || st.judul_subtest || ('Subtest ' + (stIdx + 1))).trim() },
              durasi_menit: { integerValue: String(parseInt(st.durasi || st.durasi_menit || '0', 10)) },
              soal_count: { integerValue: String(parseInt(st.soal_count || (stIdx === 0 && paketData.soal ? paketData.soal.length : 0), 10)) },
              order_index: { integerValue: String(stIdx) }
            }
          }
        });
      }

      var savedCount = 0;
      var failedQuestions = [];

      // 2. Simpan butir soal jika ada soal dari DOCX
      if (paketData.soal && Array.isArray(paketData.soal) && paketData.soal.length > 0) {
        // Safety net: pastikan semua gambar base64 tersimpan ke Google Drive resmi
        for (var sIdx = 0; sIdx < paketData.soal.length; sIdx++) {
          var sq = paketData.soal[sIdx];
          if (sq.gambar_soal && typeof sq.gambar_soal === 'string' && sq.gambar_soal.indexOf('data:image') === 0) {
            var up = uploadImageToDriveFolder(sq.gambar_soal, 'soal_' + paketId + '_Q' + (sIdx + 1) + '_main');
            if (up && up.url) sq.gambar_soal = up.url;
          }
          ['a', 'b', 'c', 'd', 'e'].forEach(function(optKey) {
            if (sq['gam_' + optKey] && typeof sq['gam_' + optKey] === 'string' && sq['gam_' + optKey].indexOf('data:image') === 0) {
              var upOpt = uploadImageToDriveFolder(sq['gam_' + optKey], 'soal_' + paketId + '_Q' + (sIdx + 1) + '_opt_' + optKey);
              if (upOpt && upOpt.url) sq['gam_' + optKey] = upOpt.url;
            }
          });
        }

        for (var i = 0; i < paketData.soal.length; i++) {
          var q = paketData.soal[i];
          var qNum = i + 1;
          var textPertanyaan = String(q.pertanyaan || '').trim();

          // Validasi kelengkapan opsi pilihan ganda
          var optCount = 0;
          ['a', 'b', 'c', 'd', 'e'].forEach(function(opt) {
            if (String(q[opt] || q['opsi_' + opt] || q['gam_' + opt] || '').trim()) optCount++;
          });

          // Validasi format kelengkapan: lewati jika pertanyaan kosong atau opsi kurang dari 2
          if (!textPertanyaan || optCount < 2) {
            failedQuestions.push(qNum);
            continue;
          }

          var targetStId = q.subtest_id || primarySubtestId;
          var qDocPath = 'projects/' + projectId + '/databases/(default)/documents/tryout_soal/' + encodeURIComponent(paketId + '_Q' + qNum);
          
          var qFields = {
            soal_id: { stringValue: paketId + '_Q' + qNum },
            paket_id: { stringValue: paketId },
            subtest_id: { stringValue: targetStId },
            nomor_soal: { integerValue: String(qNum) },
            pertanyaan: { stringValue: textPertanyaan },
            opsi_a: { stringValue: String(q.a || q.opsi_a || '').trim() },
            opsi_b: { stringValue: String(q.b || q.opsi_b || '').trim() },
            opsi_c: { stringValue: String(q.c || q.opsi_c || '').trim() },
            opsi_d: { stringValue: String(q.d || q.opsi_d || '').trim() },
            opsi_e: { stringValue: String(q.e || q.opsi_e || '').trim() },
            gam_a: { stringValue: String(q.gam_a || '').trim() },
            gam_b: { stringValue: String(q.gam_b || '').trim() },
            gam_c: { stringValue: String(q.gam_c || '').trim() },
            gam_d: { stringValue: String(q.gam_d || '').trim() },
            gam_e: { stringValue: String(q.gam_e || '').trim() },
            kunci: { stringValue: String(q.kunci || 'A').trim().toUpperCase() },
            pembahasan: { stringValue: String(q.pembahasan || '').trim() },
            gambar: { stringValue: String(q.gambar_soal || q.gambar || '').trim() },
            tabel: { stringValue: String(q.baris_tabel || q.tabel || '').trim() }
          };

          writes.push({
            update: {
              name: qDocPath,
              fields: qFields
            }
          });
          savedCount++;

          if (writes.length >= 200) {
            _commitWrites(projectId, accessToken, writes);
            writes = [];
          }
        }
      }

      if (writes.length > 0) {
        _commitWrites(projectId, accessToken, writes);
      }

      if (savedCount === 0 && paketData.soal && paketData.soal.length > 0) {
        return { error: 'Format soal tidak sesuai: Seluruh ' + paketData.soal.length + ' butir soal gagal disimpan karena teks pertanyaan kosong atau pilihan jawaban kurang dari 2 opsi.' };
      }

      if (failedQuestions.length > 0) {
        return {
          success: true,
          paket_id: paketId,
          savedCount: savedCount,
          totalCount: paketData.soal.length,
          failedQuestions: failedQuestions,
          message: 'Peringatan: Ada ' + failedQuestions.length + ' butir soal tidak tersimpan (Soal No. [' + failedQuestions.join(', ') + ']) karena format tidak sesuai. Berhasil menyimpan ' + savedCount + ' dari ' + paketData.soal.length + ' butir soal ke Firestore.'
        };
      }

      return {
        success: true,
        paket_id: paketId,
        subtestsCount: subtestsToSave.length,
        savedCount: savedCount,
        message: 'Paket tryout beserta ' + subtestsToSave.length + ' subtest' + (savedCount > 0 ? ' dan ' + savedCount + ' butir soal berformat LaTeX' : '') + ' berhasil disimpan ke Firestore.'
      };
    } else {
      return { error: 'Gagal menyimpan ke Firestore (' + resp.getResponseCode() + '): ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

function _commitWrites(projectId, accessToken, writes) {
  var commitUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents:commit';
  var resp = UrlFetchApp.fetch(commitUrl, {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + accessToken },
    payload: JSON.stringify({ writes: writes }),
    muteHttpExceptions: true
  });
  var code = resp.getResponseCode();
  if (code !== 200) {
    throw new Error('Gagal upload ke Firestore (HTTP ' + code + '): ' + resp.getContentText());
  }
  return true;
}

/**
 * Menghapus paket tryout dari Firestore
 */
function deleteAdminPaketTryout(paketId, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  var cleanId = String(paketId || '').trim();
  if (!cleanId) return { error: 'ID paket kosong.' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/paket_tryout/' + encodeURIComponent(cleanId);
  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'delete',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200 || resp.getResponseCode() === 204) {
      return { success: true, message: 'Paket tryout ' + cleanId + ' berhasil dihapus.' };
    } else {
      return { error: 'Gagal menghapus dari Firestore (' + resp.getResponseCode() + '): ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Menghapus beberapa paket tryout sekaligus (Bulk Delete)
 */
function deleteMultipleTryouts(paketIds, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!Array.isArray(paketIds)) return { error: 'Invalid input paketIds' };

  var count = 0;
  for (var i = 0; i < paketIds.length; i++) {
    var res = deleteAdminPaketTryout(paketIds[i], username, password);
    if (res && res.success) count++;
  }
  return { success: true, count: count };
}

/**
 * Mengambil daftar subtest untuk paket tertentu dari Firestore
 */
function getAdminSubtests(paketId, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  var cleanId = String(paketId || '').trim();
  if (!cleanId) return { error: 'ID paket kosong.' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/subtest?pageSize=300';

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
      var docs = data.documents || [];
      var subtests = [];

      docs.forEach(function(d) {
        var f = d.fields || {};
        var pId = (f.paket_id && f.paket_id.stringValue) || '';
        if (pId === cleanId) {
          var docId = d.name.split('/').pop();
          subtests.push({
            id: docId,
            subtest_id: (f.subtest_id && f.subtest_id.stringValue) || docId,
            paket_id: pId,
            judul_subtest: (f.judul_subtest && f.judul_subtest.stringValue) || '',
            durasi_menit: parseInt((f.durasi_menit && f.durasi_menit.integerValue) || '0', 10),
            soal_count: parseInt((f.soal_count && f.soal_count.integerValue) || '0', 10),
            order_index: parseInt((f.order_index && f.order_index.integerValue) || '0', 10)
          });
        }
      });

      subtests.sort(function(a, b) {
        return (a.order_index - b.order_index) || a.subtest_id.localeCompare(b.subtest_id);
      });

      return { success: true, subtests: subtests };
    } else {
      return { error: 'Gagal memuat subtest dari Firestore (' + resp.getResponseCode() + ')' };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Menyimpan / memperbarui subtest individu ke Firestore
 */
function saveAdminSubtest(subtestData, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!subtestData || !subtestData.paket_id || !subtestData.judul_subtest) {
    return { error: 'Paket ID dan Judul Subtest harus diisi.' };
  }

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var paketId = String(subtestData.paket_id).trim();
  var subtestId = String(subtestData.subtest_id || '').trim();
  if (!subtestId) {
    subtestId = paketId + '_ST' + Date.now().toString(36).toUpperCase();
  }

  var fields = {
    subtest_id: { stringValue: subtestId },
    paket_id: { stringValue: paketId },
    judul_subtest: { stringValue: String(subtestData.judul_subtest).trim() },
    durasi_menit: { integerValue: String(parseInt(subtestData.durasi_menit || '0', 10)) },
    soal_count: { integerValue: String(parseInt(subtestData.soal_count || '0', 10)) },
    order_index: { integerValue: String(parseInt(subtestData.order_index || '0', 10)) }
  };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/subtest/' + encodeURIComponent(subtestId);

  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'patch',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + accessToken },
      payload: JSON.stringify({ fields: fields }),
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200) {
      return { success: true, subtest_id: subtestId, message: 'Subtest berhasil disimpan.' };
    } else {
      return { error: 'Gagal menyimpan subtest ke Firestore: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Menghapus subtest dari Firestore
 */
function deleteAdminSubtest(subtestId, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  var cleanId = String(subtestId || '').trim();
  if (!cleanId) return { error: 'ID subtest kosong.' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/subtest/' + encodeURIComponent(cleanId);
  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'delete',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200 || resp.getResponseCode() === 204) {
      return { success: true, message: 'Subtest ' + cleanId + ' berhasil dihapus.' };
    } else {
      return { error: 'Gagal menghapus subtest dari Firestore: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Batch mengunggah soal langsung ke Subtest tertentu
 */
function saveAdminSubtestQuestions(subtestId, paketId, questions, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!subtestId || !paketId || !questions || !Array.isArray(questions)) {
    return { error: 'Data subtest, paket, dan soal harus valid.' };
  }

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var cleanSubtestId = String(subtestId).trim();
  var cleanPaketId = String(paketId).trim();

  try {
    var accessToken = _getAccessToken();
    var writes = [];
    var savedCount = 0;
    var failedQuestions = [];

    // Safety net gambar
    for (var sIdx = 0; sIdx < questions.length; sIdx++) {
      var sq = questions[sIdx];
      if (sq.gambar_soal && typeof sq.gambar_soal === 'string' && sq.gambar_soal.indexOf('data:image') === 0) {
        var up = uploadImageToDriveFolder(sq.gambar_soal, 'soal_' + cleanPaketId + '_' + cleanSubtestId + '_Q' + (sIdx + 1) + '_main');
        if (up && up.url) sq.gambar_soal = up.url;
      }
      ['a', 'b', 'c', 'd', 'e'].forEach(function(optKey) {
        if (sq['gam_' + optKey] && typeof sq['gam_' + optKey] === 'string' && sq['gam_' + optKey].indexOf('data:image') === 0) {
          var upOpt = uploadImageToDriveFolder(sq['gam_' + optKey], 'soal_' + cleanPaketId + '_' + cleanSubtestId + '_Q' + (sIdx + 1) + '_opt_' + optKey);
          if (upOpt && upOpt.url) sq['gam_' + optKey] = upOpt.url;
        }
      });
    }

    for (var i = 0; i < questions.length; i++) {
      var q = questions[i];
      var qNum = i + 1;
      var textPertanyaan = String(q.pertanyaan || '').trim();

      var optCount = 0;
      ['a', 'b', 'c', 'd', 'e'].forEach(function(opt) {
        if (String(q[opt] || q['opsi_' + opt] || q['gam_' + opt] || '').trim()) optCount++;
      });

      if (!textPertanyaan || optCount < 2) {
        failedQuestions.push(qNum);
        continue;
      }

      var qDocId = cleanSubtestId + '_Q' + qNum;
      var qDocPath = 'projects/' + projectId + '/databases/(default)/documents/tryout_soal/' + encodeURIComponent(qDocId);

      var qFields = {
        soal_id: { stringValue: qDocId },
        paket_id: { stringValue: cleanPaketId },
        subtest_id: { stringValue: cleanSubtestId },
        nomor_soal: { integerValue: String(qNum) },
        pertanyaan: { stringValue: textPertanyaan },
        opsi_a: { stringValue: String(q.a || q.opsi_a || '').trim() },
        opsi_b: { stringValue: String(q.b || q.opsi_b || '').trim() },
        opsi_c: { stringValue: String(q.c || q.opsi_c || '').trim() },
        opsi_d: { stringValue: String(q.d || q.opsi_d || '').trim() },
        opsi_e: { stringValue: String(q.e || q.opsi_e || '').trim() },
        gam_a: { stringValue: String(q.gam_a || '').trim() },
        gam_b: { stringValue: String(q.gam_b || '').trim() },
        gam_c: { stringValue: String(q.gam_c || '').trim() },
        gam_d: { stringValue: String(q.gam_d || '').trim() },
        gam_e: { stringValue: String(q.gam_e || '').trim() },
        kunci: { stringValue: String(q.kunci || 'A').trim().toUpperCase() },
        pembahasan: { stringValue: String(q.pembahasan || '').trim() },
        gambar: { stringValue: String(q.gambar_soal || q.gambar || '').trim() },
        tabel: { stringValue: String(q.baris_tabel || q.tabel || '').trim() }
      };

      writes.push({
        update: {
          name: qDocPath,
          fields: qFields
        }
      });
      savedCount++;

      if (writes.length >= 200) {
        _commitWrites(projectId, accessToken, writes);
        writes = [];
      }
    }

    var stDocPath = 'projects/' + projectId + '/databases/(default)/documents/subtest/' + encodeURIComponent(cleanSubtestId);
    writes.push({
      update: {
        name: stDocPath,
        fields: {
          soal_count: { integerValue: String(savedCount) }
        }
      },
      updateMask: { fieldPaths: ['soal_count'] }
    });

    if (writes.length > 0) {
      _commitWrites(projectId, accessToken, writes);
    }

    return {
      success: true,
      subtest_id: cleanSubtestId,
      savedCount: savedCount,
      failedQuestions: failedQuestions,
      message: 'Berhasil mengunggah ' + savedCount + ' butir soal ke subtest.'
    };
  } catch(e) {
    return { error: e.message };
  }
}

/**
 * Backup paket tryout ke tab Sheet 'paket_tryout'
 */
function _logPaketToSheet(fields) {
  try {
    var props = PropertiesService.getScriptProperties();
    var ssId = props.getProperty('SPREADSHEET_ID');
    var ss = ssId ? SpreadsheetApp.openById(ssId) : SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) return;

    var sheet = ss.getSheetByName('paket_tryout');
    if (!sheet) {
      sheet = ss.insertSheet('paket_tryout');
      sheet.appendRow(['ID Paket', 'Nama Paket', 'Jenis Test', 'Tanggal', 'Jam Mulai', 'Jam Selesai', 'Durasi', 'Status', 'Target Exam ID', 'Updated At']);
      sheet.getRange('A1:J1').setFontWeight('bold');
      sheet.setFrozenRows(1);
    }
    sheet.appendRow([
      fields.paket_id.stringValue,
      fields.nama_paket.stringValue,
      fields.jenis_test.stringValue,
      fields.tanggal.stringValue,
      fields.jam_mulai.stringValue,
      fields.jam_selesai.stringValue,
      fields.durasi_menit.integerValue,
      fields.status.stringValue,
      fields.target_exam_id.stringValue,
      new Date()
    ]);
  } catch(e) {
    Logger.log('Sheet backup tryout error (abaikan): ' + e.message);
  }
}

/**
 * Auto-clean abandoned exam sessions:
 * Menghapus sesi ujian yang umurnya sudah >= 10 hari dan siswanya 0 (hemat kuota Firebase)
 */
function cleanupAbandonedExamSessions() {
  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum diatur' };

  try {
    var accessToken = _getAccessToken();
    var tenDaysAgo = new Date(Date.now() - (10 * 24 * 60 * 60 * 1000)).toISOString();
    
    // Ambil daftar exam_sessions (max 100 dokumen per eksekusi agar hemat kuota REST API)
    var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/exam_sessions?pageSize=100';
    var resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + accessToken },
      muteHttpExceptions: true
    });
    
    if (resp.getResponseCode() !== 200) return { error: 'Gagal membaca Firestore' };
    
    var data = JSON.parse(resp.getContentText());
    var docs = data.documents || [];
    var deletedCount = 0;
    
    docs.forEach(function(doc) {
      var fields = doc.fields || {};
      var studentCount = 0;
      if (fields.student_count && fields.student_count.integerValue) {
        studentCount = parseInt(fields.student_count.integerValue, 10);
      }
      
      var createdAt = (fields.created_at && fields.created_at.timestampValue) || '';
      var isOld = createdAt ? (new Date(createdAt) < new Date(tenDaysAgo)) : false;
      
      if (isOld && studentCount === 0) {
        // Hapus dokumen sesi ini
        var delUrl = 'https://firestore.googleapis.com/v1/' + doc.name;
        UrlFetchApp.fetch(delUrl, {
          method: 'delete',
          headers: { Authorization: 'Bearer ' + accessToken },
          muteHttpExceptions: true
        });
        deletedCount++;
      }
    });
    
    Logger.log('cleanupAbandonedExamSessions: Berhasil menghapus ' + deletedCount + ' sesi terlantar (0 siswa, >= 10 hari)');
    return { success: true, deleted: deletedCount };
  } catch (err) {
    Logger.log('cleanupAbandonedExamSessions Gagal: ' + err.toString());
    return { success: false, error: err.message };
  }
}
