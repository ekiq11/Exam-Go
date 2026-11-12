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
  var data = {};

  if (e && e.postData && e.postData.contents) {
    try {
      data = JSON.parse(e.postData.contents);
    } catch (err) {
      data = {};
    }
  }

  // ── Webhook Lynk.id Handler (Auto Deliver Token) ───────────────
  var secret = e && e.parameter && e.parameter.secret;
  var isLynkParam = e && e.parameter && (e.parameter.action === 'webhook_lynk' || e.parameter.source === 'lynkid' || e.parameter.source === 'lynk' || secret);
  var eventName = (data && data.event) || '';
  var isLynkEvent = eventName === 'payment.received' || eventName === 'order.paid' ||
                    eventName === 'payment_received' || eventName === 'order_paid' ||
                    eventName === 'test' || eventName === 'ping' ||
                    (data && data.data && data.data.message_data) ||
                    (data && (data.refId || data.orderId));
  Logger.log('doPost: isLynkParam=' + isLynkParam + ' isLynkEvent=' + isLynkEvent + ' event=' + eventName + ' action=' + (e && e.parameter && e.parameter.action));
  if (isLynkParam || isLynkEvent) {
    return handleLynkIdWebhook(e, data);
  }

  // ── Public & Admin Landing Page Settings API (Tidak butuh API_KEY, memakai auth user/pass untuk save) ──
  var reqAction = (data && data.action) || (e && e.parameter && e.parameter.action) || '';
  if (reqAction === 'getLandingPageSettings' || reqAction === 'get_landing_settings') {
    return _json({ status: 'success', settings: getLandingPageSettings() });
  }
  if (reqAction === 'saveLandingPageSettings') {
    var u = data.username || data.user || (e && e.parameter && (e.parameter.username || e.parameter.user)) || '';
    var p = data.password || data.pass || (e && e.parameter && (e.parameter.password || e.parameter.pass)) || '';
    var setts = data.settings || data;
    var saveRes = saveLandingPageSettings(setts, u, p);
    return _json(saveRes);
  }

  // Validasi API key
  if (!data.apiKey || data.apiKey !== props.getProperty('API_KEY')) {
    Logger.log('⛔ Unauthorized request');
    return _json({ error: 'unauthorized' });
  }

  var action = data.action || 'notify';

  // ── Kelola Iklan (Admin) ────────────────────────────────────────
  if (action === 'saveAd') {
    return _json(saveAd(data.ad || data));
  }
  if (action === 'deleteAd') {
    return _json(deleteAd(data.adId));
  }

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
      var directUrl = 'https://lh3.googleusercontent.com/d/' + fileId;
      
      return _json({
        success: true,
        fileId: fileId,
        url: directUrl,
        cdnUrl: directUrl,
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
        return _json({ success: false, isSuccess: false, error: 'not_found', message: 'Kode token tidak ditemukan atau salah ketik.' });
      }
      if (resp.getResponseCode() !== 200) {
        return _json({ success: false, isSuccess: false, error: 'http_error', message: 'Gagal verifikasi lisensi (HTTP ' + resp.getResponseCode() + ')' });
      }

      var doc = JSON.parse(resp.getContentText());
      var f = doc.fields || {};
      var isUsed = f.is_used && f.is_used.booleanValue;
      var assignedDevice = (f.device_id && f.device_id.stringValue) || '';
      var tokenType = (f.type && f.type.stringValue) || 'STUDENT_LIFETIME';
      var targetExamId = (f.target_exam_id && f.target_exam_id.stringValue) || '';

      if (userType && userType !== tokenType && tokenType !== 'EVENT') {
        return _json({
          success: false,
          isSuccess: false,
          error: 'type_mismatch',
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
            success: false,
            isSuccess: false,
            error: 'quota_full',
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

        if (deviceId) {
          var devField = (tokenType === 'TEACHER_PREMIUM') ? 'is_teacher_premium' : 'is_student_premium';
          var devDocUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/devices/' + encodeURIComponent(deviceId) + '?updateMask.fieldPaths=' + devField + '&updateMask.fieldPaths=last_token_activated&updateMask.fieldPaths=activated_at&updateMask.fieldPaths=school';
          var devPayload = {
            fields: {
              last_token_activated: { stringValue: rawToken },
              activated_at: { timestampValue: new Date().toISOString() },
              school: { stringValue: school }
            }
          };
          devPayload.fields[devField] = { booleanValue: true };
          UrlFetchApp.fetch(devDocUrl, {
            method: 'patch',
            contentType: 'application/json',
            headers: { Authorization: 'Bearer ' + accessToken },
            payload: JSON.stringify(devPayload),
            muteHttpExceptions: true
          });
        }

        return _json({
          success: true,
          isSuccess: true,
          message: 'Selamat! Akun ' + (tokenType === 'TEACHER_PREMIUM' ? 'Guru Premium' : 'Siswa Lifetime') + ' ' + school + ' aktif!',
          tokenType: tokenType,
          targetExamId: targetExamId
        });
      }

      if (isUsed && assignedDevice && assignedDevice !== deviceId) {
        return _json({
          success: false,
          isSuccess: false,
          error: 'already_used',
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

      if (deviceId) {
        var devField = (tokenType === 'TEACHER_PREMIUM') ? 'is_teacher_premium' : 'is_student_premium';
        var devDocUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/devices/' + encodeURIComponent(deviceId) + '?updateMask.fieldPaths=' + devField + '&updateMask.fieldPaths=last_token_activated&updateMask.fieldPaths=activated_at';
        var devPayload = {
          fields: {
            last_token_activated: { stringValue: rawToken },
            activated_at: { timestampValue: new Date().toISOString() }
          }
        };
        devPayload.fields[devField] = { booleanValue: true };
        UrlFetchApp.fetch(devDocUrl, {
          method: 'patch',
          contentType: 'application/json',
          headers: { Authorization: 'Bearer ' + accessToken },
          payload: JSON.stringify(devPayload),
          muteHttpExceptions: true
        });
      }

      return _json({
        success: true,
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

  // ── Ambil butir soal tryout lengkap (Resilience Fallback untuk Siswa) ──────
  if (action === 'getSoalTryout') {
    var targetPid = (data.paketId || data.token || '').trim();
    if (!targetPid) return _json({ status: 'error', message: 'paketId required' });
    var soalData = _getSoalForPaket(targetPid);
    return _json(soalData);
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

// ── Ambil butir soal untuk paket ujian tertentu (Multi-source: Firestore + Sheet Fallback) ──
function _getSoalForPaket(targetPaketId) {
  var pId = String(targetPaketId || '').trim().toUpperCase();
  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');

  // 1. Coba ambil dari Firestore REST API
  if (projectId) {
    try {
      var accessToken = _getAccessToken();
      var headers = {
        Authorization: 'Bearer ' + accessToken,
        'Cache-Control': 'no-cache'
      };

      // (a) Ambil dokumen paket_tryout
      var pkgUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/paket_tryout/' + encodeURIComponent(pId);
      var pkgResp = UrlFetchApp.fetch(pkgUrl, { method: 'get', headers: headers, muteHttpExceptions: true });
      var pkgData = null;
      if (pkgResp.getResponseCode() === 200) {
        var pJson = JSON.parse(pkgResp.getContentText());
        pkgData = _firestoreFieldsToObj(pJson.fields || {});
      }

      // (b) Ambil tryout_soal via structured query
      var queryUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents:runQuery';
      var qPayload = {
        structuredQuery: {
          from: [{ collectionId: 'tryout_soal' }],
          where: {
            fieldFilter: {
              field: { fieldPath: 'paket_id' },
              op: 'EQUAL',
              value: { stringValue: pId }
            }
          }
        }
      };

      var qResp = UrlFetchApp.fetch(queryUrl, {
        method: 'post',
        headers: headers,
        contentType: 'application/json',
        payload: JSON.stringify(qPayload),
        muteHttpExceptions: true
      });

      var questions = [];
      if (qResp.getResponseCode() === 200) {
        var queryResults = JSON.parse(qResp.getContentText());
        if (Array.isArray(queryResults)) {
          queryResults.forEach(function(res) {
            if (res.document && res.document.fields) {
              var qObj = _firestoreFieldsToObj(res.document.fields);
              questions.push(qObj);
            }
          });
        }
      }

      // (c) Ambil subtest via structured query
      var stPayload = {
        structuredQuery: {
          from: [{ collectionId: 'subtest' }],
          where: {
            fieldFilter: {
              field: { fieldPath: 'paket_id' },
              op: 'EQUAL',
              value: { stringValue: pId }
            }
          }
        }
      };

      var stResp = UrlFetchApp.fetch(queryUrl, {
        method: 'post',
        headers: headers,
        contentType: 'application/json',
        payload: JSON.stringify(stPayload),
        muteHttpExceptions: true
      });

      var subtests = [];
      if (stResp.getResponseCode() === 200) {
        var stResults = JSON.parse(stResp.getContentText());
        if (Array.isArray(stResults)) {
          stResults.forEach(function(res) {
            if (res.document && res.document.fields) {
              subtests.push(_firestoreFieldsToObj(res.document.fields));
            }
          });
        }
      }

      // Jika butir soal via paket_id kosong, coba query via subtest_id dalam 1 batch IN (hindari N+1 query)
      if (questions.length === 0 && subtests.length > 0) {
        var subtestIds = [];
        for (var si = 0; si < subtests.length; si++) {
          if (subtests[si].subtest_id) subtestIds.push(subtests[si].subtest_id);
        }
        if (subtestIds.length > 0) {
          var stQPayload = {
            structuredQuery: {
              from: [{ collectionId: 'tryout_soal' }],
              where: {
                fieldFilter: {
                  field: { fieldPath: 'subtest_id' },
                  op: 'IN',
                  value: {
                    arrayValue: {
                      values: subtestIds.slice(0, 30).map(function(id) {
                        return { stringValue: String(id) };
                      })
                    }
                  }
                }
              }
            }
          };
          var stQResp = UrlFetchApp.fetch(queryUrl, {
            method: 'post',
            headers: headers,
            contentType: 'application/json',
            payload: JSON.stringify(stQPayload),
            muteHttpExceptions: true
          });
          if (stQResp.getResponseCode() === 200) {
            var stQResults = JSON.parse(stQResp.getContentText());
            if (Array.isArray(stQResults)) {
              stQResults.forEach(function(res) {
                if (res.document && res.document.fields) {
                  questions.push(_firestoreFieldsToObj(res.document.fields));
                }
              });
            }
          }
        }
      }

      if (questions.length > 0) {
        return {
          status: 'success',
          source: 'firestore',
          paket: pkgData || { paket_id: pId, nama_paket: 'Tryout ' + pId },
          subtests: subtests,
          questions: questions
        };
      }
    } catch(err) {
      Logger.log('Firestore fetch error: ' + err.message);
    }
  }

  // 2. Fallback: Ambil langsung dari Google Sheet aktif
  try {
    var ss = null;
    var sheetId = props.getProperty('SHEET_ID');
    if (sheetId) {
      try { ss = SpreadsheetApp.openById(sheetId); } catch(e) {}
    }
    if (!ss) {
      try { ss = SpreadsheetApp.getActiveSpreadsheet(); } catch(e) {}
    }

    if (ss) {
      var qSheet = ss.getSheetByName('tryout_soal');
      var stSheet = ss.getSheetByName('subtest');
      var pSheet = ss.getSheetByName('paket_tryout');

      var allQRows = qSheet ? _readSheetTableRows(qSheet) : [];
      var allStRows = stSheet ? _readSheetTableRows(stSheet) : [];
      var allPRows = pSheet ? _readSheetTableRows(pSheet) : [];

      var matchedQ = allQRows.filter(function(r) {
        var qP = String(r.paket_id || '').trim().toUpperCase();
        return qP === pId || qP.indexOf(pId) >= 0;
      });

      var matchedSt = allStRows.filter(function(r) {
        var stP = String(r.paket_id || '').trim().toUpperCase();
        return stP === pId || stP.indexOf(pId) >= 0;
      });

      var matchedP = allPRows.filter(function(r) {
        var p = String(r.paket_id || '').trim().toUpperCase();
        return p === pId;
      });

      if (matchedQ.length > 0) {
        return {
          status: 'success',
          source: 'sheets',
          paket: matchedP.length > 0 ? matchedP[0] : { paket_id: pId, nama_paket: 'Tryout ' + pId },
          subtests: matchedSt,
          questions: matchedQ
        };
      }
    }
  } catch(sheetErr) {
    Logger.log('Sheet fetch error: ' + sheetErr.message);
  }

  return { status: 'error', message: 'Paket ' + pId + ' tidak ditemukan atau tidak memiliki butir soal.' };
}

function _firestoreFieldsToObj(fields) {
  var obj = {};
  if (!fields) return obj;
  Object.keys(fields).forEach(function(k) {
    var valObj = fields[k];
    if (valObj.stringValue !== undefined) obj[k] = valObj.stringValue;
    else if (valObj.integerValue !== undefined) obj[k] = parseInt(valObj.integerValue, 10);
    else if (valObj.booleanValue !== undefined) obj[k] = valObj.booleanValue;
    else if (valObj.doubleValue !== undefined) obj[k] = valObj.doubleValue;
    else if (valObj.timestampValue !== undefined) obj[k] = valObj.timestampValue;
  });
  return obj;
}


// ── GET: Render Dashboard HTML ───────────────────────────────────
function doGet(e) {
  // ── GET: Ambil Konten Landing Page (Publik) ─────────────────────
  if (e && e.parameter && (e.parameter.action === 'get_landing_settings' || e.parameter.action === 'getLandingPageSettings')) {
    return ContentService.createTextOutput(JSON.stringify({
      status: 'success',
      settings: getLandingPageSettings()
    })).setMimeType(ContentService.MimeType.JSON);
  }

  if (e && e.parameter && (e.parameter.action === 'webhook_lynk' || e.parameter.source === 'lynkid' || e.parameter.source === 'lynk')) {
    return ContentService.createTextOutput(JSON.stringify({
      status: 'success',
      message: 'ExamGO Webhook Endpoint for Lynk.id is Active & Ready! (Use POST for order fulfillment)',
      endpoint: 'POST',
      timestamp: new Date().toISOString()
    })).setMimeType(ContentService.MimeType.JSON);
  }

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

  // ── GET: Ambil Histori Transaksi Lynk.id via API REST ──────────
  if (e && e.parameter && (e.parameter.action === 'get_lynk_transactions' || e.parameter.action === 'lynk_transactions')) {
    var userParam = e.parameter.user || e.parameter.username || '';
    var passParam = e.parameter.pass || e.parameter.password || '';
    var lynkRes = getLynkTransactions(userParam, passParam);
    return ContentService.createTextOutput(JSON.stringify(lynkRes)).setMimeType(ContentService.MimeType.JSON);
  }

  // ── GET: Ambil iklan popup aktif ──
  if (e && e.parameter && (e.parameter.action === 'get_ads' || e.parameter.action === 'popup_ads')) {
    return ContentService.createTextOutput(JSON.stringify(getPopupAdsSettings())).setMimeType(ContentService.MimeType.JSON);
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
  
  // Routing: ?action=copy atau ?action=salin membuka Halaman Salin Token Instan
  if (e && e.parameter && (e.parameter.action === 'copy' || e.parameter.action === 'salin' || e.parameter.copy)) {
    var rawTok = e.parameter.token || e.parameter.copy || e.parameter.t || '';
    return _renderCopyTokenHtmlOutput(rawTok);
  }

  // Routing: ?action=props_manager atau ?action=audit_props atau ?action=clean_props
  if (e && e.parameter && (e.parameter.action === 'props_manager' || e.parameter.action === 'audit_props' || e.parameter.action === 'clean_props')) {
    return _renderPropsManagerHtmlOutput(e);
  }

  // Routing: ?page=admin atau ?admin=true membuka Portal Administrator
  if (e && e.parameter && (e.parameter.page === 'admin' || e.parameter.admin === 'true')) {
    return HtmlService.createHtmlOutputFromFile('admin')
      .setTitle('ExamGO Administrator')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1')
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
  }

  // Routing: ?page=privacy atau ?page=terms membuka Dokumen Legal & Kebijakan Privasi
  if (e && e.parameter && (e.parameter.page === 'privacy' || e.parameter.page === 'terms' || e.parameter.privacy === 'true')) {
    return HtmlService.createHtmlOutputFromFile('privacy')
      .setTitle('ExamGO — Kebijakan Privasi & Syarat Ketentuan Layanan')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1')
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
  }

  // Secara default (publik / siswa) tampilkan Landing Page Penjualan & Promosi
  return HtmlService.createHtmlOutputFromFile('landing')
    .setTitle('ExamGO — Platform Tryout SNBT, SKD & CBT Ujian Sekolah #1')
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
    if (String(data[i][0]).trim().toLowerCase() === String(username || '').trim().toLowerCase() && 
        String(data[i][1]).trim() === String(password || '').trim()) {
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
function generateLicenseTokens(username, password, type, count, targetExamId, school, format) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set di Script Properties.' };

  var validCount = parseInt(count) || 10;
  if (validCount > 500) validCount = 500;
  if (validCount < 1) validCount = 1;

  var tokenType = (type === 'TEACHER_PREMIUM') ? 'TEACHER_PREMIUM' : (type === 'EVENT' ? 'EVENT' : 'STUDENT_LIFETIME');
  var prefix = (tokenType === 'TEACHER_PREMIUM') ? 'GURU' : (tokenType === 'EVENT' ? 'EVENT' : 'SISWA');
  var cleanSchool = school ? String(school).trim() : 'UMUM (Lynk.id)';
  var chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  var isShort6 = (format === 'SHORT6');
  var generatedTokens = [];
  var writes = [];
  var cleanTargetId = targetExamId ? String(targetExamId).trim().toUpperCase() : '';

  for (var i = 0; i < validCount; i++) {
    var code = '';
    if (isShort6) {
      // Format 6 Karakter: Sangat mudah diinputkan di menu Input Token Manual Home ExamGo
      var pre = (tokenType === 'EVENT') ? 'EV' : (tokenType === 'TEACHER_PREMIUM' ? 'GR' : 'SW');
      code = pre;
      for (var s = 0; s < 4; s++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
      }
    } else {
      var seg1 = '';
      var seg2 = '';
      for (var j = 0; j < 4; j++) {
        seg1 += chars.charAt(Math.floor(Math.random() * chars.length));
        seg2 += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      code = prefix + '-' + seg1 + '-' + seg2;
    }
    generatedTokens.push(code);

    var docPath = 'projects/' + projectId + '/databases/(default)/documents/license_tokens/' + code;
    var fieldsObj = {
      token: { stringValue: code },
      type: { stringValue: tokenType },
      school: { stringValue: cleanSchool },
      is_used: { booleanValue: false },
      device_id: { nullValue: null },
      used_by_email: { nullValue: null },
      created_at: { timestampValue: new Date().toISOString() },
      platform: { stringValue: 'lynk.id' }
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
    var chunkSize = 150;
    for (var k = 0; k < writes.length; k += chunkSize) {
      var batch = writes.slice(k, k + chunkSize);
      var commitUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents:commit';
      var resp = UrlFetchApp.fetch(commitUrl, {
        method: 'post',
        contentType: 'application/json',
        headers: { Authorization: 'Bearer ' + accessToken },
        payload: JSON.stringify({ writes: batch }),
        muteHttpExceptions: true
      });

      if (resp.getResponseCode() !== 200) {
        return { error: 'Gagal commit ke Firestore: ' + resp.getContentText() };
      }
    }

    _logTokensToSheet(generatedTokens, tokenType, cleanSchool);
    return {
      success: true,
      count: generatedTokens.length,
      tokens: generatedTokens,
      type: tokenType,
      prefix: prefix,
      school: cleanSchool
    };
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
        var userName = (f.user_name && f.user_name.stringValue) ? f.user_name.stringValue : '-';
        var userWhatsapp = (f.user_whatsapp && f.user_whatsapp.stringValue) ? f.user_whatsapp.stringValue : '-';
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
          userName: userName,
          userWhatsapp: userWhatsapp,
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
    var rows = tokens.map(function(code) {
      return [now, code, type, sch, 'TERSEDIA', 'Generated via WebGAS'];
    });
    if (rows.length > 0) {
      sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, 6).setValues(rows);
    }
  } catch(e) {
    Logger.log('Sheet backup token error (abaikan): ' + e.message);
  }
}

// ─────────────────────────────────────────────────────────────
// LYNK.ID WEBHOOK INTEGRATION (AUTO-FULFILLMENT ENGINE)
// ─────────────────────────────────────────────────────────────

/**
 * Handler utama Webhook Lynk.id.
 * Mendukung ping test ("Test URL"), auto claim token dari stok,
 * auto generate token jika stok habis (zero stockout), anti-duplikasi (idempotent),
 * pengiriman email otomatis via MailApp, dan logging transaksi.
 */
function handleLynkIdWebhook(e, data) {
  Logger.log('📥 Menerima Lynk.id Webhook Payload: ' + JSON.stringify(data));

  // 1. Tangani test ping dari Lynk.id dashboard ("Test URL")
  if (!data || Object.keys(data).length === 0 || data.event === 'test' || data.event === 'ping') {
    Logger.log('🔔 Lynk.id Webhook Test Ping Handled');
    return _json({
      status: 'success',
      message: 'ExamGO Webhook Active & Ready',
      code: '0',
      timestamp: new Date().toISOString()
    });
  }

  // Verifikasi: Merchant Key sudah dicek di Cloudflare Worker (CF bisa baca headers, GAS tidak).
  // Di GAS cukup verifikasi ?secret= query param saja.
  var props = PropertiesService.getScriptProperties();
  var webhookSecret = props.getProperty('LYNK_WEBHOOK_SECRET') || '';
  var apiKey = props.getProperty('API_KEY') || '';
  var isAdminCall = apiKey && data.apiKey === apiKey;

  if (webhookSecret && !isAdminCall) {
    var providedSecret = (e && e.parameter && (e.parameter.secret || e.parameter.webhook_key)) || '';
    if (providedSecret !== webhookSecret) {
      Logger.log('🚫 Webhook ditolak: secret tidak cocok.');
      return _json({ status: 'error', message: 'Unauthorized webhook request' });
    }
  }
  Logger.log('✅ Webhook diizinkan.');

  // 2. Ekstrak data transaksi — log RAW untuk debug
  Logger.log('DEBUG event=' + data.event + ' keys=' + Object.keys(data).join(','));
  Logger.log('DEBUG data.data=' + JSON.stringify(data.data || {}).substring(0, 300));
  var msgData = (data.data && data.data.message_data) ? data.data.message_data : (data.data || data);
  var customer = msgData.customer || data.customer || {};

  var orderId = String(msgData.refId || msgData.orderId || data.orderId || data.refId || (data.data && data.data.message_id) || '').trim();
  Logger.log('DEBUG orderId=' + orderId + ' customer=' + JSON.stringify(customer).substring(0, 150));
  if (!orderId) {
    return _json({ status: 'success', message: 'ExamGO Webhook Ping Handled' });
  }

  var customerName = String(customer.name || msgData.name || data.name || 'Siswa ExamGO').trim();
  var customerEmail = String(customer.email || msgData.email || data.email || '').trim();
  var customerPhone = String(customer.phone || customer.phone_number || msgData.phone || data.phone || '').trim();

  // Ekstrak rincian produk
  var items = msgData.items || data.items || [];
  var productTitle = '';
  var quantity = 1;
  var grandTotal = 0;

  if (items && items.length > 0) {
    productTitle = items.map(function(it) { return it.productTitle || it.title || it.name || it.productName || it.product_name || ''; }).filter(Boolean).join(', ');
    quantity = items.reduce(function(acc, it) { return acc + (Number(it.qty || it.quantity || 1)); }, 0) || 1;
  } else {
    productTitle = msgData.productTitle || msgData.product_name || msgData.title || msgData.name || data.product_name || data.title || 'Token ExamGO';
  }

  // grandTotal boleh 0 (order gratis/kupon) — jangan pakai truthiness check
  if (msgData.totals && msgData.totals.grandTotal !== undefined) {
    grandTotal = Number(msgData.totals.grandTotal);
  } else if (msgData.grandTotal !== undefined) {
    grandTotal = Number(msgData.grandTotal);
  } else if (data.amount !== undefined) {
    grandTotal = Number(data.amount);
  }
  Logger.log('DEBUG productTitle=' + productTitle + ' grandTotal=' + grandTotal + ' email=' + customerEmail);

  // Validasi: wajib event payment/order DAN email valid — grandTotal boleh 0 (gratis/kupon)
  var isPaymentEvent = (data.event === 'payment.received' || data.event === 'order.paid' ||
                        data.event === 'payment_received' || data.event === 'order_paid' ||
                        (data.event || '').indexOf('payment') !== -1 || (data.event || '').indexOf('order') !== -1);
  var hasEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail);
  if (!isAdminCall && !isPaymentEvent) {
    Logger.log('🚫 Bukan payment event: ' + data.event);
    return _json({ status: 'error', message: 'Invalid transaction event: ' + data.event });
  }
  if (!isAdminCall && !hasEmail) {
    Logger.log('🚫 Email tidak valid: ' + customerEmail);
    return _json({ status: 'error', message: 'Email pembeli wajib diisi di checkout Lynk.id' });
  }

  // 3. Tentukan role token
  var tokenType = 'STUDENT_LIFETIME';
  var titleUpper = productTitle.toUpperCase();
  if (titleUpper.indexOf('EVENT') !== -1 || titleUpper.indexOf('TIKET') !== -1) {
    tokenType = 'EVENT';
  } else if (titleUpper.indexOf('GURU') !== -1 || titleUpper.indexOf('TEACHER') !== -1) {
    tokenType = 'TEACHER_PREMIUM';
  }

  // Gunakan ScriptLock untuk mencegah race condition (2 pembeli di detik yang sama mendapat token yang sama)
  var lock = LockService.getScriptLock();
  lock.waitLock(15000);
  var assignedToken = '';
  var existing = null;
  try {
    // 4. Idempotency Check (Cegah token ganda jika webhook di-retry oleh Lynk.id)
    existing = _findAssignedLynkToken(orderId);
    if (!existing) {
      // 5. Alokasikan token (Ambil dari stok TERSEDIA atau generate baru jika habis)
      assignedToken = _claimOrCreateLynkToken(tokenType, customerName, customerEmail, customerPhone, orderId);
      SpreadsheetApp.flush();
    }
  } finally {
    lock.releaseLock();
  }

  if (existing) {
    Logger.log('⚠️ Order [' + orderId + '] sudah diproses sebelumnya dengan token: ' + existing.token);
    var emailRes = { success: false, error: 'No email' };
    if (customerEmail) {
      emailRes = _sendBuyerTokenEmail(customerEmail, customerName, orderId, existing.token, productTitle);
    }
    var maskedExisting = existing.token ? (existing.token.substring(0, 6) + '-****-****') : '';
    return _json({
      status: 'success',
      message: 'Order already fulfilled (Idempotent)' + (emailRes.success ? ' & email delivered' : ''),
      orderId: orderId,
      token: isAdminCall ? existing.token : maskedExisting,
      customer: {
        name: customerName,
        email: customerEmail,
        phone: customerPhone
      },
      emailDelivered: !!emailRes.success,
      emailError: emailRes.error || null,
      isDuplicate: true
    });
  }

  // 6. Kirim email otomatis ke pembeli
  var newEmailRes = { success: false };
  if (customerEmail) {
    newEmailRes = _sendBuyerTokenEmail(customerEmail, customerName, orderId, assignedToken, productTitle);
  }

  // 7. Catat transaksi di Sheet lynk_transactions
  _recordLynkTransaction(
    orderId,
    customerName,
    customerEmail,
    customerPhone,
    productTitle,
    quantity,
    grandTotal,
    assignedToken,
    newEmailRes.success ? 'SUCCESS_EMAILED' : 'SUCCESS'
  );

  Logger.log('🎉 Sukses memenuhi order ' + orderId + ' dengan token: ' + assignedToken);

  var maskedToken = assignedToken ? (assignedToken.substring(0, 6) + '-****-****') : '';
  return _json({
    status: 'success',
    message: 'Token assigned and delivered successfully',
    orderId: orderId,
    token: isAdminCall ? assignedToken : maskedToken,
    customer: {
      name: customerName,
      email: customerEmail,
      phone: customerPhone
    },
    emailDelivered: !!newEmailRes.success,
    emailError: newEmailRes.error || null
  });
}

var _memoizedSS = null;
function _getSpreadsheet() {
  if (_memoizedSS) return _memoizedSS;
  var ssId = PropertiesService.getScriptProperties().getProperty('SPREADSHEET_ID');
  _memoizedSS = ssId ? SpreadsheetApp.openById(ssId) : SpreadsheetApp.getActiveSpreadsheet();
  return _memoizedSS;
}

/**
 * Cek apakah orderId sudah pernah diproses sebelumnya di Sheet 'lynk_transactions'
 */
function _findAssignedLynkToken(orderId) {
  try {
    var ss = _getSpreadsheet();
    if (!ss) return null;
    var sheet = ss.getSheetByName('lynk_transactions');
    if (!sheet || sheet.getLastRow() <= 1) return null;

    var data = sheet.getDataRange().getValues();
    for (var i = 1; i < data.length; i++) {
      if (String(data[i][1]).trim() === String(orderId).trim()) {
        return {
          token: String(data[i][8]).trim(),
          customerName: data[i][2],
          customerEmail: data[i][3],
          row: i + 1
        };
      }
    }
  } catch (e) {
    Logger.log('Error checking idempotency: ' + e);
  }
  return null;
}

/**
 * Mengambil 1 token yang tersedia dari stok atau generate token baru jika stok habis.
 * Memastikan zero stockout dan sinkronisasi ke Firestore.
 */
function _claimOrCreateLynkToken(tokenType, customerName, customerEmail, customerPhone, orderId) {
  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID') || 'examgo-31b5b';
  var ss = _getSpreadsheet();
  
  var tokenCode = null;
  var isNewGenerated = false;

  // 1. Coba cari token dengan status 'TERSEDIA' di Sheet 'license_tokens'
  if (ss) {
    try {
      var sheet = ss.getSheetByName('license_tokens');
      if (sheet && sheet.getLastRow() > 1) {
        var data = sheet.getDataRange().getValues();
        // data[0] adalah header: ['Waktu Generate', 'Kode Token', 'Tipe', 'Sekolah / Mitra', 'Status', 'Catatan']
        var expectedPrefix = (tokenType === 'EVENT') ? 'EVENT' : (tokenType === 'TEACHER_PREMIUM' ? 'GURU' : 'SISWA');
        for (var i = 1; i < data.length; i++) {
          var rowCode = String(data[i][1] || '').trim();
          var rowType = String(data[i][2] || '').trim().toUpperCase();
          var rowStatus = String(data[i][4] || '').trim().toUpperCase();
          var typeMatches = (rowType === tokenType.toUpperCase()) || (rowType.indexOf(expectedPrefix) !== -1) || (rowCode.indexOf(expectedPrefix) === 0);
          if (rowStatus === 'TERSEDIA' && typeMatches) {
            tokenCode = rowCode;
            // Update baris ini menjadi TERJUAL
            sheet.getRange(i + 1, 5).setValue('TERJUAL');
            sheet.getRange(i + 1, 6).setValue('Terjual Lynk.id Order: ' + orderId + ' (' + (customerEmail || customerName) + ')');
            break;
          }
        }
      }
    } catch (errSheet) {
      Logger.log('Catatan pencarian sheet: ' + errSheet);
    }
  }

  // 2. Jika tidak ada token yang tersedia di stok, auto-generate token baru (Zero Stockout Protection)
  if (!tokenCode) {
    isNewGenerated = true;
    var prefix = (tokenType === 'EVENT') ? 'EVENT' : (tokenType === 'TEACHER_PREMIUM' ? 'GURU' : 'SISWA');
    var chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var seg1 = '', seg2 = '';
    for (var j = 0; j < 4; j++) {
      seg1 += chars.charAt(Math.floor(Math.random() * chars.length));
      seg2 += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    tokenCode = prefix + '-' + seg1 + '-' + seg2;
  }

  // 3. Simpan atau update dokumen token di Firestore
  try {
    var accessToken = _getAccessToken();
    var docPath = 'projects/' + projectId + '/databases/(default)/documents/license_tokens/' + encodeURIComponent(tokenCode);
    var fieldsObj = {
      token: { stringValue: tokenCode },
      type: { stringValue: tokenType },
      school: { stringValue: 'Lynk.id Store' },
      is_used: { booleanValue: false },
      assigned_to: { stringValue: customerName || 'Pembeli Lynk.id' },
      assigned_email: { stringValue: customerEmail || '' },
      assigned_phone: { stringValue: customerPhone || '' },
      order_id: { stringValue: orderId },
      platform: { stringValue: 'lynk.id' },
      assigned_at: { timestampValue: new Date().toISOString() }
    };

    var commitUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents:commit';
    UrlFetchApp.fetch(commitUrl, {
      method: 'post',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + accessToken },
      payload: JSON.stringify({
        writes: [{
          update: {
            name: docPath,
            fields: fieldsObj
          }
        }]
      }),
      muteHttpExceptions: true
    });

    // Jika token baru, catat baris baru di sheet 'license_tokens'
    if (isNewGenerated && ss) {
      var licSheet = ss.getSheetByName('license_tokens');
      if (licSheet) {
        licSheet.appendRow([
          new Date(),
          tokenCode,
          tokenType,
          'Lynk.id Store',
          'TERJUAL',
          'Auto-Generated Webhook Order: ' + orderId + ' (' + (customerEmail || customerName) + ')'
        ]);
      }
    }
  } catch (errFirestore) {
    Logger.log('Gagal update Firestore: ' + errFirestore);
  }

  return tokenCode;
}

/**
 * Catat transaksi Lynk.id ke Sheet 'lynk_transactions'
 */
function _recordLynkTransaction(orderId, customerName, customerEmail, customerPhone, productTitle, quantity, grandTotal, tokenCode, status) {
  try {
    var ss = _getSpreadsheet();
    if (!ss) return;

    var sheet = ss.getSheetByName('lynk_transactions');
    if (!sheet) {
      sheet = ss.insertSheet('lynk_transactions');
      sheet.appendRow([
        'Waktu Transaksi',
        'Order ID (Ref ID)',
        'Nama Pembeli',
        'Email Pembeli',
        'No WhatsApp',
        'Produk',
        'Jumlah (Qty)',
        'Total Bayar',
        'Kode Token Diberikan',
        'Status Delivery'
      ]);
      sheet.getRange('A1:J1').setFontWeight('bold').setBackground('#e8f5e9');
      sheet.setFrozenRows(1);
    }

    sheet.appendRow([
      new Date(),
      orderId,
      customerName,
      customerEmail,
      customerPhone,
      productTitle,
      quantity,
      grandTotal,
      tokenCode,
      status || 'SUCCESS'
    ]);
  } catch (e) {
    Logger.log('Gagal mencatat transaksi ke lynk_transactions: ' + e);
  }
}

/**
 * Kirim email otomatis berisi Kode Token ke Pembeli via MailApp (Khusus Guru & Siswa)
 */
function _sendBuyerTokenEmail(customerEmail, customerName, orderId, tokenCode, productTitle) {
  if (!customerEmail || customerEmail.indexOf('@') === -1) {
    Logger.log('Email pembeli tidak tersedia atau format tidak valid: ' + customerEmail);
    return { success: false, error: 'Email invalid: ' + customerEmail };
  }

  var tokenStr = String(tokenCode || '').trim();
  var prodStr = String(productTitle || '').trim();
  var prodUpper = prodStr.toUpperCase();
  var isTeacher = (tokenStr.toUpperCase().indexOf('GURU') !== -1) ||
                  (prodUpper.indexOf('GURU') !== -1 || prodUpper.indexOf('TEACHER') !== -1 || prodUpper.indexOf('PROKTOR') !== -1 || prodUpper.indexOf('SEKOLAH') !== -1);
  var isEvent = (tokenStr.indexOf('EVENT-') === 0) || (prodUpper.indexOf('EVENT') !== -1 || prodUpper.indexOf('TIKET') !== -1);

  var appName = 'ExamGO';
  var copyUrl = 'https://examgo.id/salin?token=' + encodeURIComponent(tokenStr);
  var youtubeTutorialUrl = 'https://www.youtube.com/watch?v=GFUgdGcGHzY';
  var waAdminUrl = 'https://wa.me/6289693652230?text=' + encodeURIComponent('Halo Admin ExamGO, saya baru membeli lisensi ' + (isTeacher ? 'Guru' : 'Siswa') + ' dengan token ' + tokenStr + '. Mohon bantuan aktivasi/panduan.');

  var subject = '';
  var htmlBody = '';

  if (isTeacher) {
    subject = '🛡️ Lisensi Resmi Guru & Proktor ExamGO: [' + tokenStr + '] + Panduan Upload Soal';

    htmlBody = '<!DOCTYPE html>' +
      '<html>' +
      '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>' +
      '<body style="font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Helvetica, Arial, sans-serif; background-color: #f1f5f9; margin: 0; padding: 20px 12px; color: #1e293b;">' +
        '<div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 24px; overflow: hidden; border: 1px solid #cbd5e1; box-shadow: 0 10px 25px -5px rgba(0,0,0,0.08);">' +
          
          '<!-- Header Banner Guru -->' +
          '<div style="background: linear-gradient(135deg, #064e3b 0%, #047857 50%, #0d9488 100%); padding: 32px 24px; text-align: center; color: #ffffff;">' +
            '<div style="display: inline-block; background: rgba(255,255,255,0.18); border: 1px solid rgba(255,255,255,0.3); border-radius: 999px; padding: 4px 14px; font-size: 11px; font-weight: 800; letter-spacing: 1px; text-transform: uppercase; margin-bottom: 10px;">' +
              '🛡️ LISENSI RESMI GURU & PROKTOR' +
            '</div>' +
            '<div style="font-size: 28px; font-weight: 800; letter-spacing: -0.5px; line-height: 1.2;">ExamGO Mode Guru</div>' +
            '<div style="font-size: 13px; opacity: 0.95; margin-top: 6px; font-weight: 500;">Sistem CBT Anti-Curang & Rekap Nilai Ujian Sekolah Otomatis #1</div>' +
          '</div>' +

          '<div style="padding: 28px 24px;">' +
            '<h2 style="font-size: 18px; font-weight: 800; color: #0f172a; margin-top: 0; margin-bottom: 10px;">Halo, Bapak/Ibu ' + (customerName || 'Guru Berdedikasi') + '! 👨‍🏫👩‍🏫</h2>' +
            '<p style="font-size: 14px; line-height: 1.6; color: #475569; margin: 0 0 20px;">' +
              'Selamat! Pembelian <b>Lisensi Guru & Proktor Premium</b> melalui <b>Lynk.id</b> telah kami verifikasi dengan sukses. Sekarang Anda dapat menggelar ujian sekolah yang 100% bebas curang dengan koreksi nilai otomatis.' +
            '</p>' +

            '<!-- Ticket Box Lisensi Guru -->' +
            '<div style="background: #f0fdf4; border: 2px dashed #10b981; border-radius: 18px; padding: 22px 18px; text-align: center; margin: 24px 0;">' +
              '<div style="font-size: 11px; font-weight: 800; text-transform: uppercase; letter-spacing: 1.5px; color: #047857; margin-bottom: 8px;">KODE LISENSI RESMI GURU ANDA</div>' +
              '<div style="font-size: 28px; font-weight: 900; font-family: \'JetBrains Mono\', Consolas, Monaco, monospace; letter-spacing: 4px; color: #064e3b; user-select: all; -webkit-user-select: all; word-break: break-all; margin: 10px 0;">' +
                tokenStr +
              '</div>' +
              '<div style="margin-top: 14px;">' +
                '<a href="' + copyUrl + '" target="_blank" style="display: inline-block; background: #059669; color: #ffffff; text-decoration: none; font-size: 13px; font-weight: 800; padding: 12px 24px; border-radius: 12px; box-shadow: 0 4px 12px rgba(5, 150, 105, 0.35);">' +
                  '📋 Klik untuk Salin Token Otomatis' +
                '</a>' +
              '</div>' +
              '<div style="font-size: 11px; color: #059669; margin-top: 8px;">(Atau ketuk/blok langsung kode di atas untuk menyalin)</div>' +
              '<div style="border-top: 1px solid #bbf7d0; margin-top: 16px; padding-top: 12px; text-align: left; font-size: 12px; color: #166534; line-height: 1.7;">' +
                '<div>✓ <b>Akses Seumur Hidup (Lifetime)</b> — Tanpa biaya langganan bulanan</div>' +
                '<div>✓ <b>UNLIMITED Siswa & UNLIMITED Ujian</b> — Buat ujian kelas sebanyak-banyaknya</div>' +
                '<div>✓ <b>Kiosk Shield Anti-Curang</b> — Kunci layar HP siswa, blokir AI & split-screen</div>' +
                '<div>✓ <b>Rekap Nilai Excel & PDF</b> — Koreksi otomatis begitu siswa selesai ujian</div>' +
              '</div>' +
            '</div>' +

            '<!-- Video Panduan Upload Soal (YouTube) -->' +
            '<div style="background: #ffffff; border: 1px solid #cbd5e1; border-radius: 18px; overflow: hidden; margin: 28px 0; box-shadow: 0 4px 14px rgba(0,0,0,0.06);">' +
              '<div style="background: #0f172a; padding: 12px 18px; color: #ffffff; display: flex; align-items: center; justify-content: space-between;">' +
                '<span style="font-size: 12px; font-weight: 800; text-transform: uppercase; letter-spacing: 1px; color: #f87171;">📺 VIDEO PANDUAN RESMI</span>' +
                '<span style="font-size: 11px; color: #94a3b8; font-weight: 600;">YouTube • 4 Menit</span>' +
              '</div>' +
              '<a href="' + youtubeTutorialUrl + '" target="_blank" style="text-decoration: none; display: block; background: #000000; text-align: center;">' +
                '<div style="position: relative; max-height: 250px; overflow: hidden;">' +
                  '<img src="https://img.youtube.com/vi/GFUgdGcGHzY/hqdefault.jpg" alt="Panduan Upload Soal ExamGO" style="width: 100%; display: block; max-height: 250px; object-fit: cover; opacity: 0.9;" />' +
                '</div>' +
              '</a>' +
              '<div style="padding: 18px 20px; background: #f8fafc; border-top: 1px solid #e2e8f0;">' +
                '<div style="font-size: 15px; font-weight: 800; color: #0f172a; margin-bottom: 6px;">' +
                  'Tutorial: Cara Cepat Buat & Upload Soal CBT ExamGO' +
                '</div>' +
                '<div style="font-size: 13px; color: #475569; line-height: 1.6; margin-bottom: 14px;">' +
                  'Tonton panduan langkah demi langkah cara import soal dari dokumen Word (.docx) atau Google Form, membuat QR Code ujian kelas, dan merekap nilai otomatis.' +
                '</div>' +
                '<a href="' + youtubeTutorialUrl + '" target="_blank" style="display: inline-block; background: #dc2626; color: #ffffff; text-decoration: none; font-size: 13px; font-weight: 800; padding: 10px 20px; border-radius: 10px; box-shadow: 0 4px 10px rgba(220, 38, 38, 0.3);">' +
                  '▶ Tonton Panduan di YouTube' +
                '</a>' +
              '</div>' +
            '</div>' +

            '<!-- Panduan Langkah Aktivasi -->' +
            '<div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 16px; padding: 20px; margin-bottom: 24px;">' +
              '<div style="font-size: 14px; font-weight: 800; color: #0f172a; margin-bottom: 12px;">🚀 4 Langkah Mudah Memulai Ujian:</div>' +
              '<table style="width: 100%; border-collapse: collapse; font-size: 13px; color: #334155; line-height: 1.6;">' +
                '<tr>' +
                  '<td style="vertical-align: top; padding: 6px 10px 6px 0; font-weight: 800; color: #059669;">1.</td>' +
                  '<td style="vertical-align: top; padding: 6px 0;">Buka aplikasi <b>ExamGO</b> di ponsel Android/iPhone atau tablet Anda.</td>' +
                '</tr>' +
                '<tr>' +
                  '<td style="vertical-align: top; padding: 6px 10px 6px 0; font-weight: 800; color: #059669;">2.</td>' +
                  '<td style="vertical-align: top; padding: 6px 0;">Pada halaman depan, ketuk menu <b>"Mode Guru / Proktor"</b> lalu pilih <b>"Aktivasi Lisensi Guru"</b>.</td>' +
                '</tr>' +
                '<tr>' +
                  '<td style="vertical-align: top; padding: 6px 10px 6px 0; font-weight: 800; color: #059669;">3.</td>' +
                  '<td style="vertical-align: top; padding: 6px 0;">Tempelkan (paste) <b>Kode Lisensi</b> di atas dan tekan <b>Aktivasi</b>. Akun Anda langsung aktif selamanya!</td>' +
                '</tr>' +
                '<tr>' +
                  '<td style="vertical-align: top; padding: 6px 10px 6px 0; font-weight: 800; color: #059669;">4.</td>' +
                  '<td style="vertical-align: top; padding: 6px 0;">Buat sesi ujian, import bank soal sesuai panduan YouTube di atas, dan tampilkan QR Code ke siswa!</td>' +
                '</tr>' +
              '</table>' +
            '</div>' +

            '<!-- Rincian Pesanan -->' +
            '<table style="width: 100%; font-size: 12px; border-collapse: collapse; margin-bottom: 24px; color: #64748b; background: #fafafa; border: 1px solid #f1f5f9; border-radius: 12px; padding: 12px;">' +
              '<tr><td style="padding: 6px 12px;">Order Reference:</td><td style="padding: 6px 12px; text-align: right; font-weight: 700; color: #0f172a;">' + orderId + '</td></tr>' +
              '<tr><td style="padding: 6px 12px;">Paket Produk:</td><td style="padding: 6px 12px; text-align: right; font-weight: 700; color: #059669;">' + (productTitle || 'Lisensi Guru & Proktor Premium') + '</td></tr>' +
              '<tr><td style="padding: 6px 12px;">Waktu Transaksi:</td><td style="padding: 6px 12px; text-align: right; font-weight: 600; color: #0f172a;">' + new Date().toLocaleString('id-ID') + '</td></tr>' +
            '</table>' +

            '<!-- Tombol Download & Bantuan -->' +
            '<div style="text-align: center; padding-top: 14px; border-top: 1px solid #e2e8f0;">' +
              '<div style="font-size: 12px; font-weight: 700; color: #475569; margin-bottom: 12px;">Unduh Aplikasi ExamGO:</div>' +
              '<a href="https://play.google.com/store/apps/details?id=com.kemenag.examgo" style="display: inline-block; background: #059669; color: #ffffff; text-decoration: none; font-size: 12px; font-weight: 700; padding: 10px 18px; border-radius: 10px; margin: 4px;">▶ Google Play Store</a> ' +
              '<a href="https://apps.apple.com/id/app/examgo/id6759708435" style="display: inline-block; background: #0f172a; color: #ffffff; text-decoration: none; font-size: 12px; font-weight: 700; padding: 10px 18px; border-radius: 10px; margin: 4px;">🍎 Apple App Store</a>' +
              '<div style="margin-top: 16px;">' +
                '<a href="' + waAdminUrl + '" target="_blank" style="display: inline-block; background: #25d366; color: #ffffff; text-decoration: none; font-size: 12px; font-weight: 800; padding: 8px 16px; border-radius: 8px;">💬 Bantuan Setup via WhatsApp</a>' +
              '</div>' +
            '</div>' +

          '</div>' +

          '<!-- Footer -->' +
          '<div style="background: #f8fafc; padding: 18px 24px; text-align: center; font-size: 11px; color: #94a3b8; border-top: 1px solid #e2e8f0; line-height: 1.5;">' +
            '<b>ExamGO</b> &bull; Platform Tryout CBT & Asesmen Ujian Sekolah Terkunci #1 &bull; <a href="https://examgo.id" style="color: #059669; text-decoration: none;">examgo.id</a>' +
          '</div>' +

        '</div>' +
      '</body>' +
      '</html>';

  } else {
    // Siswa & Event Email
    subject = isEvent
      ? ('🎟️ Tiket Event Tryout Akbar ExamGO: [' + tokenStr + ']')
      : ('🎉 Lisensi Siswa Premium ExamGO: [' + tokenStr + ']');

    htmlBody = '<!DOCTYPE html>' +
      '<html>' +
      '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>' +
      '<body style="font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Helvetica, Arial, sans-serif; background-color: #f8fafc; margin: 0; padding: 20px 12px; color: #1e293b;">' +
        '<div style="max-width: 580px; margin: 0 auto; background: #ffffff; border-radius: 24px; overflow: hidden; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">' +
          
          '<div style="background: linear-gradient(135deg, #059669 0%, #10b981 100%); padding: 30px 24px; text-align: center; color: #ffffff;">' +
            '<div style="font-size: 26px; font-weight: 800; letter-spacing: 0.5px;">ExamGO</div>' +
            '<div style="font-size: 13px; opacity: 0.95; margin-top: 4px;">Platform Tryout SNBT, SKD CPNS & Kedinasan 2026 #1</div>' +
          '</div>' +

          '<div style="padding: 28px 24px;">' +
            '<h2 style="font-size: 18px; font-weight: 700; color: #0f172a; margin-top: 0;">Halo, ' + (customerName || 'Sobat Pejuang Kampus') + '! 👋</h2>' +
            '<p style="font-size: 14px; line-height: 1.6; color: #475569;">' +
              'Terima kasih telah melakukan pembelian melalui <b>Lynk.id</b>. Pembayaran Anda untuk <b>' + (productTitle || 'Lisensi Akses Siswa ExamGO') + '</b> telah kami verifikasi dengan sukses.' +
            '</p>' +

            '<div style="background: #f0fdf4; border: 2px dashed #10b981; border-radius: 18px; padding: 22px; text-align: center; margin: 24px 0;">' +
              '<div style="font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; color: #166534; margin-bottom: 8px;">KODE LISENSI RESMI ANDA</div>' +
              '<div style="font-size: 28px; font-weight: 900; font-family: \'JetBrains Mono\', monospace; letter-spacing: 3px; color: #064e3b; user-select: all; -webkit-user-select: all; word-break: break-all; margin: 10px 0;">' + tokenStr + '</div>' +
              '<div style="margin-top: 14px;">' +
                '<a href="' + copyUrl + '" target="_blank" style="display: inline-block; background: #059669; color: #ffffff; text-decoration: none; font-size: 13px; font-weight: 800; padding: 12px 24px; border-radius: 12px; box-shadow: 0 4px 12px rgba(5, 150, 105, 0.35);">' +
                  '📋 Klik untuk Salin Token Otomatis' +
                '</a>' +
              '</div>' +
              '<div style="font-size: 11px; color: #15803d; margin-top: 8px;">(Salin kode di atas untuk aktivasi di aplikasi)</div>' +
            '</div>' +

            '<div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 14px; padding: 18px; margin-bottom: 24px;">' +
              '<div style="font-size: 13px; font-weight: 700; color: #0f172a; margin-bottom: 10px;">📋 Cara Aktivasi Token di Aplikasi ExamGO:</div>' +
              '<ol style="margin: 0; padding-left: 20px; font-size: 13px; line-height: 1.7; color: #334155;">' +
                '<li>Buka aplikasi <b>ExamGO</b> di ponsel Android atau iPhone Anda.</li>' +
                '<li>Pada Beranda Utama, ketuk menu <b>"Lisensi & Status Akun"</b> atau kartu Tryout.</li>' +
                '<li>Masukkan <b>Kode Lisensi</b> di atas pada kolom yang tersedia.</li>' +
                '<li>Tekan tombol <b>"Aktivasi Sekarang"</b>. Seluruh bank soal & tryout langsung terbuka selamanya!</li>' +
              '</ol>' +
            '</div>' +

            '<!-- Video Panduan YouTube -->' +
            '<div style="background: #ffffff; border: 1px solid #e2e8f0; border-radius: 14px; overflow: hidden; margin-bottom: 24px;">' +
              '<div style="background: #0f172a; padding: 10px 16px; color: #ffffff;">' +
                '<span style="font-size: 11px; font-weight: 800; text-transform: uppercase; letter-spacing: 1px; color: #f87171;">📺 VIDEO PANDUAN RESMI</span>' +
              '</div>' +
              '<a href="' + youtubeTutorialUrl + '" target="_blank" style="text-decoration: none; display: block; background: #000000; text-align: center;">' +
                '<img src="https://img.youtube.com/vi/GFUgdGcGHzY/hqdefault.jpg" alt="Panduan ExamGO" style="width: 100%; display: block; max-height: 220px; object-fit: cover; opacity: 0.95;" />' +
              '</a>' +
              '<div style="padding: 14px 16px; background: #f8fafc; border-top: 1px solid #e2e8f0;">' +
                '<div style="font-size: 14px; font-weight: 800; color: #0f172a; margin-bottom: 6px;">Tutorial: Panduan Lengkap Aplikasi ExamGO</div>' +
                '<div style="font-size: 12px; color: #475569; line-height: 1.5; margin-bottom: 10px;">Tonton panduan langkah demi langkah cara aktivasi lisensi dan penggunaan fitur ExamGO.</div>' +
                '<a href="' + youtubeTutorialUrl + '" target="_blank" style="display: inline-block; background: #dc2626; color: #ffffff; text-decoration: none; font-size: 12px; font-weight: 800; padding: 8px 16px; border-radius: 8px;">▶ Tonton Panduan di YouTube</a>' +
              '</div>' +
            '</div>' +

            '<table style="width: 100%; font-size: 12px; border-collapse: collapse; margin-bottom: 24px; color: #64748b;">' +
              '<tr><td style="padding: 6px 0;">Order Reference:</td><td style="padding: 6px 0; text-align: right; font-weight: 600; color: #0f172a;">' + orderId + '</td></tr>' +
              '<tr><td style="padding: 6px 0;">Waktu Transaksi:</td><td style="padding: 6px 0; text-align: right; font-weight: 600; color: #0f172a;">' + new Date().toLocaleString('id-ID') + '</td></tr>' +
            '</table>' +

            '<div style="text-align: center; padding-top: 10px; border-top: 1px solid #e2e8f0;">' +
              '<div style="font-size: 12px; font-weight: 600; color: #64748b; margin-bottom: 12px;">Unduh aplikasi ExamGO di ponsel Anda:</div>' +
              '<a href="https://play.google.com/store/apps/details?id=com.kemenag.examgo" style="display: inline-block; background: #059669; color: #ffffff; text-decoration: none; font-size: 12px; font-weight: 700; padding: 10px 18px; border-radius: 10px; margin: 4px;">Google Play Store</a> ' +
              '<a href="https://apps.apple.com/id/app/examgo/id6759708435" style="display: inline-block; background: #0f172a; color: #ffffff; text-decoration: none; font-size: 12px; font-weight: 700; padding: 10px 18px; border-radius: 10px; margin: 4px;">Apple App Store</a>' +
            '</div>' +

          '</div>' +

          '<div style="background: #f1f5f9; padding: 16px 24px; text-align: center; font-size: 11px; color: #94a3b8;">' +
            'ExamGO &bull; Official Digital Learning & Assessment System &bull; Butuh bantuan? Hubungi Admin via WhatsApp: 0896-9365-2230' +
          '</div>' +

        '</div>' +
      '</body>' +
      '</html>';
  }

  try {
    MailApp.sendEmail({
      to: customerEmail,
      subject: subject,
      htmlBody: htmlBody
    });
    Logger.log('✅ Email delivery sukses terkirim ke: ' + customerEmail);
    return { success: true };
  } catch (errMail) {
    Logger.log('⚠️ Gagal mengirim email via MailApp: ' + errMail);
    try {
      if (typeof GmailApp !== 'undefined') {
        GmailApp.sendEmail(customerEmail, subject, '', { htmlBody: htmlBody });
        Logger.log('✅ Email delivery sukses via GmailApp ke: ' + customerEmail);
        return { success: true };
      }
    } catch (errGmail) {
      Logger.log('⚠️ Gagal via GmailApp: ' + errGmail);
    }
    return { success: false, error: String(errMail) };
  }
}

/**
 * Render halaman Salin Token Otomatis untuk link copy di email
 */
function _renderCopyTokenHtmlOutput(token) {
  var cleanToken = String(token || '').trim().replace(/[^A-Za-z0-9_-]/g, '').substring(0, 32);
  var html = '<!DOCTYPE html>' +
    '<html lang="id">' +
    '<head>' +
      '<meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">' +
      '<title>Salin Token Lisensi ExamGO</title>' +
      '<link rel="preconnect" href="https://fonts.googleapis.com">' +
      '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' +
      '<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;700;800&family=JetBrains+Mono:wght@700;800&display=swap" rel="stylesheet">' +
      '<style>' +
        '* { box-sizing: border-box; }' +
        'body {' +
          'margin: 0; padding: 20px; font-family: \'Plus Jakarta Sans\', sans-serif;' +
          'background: radial-gradient(circle at 50% 20%, #064e3b 0%, #022c22 40%, #090d16 100%);' +
          'color: #f8fafc; min-height: 100vh; display: flex; align-items: center; justify-content: center;' +
        '}' +
        '.card {' +
          'background: rgba(15, 23, 42, 0.95); border: 1px solid rgba(16, 185, 129, 0.35);' +
          'border-radius: 24px; padding: 32px 24px; max-width: 440px; width: 100%;' +
          'text-align: center; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.6);' +
        '}' +
        '.badge {' +
          'display: inline-block; background: rgba(16, 185, 129, 0.15); border: 1px solid rgba(16, 185, 129, 0.4);' +
          'color: #34d399; font-size: 11px; font-weight: 800; text-transform: uppercase;' +
          'letter-spacing: 1px; padding: 5px 14px; border-radius: 999px; margin-bottom: 16px;' +
        '}' +
        '.token-box {' +
          'background: #022c22; border: 2px dashed #10b981; border-radius: 14px;' +
          'padding: 16px; font-family: \'JetBrains Mono\', monospace; font-size: 24px;' +
          'font-weight: 800; letter-spacing: 3px; color: #6ee7b7; margin: 18px 0;' +
          'user-select: all; -webkit-user-select: all; word-break: break-all;' +
        '}' +
        '.btn-primary {' +
          'display: block; width: 100%; background: linear-gradient(135deg, #10b981 0%, #059669 100%);' +
          'color: #ffffff; text-decoration: none; font-weight: 800; font-size: 14px;' +
          'padding: 14px; border-radius: 14px; box-shadow: 0 10px 15px -3px rgba(16, 185, 129, 0.3);' +
          'margin-bottom: 10px;' +
        '}' +
        '.btn-secondary {' +
          'display: block; width: 100%; background: #1e293b; color: #cbd5e1;' +
          'text-decoration: none; font-weight: 700; font-size: 13px;' +
          'padding: 12px; border-radius: 14px; border: 1px solid #334155; margin-bottom: 10px;' +
        '}' +
        '.status-copied { color: #34d399; font-size: 13px; font-weight: 700; margin-top: 8px; }' +
      '</style>' +
    '</head>' +
    '<body>' +
      '<div class="card">' +
        '<div class="badge">LISENSI RESMI EXAMGO</div>' +
        '<h1 style="margin: 0 0 6px; font-size: 22px; font-weight: 800; color: #ffffff;">Token Berhasil Disalin!</h1>' +
        '<p style="margin: 0; font-size: 13px; color: #94a3b8; line-height: 1.5;">Kode token Anda telah otomatis tersalin ke clipboard perangkat Anda:</p>' +
        '<div class="token-box" id="token-display">' + (cleanToken || 'TOKEN-EXAMGO') + '</div>' +
        '<div id="copy-status" class="status-copied">✅ Siap ditempel (paste) di aplikasi ExamGO</div>' +
        '<div style="margin-top: 24px;">' +
          '<a href="https://play.google.com/store/apps/details?id=com.kemenag.examgo" class="btn-primary">🚀 Buka / Download di Play Store</a>' +
          '<a href="https://apps.apple.com/id/app/examgo/id6759708435" class="btn-secondary">🍎 Unduh di Apple App Store</a>' +
          '<a href="https://youtu.be/GFUgdGcGHzY" target="_blank" class="btn-secondary" style="border-color: #ef4444; color: #fca5a5;">📺 Tonton Tutorial Upload Soal (YouTube)</a>' +
        '</div>' +
      '</div>' +
      '<script>' +
        'var t = "' + cleanToken + '";' +
        'if (t && navigator.clipboard && navigator.clipboard.writeText) {' +
          'navigator.clipboard.writeText(t).then(function() {' +
            'var el = document.getElementById("copy-status");' +
            'if (el) el.innerText = "✅ Berhasil disalin ke clipboard!";' +
          '}).catch(function() {});' +
        '}' +
      '</script>' +
    '</body>' +
    '</html>';

  return HtmlService.createHtmlOutput(html)
    .setTitle('Salin Token ExamGO')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

/**
 * Mengambil histori transaksi Lynk.id Webhook dari Sheet 'lynk_transactions' untuk Admin WebGAS
 */
function getLynkTransactions(username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  try {
    var props = PropertiesService.getScriptProperties();
    var ssId = props.getProperty('SPREADSHEET_ID');
    var ss = ssId ? SpreadsheetApp.openById(ssId) : SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) return { error: 'Spreadsheet tidak ditemukan' };

    var sheet = ss.getSheetByName('lynk_transactions');
    if (!sheet) {
      sheet = ss.insertSheet('lynk_transactions');
      sheet.appendRow([
        'Waktu Transaksi',
        'Order ID (Ref ID)',
        'Nama Pembeli',
        'Email Pembeli',
        'No WhatsApp',
        'Produk',
        'Jumlah (Qty)',
        'Total Bayar',
        'Kode Token Diberikan',
        'Status Delivery'
      ]);
      sheet.getRange('A1:J1').setFontWeight('bold').setBackground('#e8f5e9');
      sheet.setFrozenRows(1);
    }

    // Auto-sync / recovery: jika lynk_transactions kosong tapi ada token lynk di license_tokens
    if (sheet.getLastRow() <= 1) {
      var licSheet = ss.getSheetByName('license_tokens');
      if (licSheet && licSheet.getLastRow() > 1) {
        var licData = licSheet.getDataRange().getValues();
        for (var k = 1; k < licData.length; k++) {
          var school = String(licData[k][3] || '');
          var notes = String(licData[k][5] || '');
          if (school.indexOf('Lynk') !== -1 || notes.indexOf('Auto-Generated Webhook Order:') !== -1) {
            var oMatch = notes.match(/Order:\s*([^\s(]+)/);
            var oId = oMatch ? oMatch[1] : ('LYNK-' + k);
            var eMatch = notes.match(/\(([^)]+)\)/);
            var bEmail = eMatch ? eMatch[1] : '';
            sheet.appendRow([
              licData[k][0] || new Date(),
              oId,
              'Pembeli Lynk.id',
              bEmail,
              '',
              'Token Siswa Premium ExamGO',
              1,
              0,
              licData[k][1],
              'SUCCESS'
            ]);
          }
        }
      }
    }

    if (sheet.getLastRow() <= 1) {
      return { success: true, transactions: [] };
    }

    var data = sheet.getDataRange().getValues();
    var list = [];
    for (var i = 1; i < data.length; i++) {
      var rawTs = data[i][0];
      var tsStr = '';
      if (rawTs instanceof Date) {
        tsStr = rawTs.toISOString();
      } else if (rawTs) {
        tsStr = String(rawTs);
      }

      list.push({
        timestamp: tsStr,
        orderId: String(data[i][1] || '').trim(),
        customerName: String(data[i][2] || '').trim(),
        customerEmail: String(data[i][3] || '').trim(),
        customerPhone: String(data[i][4] || '').trim(),
        productTitle: String(data[i][5] || '').trim(),
        quantity: Number(data[i][6] || 1),
        grandTotal: Number(data[i][7] || 0),
        token: String(data[i][8] || '').trim(),
        status: String(data[i][9] || 'SUCCESS').trim()
      });
    }

    list.reverse();
    return { success: true, transactions: list };
  } catch (e) {
    return { error: e.message };
  }
}

/**
 * Kirim ulang email token ke pembeli untuk transaksi tertentu
 */
function resendBuyerTokenEmail(username, password, orderId) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!orderId) return { error: 'Order ID wajib diisi' };

  try {
    var props = PropertiesService.getScriptProperties();
    var ssId = props.getProperty('SPREADSHEET_ID');
    var ss = ssId ? SpreadsheetApp.openById(ssId) : SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) return { error: 'Spreadsheet tidak ditemukan' };

    var sheet = ss.getSheetByName('lynk_transactions');
    if (!sheet) return { error: 'Sheet lynk_transactions tidak ditemukan' };

    var data = sheet.getDataRange().getValues();
    for (var i = 1; i < data.length; i++) {
      if (String(data[i][1]).trim() === String(orderId).trim()) {
        var customerName = data[i][2];
        var customerEmail = data[i][3];
        var productTitle = data[i][5];
        var token = data[i][8];

        var res = _sendBuyerTokenEmail(customerEmail, customerName, orderId, token, productTitle);
        if (res.success) {
          sheet.getRange(i + 1, 10).setValue('SUCCESS_EMAILED');
          return { success: true, message: 'Email token berhasil dikirim ke ' + customerEmail };
        } else {
          return { error: 'Gagal mengirim email ke ' + customerEmail + ': ' + (res.error || 'Pastikan izin MailApp aktif.') };
        }
      }
    }
    return { error: 'Order ID tidak ditemukan di histori transaksi' };
  } catch (e) {
    return { error: e.message };
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
 * Mengambil hasil pengerjaan peserta event tryout dari koleksi Firestore 'jawaban_tryout'
 * Khusus untuk tryout berjenis EVENT (SKD, SNBT, TKA, UMUM)
 */
function getEventTryoutResults(username, password, eventId) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var cleanEventId = (eventId || '').trim();
  if (!cleanEventId) return { error: 'Event ID wajib diisi.' };

  try {
    var accessToken = _getAccessToken();
    var headers = {
      Authorization: 'Bearer ' + accessToken,
      'Content-Type': 'application/json',
      'Cache-Control': 'no-cache'
    };

    // 1. Ambil detail paket_tryout untuk metadata event (nama_paket, jenis_test/kategori)
    var pkgUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/paket_tryout/' + encodeURIComponent(cleanEventId);
    var pkgResp = UrlFetchApp.fetch(pkgUrl, { method: 'get', headers: headers, muteHttpExceptions: true });
    var eventMeta = { id: cleanEventId, nama: 'Event Tryout', kategori: 'UMUM' };
    if (pkgResp.getResponseCode() === 200) {
      var pJson = JSON.parse(pkgResp.getContentText());
      var pf = pJson.fields || {};
      eventMeta.nama = (pf.nama_paket && pf.nama_paket.stringValue) || cleanEventId;
      eventMeta.kategori = (pf.jenis_test && pf.jenis_test.stringValue) || (pf.kategori && pf.kategori.stringValue) || 'UMUM';
    }

    // 2. Query jawaban_tryout yang token == cleanEventId
    var queryUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents:runQuery';
    var qPayload = {
      structuredQuery: {
        from: [{ collectionId: 'jawaban_tryout' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'token' },
            op: 'EQUAL',
            value: { stringValue: cleanEventId }
          }
        }
      }
    };

    var qResp = UrlFetchApp.fetch(queryUrl, {
      method: 'post',
      headers: headers,
      contentType: 'application/json',
      payload: JSON.stringify(qPayload),
      muteHttpExceptions: true
    });

    var results = [];
    if (qResp.getResponseCode() === 200) {
      var rawResults = JSON.parse(qResp.getContentText());
      if (Array.isArray(rawResults)) {
        rawResults.forEach(function(item) {
          if (item.document && item.document.fields) {
            var f = item.document.fields;
            var docId = item.document.name ? item.document.name.split('/').pop() : '';
            var nama = (f.nama_peserta && f.nama_peserta.stringValue) || 'Peserta';
            var nis = (f.nis && f.nis.stringValue) || (docId ? docId.split('_')[0] : '-');
            var email = (f.email && f.email.stringValue) || '-';
            var noWa = (f.no_wa && f.no_wa.stringValue) || '-';
            var kategori = (f.kategori && f.kategori.stringValue) || eventMeta.kategori;
            var skor = (f.skor_akhir && f.skor_akhir.integerValue !== undefined) ? parseInt(f.skor_akhir.integerValue) : ((f.skor_akhir && f.skor_akhir.doubleValue) ? Math.round(f.skor_akhir.doubleValue) : 0);
            var maxSkor = (f.max_skor && f.max_skor.integerValue !== undefined) ? parseInt(f.max_skor.integerValue) : 1000;
            var benar = (f.jumlah_benar && f.jumlah_benar.integerValue !== undefined) ? parseInt(f.jumlah_benar.integerValue) : 0;
            var salah = (f.jumlah_salah && f.jumlah_salah.integerValue !== undefined) ? parseInt(f.jumlah_salah.integerValue) : 0;
            var kosong = (f.jumlah_kosong && f.jumlah_kosong.integerValue !== undefined) ? parseInt(f.jumlah_kosong.integerValue) : 0;
            var totalSoal = (f.total_soal && f.total_soal.integerValue !== undefined) ? parseInt(f.total_soal.integerValue) : (benar + salah + kosong);
            var isPassed = (f.is_passed && f.is_passed.booleanValue === true);
            var status = (f.status_kelulusan && f.status_kelulusan.stringValue) || (isPassed ? 'LULUS PG' : 'BELUM LULUS');
            var predikat = (f.predikat && f.predikat.stringValue) || '-';
            var submittedAt = (f.submitted_at && f.submitted_at.timestampValue) ? f.submitted_at.timestampValue : item.document.createTime;

            results.push({
              id: docId,
              nama: nama,
              nis: nis,
              email: email,
              noWa: noWa,
              kategori: kategori,
              skor: skor,
              maxSkor: maxSkor,
              benar: benar,
              salah: salah,
              kosong: kosong,
              totalSoal: totalSoal,
              isPassed: isPassed,
              status: status,
              predikat: predikat,
              submittedAt: submittedAt
            });
          }
        });
      }
    }

    // Sort peringkat descending berdasarkan skor
    results.sort(function(a, b) {
      if (b.skor !== a.skor) return b.skor - a.skor;
      return new Date(a.submittedAt) - new Date(b.submittedAt);
    });

    // Tambahkan rank
    for (var r = 0; r < results.length; r++) {
      results[r].rank = r + 1;
    }

    // Statistik agregat
    var totalPeserta = results.length;
    var totalSkor = 0;
    var maxSkorFound = 0;
    var lulusCount = 0;
    results.forEach(function(item) {
      totalSkor += item.skor;
      if (item.skor > maxSkorFound) maxSkorFound = item.skor;
      if (item.isPassed) lulusCount++;
    });
    var avgSkor = totalPeserta > 0 ? Math.round(totalSkor / totalPeserta) : 0;

    return {
      success: true,
      event: eventMeta,
      stats: {
        totalPeserta: totalPeserta,
        avgSkor: avgSkor,
        highestSkor: maxSkorFound,
        lulusCount: lulusCount
      },
      results: results
    };
  } catch (err) {
    return { error: 'Gagal mengambil hasil tryout event: ' + err.message };
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

// ═══════════════════════════════════════════════════════════════════
// EXECUTIVE ADMIN DASHBOARD SUMMARY ENDPOINT
// ═══════════════════════════════════════════════════════════════════

/**
 * Mengambil ringkasan komprehensif seluruh metrik untuk Dashboard Eksekutif Admin
 */
function getAdminDashboardSummary(username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var result = {
    success: true,
    server_time: new Date().toISOString(),
    exams: { total: 0 },
    tryout: { total: 0, active: 0, draft: 0, total_soal: 0, categories: { SNBT: 0, SKD: 0, TKA: 0, UMUM: 0 }, recent: [] },
    licenses: { total: 0, used: 0, available: 0 },
    partners: { total: 0, schools: [] },
    cloud_status: {
      firestore: 'online',
      drive: 'online',
      fcm: props.getProperty('SA_EMAIL') ? 'online' : 'not_configured'
    }
  };

  try {
    var accessToken = _getAccessToken();
    var headers = { Authorization: 'Bearer ' + accessToken, 'Cache-Control': 'no-cache' };

    // 1. Fetch Paket Tryout
    var tryoutUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/paket_tryout?pageSize=200';
    var tryoutResp = UrlFetchApp.fetch(tryoutUrl, { method: 'get', headers: headers, muteHttpExceptions: true });
    if (tryoutResp.getResponseCode() === 200) {
      var tData = JSON.parse(tryoutResp.getContentText());
      var tDocs = tData.documents || [];
      result.tryout.total = tDocs.length;
      
      var recents = [];
      tDocs.forEach(function(d) {
        var f = d.fields || {};
        var docId = d.name.split('/').pop();
        var st = (f.status && f.status.stringValue) || 'aktif';
        if (st === 'aktif') result.tryout.active++;
        else result.tryout.draft++;

        var cat = (f.jenis_test && f.jenis_test.stringValue) || 'SNBT';
        if (!result.tryout.categories[cat]) result.tryout.categories[cat] = 0;
        result.tryout.categories[cat]++;

        var soalCount = parseInt((f.total_soal && f.total_soal.integerValue) || '0', 10);
        result.tryout.total_soal += soalCount;

        recents.push({
          paket_id: (f.paket_id && f.paket_id.stringValue) || docId,
          nama_paket: (f.nama_paket && f.nama_paket.stringValue) || '',
          jenis_test: cat,
          jenis_waktu: (f.jenis_waktu && f.jenis_waktu.stringValue) || 'per_subtest',
          durasi_menit: parseInt((f.durasi_menit && f.durasi_menit.integerValue) || '120', 10),
          total_soal: soalCount,
          status: st,
          is_lifetime: f.is_lifetime ? (f.is_lifetime.booleanValue === true) : false,
          tanggal: (f.tanggal && f.tanggal.stringValue) || '',
          jam_mulai: (f.jam_mulai && f.jam_mulai.stringValue) || '08:00',
          jam_selesai: (f.jam_selesai && f.jam_selesai.stringValue) || '23:59'
        });
      });
      result.tryout.recent = recents.slice(0, 5);
    }

    // 2. Fetch License Tokens
    var licUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/license_tokens?pageSize=500';
    var licResp = UrlFetchApp.fetch(licUrl, { method: 'get', headers: headers, muteHttpExceptions: true });
    if (licResp.getResponseCode() === 200) {
      var lData = JSON.parse(licResp.getContentText());
      var lDocs = lData.documents || [];
      result.licenses.total = lDocs.length;
      lDocs.forEach(function(d) {
        var f = d.fields || {};
        var isUsed = f.is_used ? (f.is_used.booleanValue === true) : false;
        if (isUsed) result.licenses.used++;
        else result.licenses.available++;
      });
    }

    // 3. Fetch Partner Schools
    var partUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/partner_schools?pageSize=100';
    var partResp = UrlFetchApp.fetch(partUrl, { method: 'get', headers: headers, muteHttpExceptions: true });
    if (partResp.getResponseCode() === 200) {
      var pData = JSON.parse(partResp.getContentText());
      var pDocs = pData.documents || [];
      result.partners.total = pDocs.length;
      pDocs.forEach(function(d) {
        var f = d.fields || {};
        result.partners.schools.push({
          name: (f.name && f.name.stringValue) || '',
          code: (f.code && f.code.stringValue) || '',
          count: parseInt((f.count && f.count.integerValue) || '0', 10)
        });
      });
    }

    // 4. Fetch Exam Sessions
    var examUrl = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/exam_sessions?pageSize=200';
    var examResp = UrlFetchApp.fetch(examUrl, { method: 'get', headers: headers, muteHttpExceptions: true });
    if (examResp.getResponseCode() === 200) {
      var eData = JSON.parse(examResp.getContentText());
      result.exams.total = (eData.documents || []).length;
    }

    return result;
  } catch(e) {
    return { error: e.message };
  }
}

// ═══════════════════════════════════════════════════════════════════
// LANDING PAGE SETTINGS & PROMO ENDPOINTS
// ═══════════════════════════════════════════════════════════════════

/**
 * Mengambil konfigurasi konten Landing Page dari Firestore
 */
function getLandingPageSettings() {
  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  
  var defaultSettings = {
    hero_badge: '🔥 SIMULASI ASLI UTBK SNBT & SKD BKN 2026',
    hero_title: 'Raih Kampus Impian & Kedinasan 2026 Tanpa Panik Waktu Habis!',
    hero_subtitle: 'Aplikasi Ujian CBT Terkunci #1 di Indonesia. Simulasi persis sistem resmi SNPMB & BKN: timer mandiri per-subtes, rumus matematika KaTeX tajam, pembahasan tuntas, dan bebas joki.',
    featured_event_title: 'Tryout Akbar UTBK SNBT 2026 Gelombang 1',
    featured_event_desc: '7 Subtest Lengkap (Penalaran Umum, PPU, PBM, PK, Literasi Indo, Literasi Inggris, PM). Penilaian skala UTBK & pembahasan mendalam.',
    featured_event_date: 'Sabtu - Minggu, 15 - 16 November 2026',
    promo_price_original: 'Rp 50.000',
    promo_price_discount: 'Rp 19.000',
    promo_tag: 'Diskon 62% Khusus Siswa!',
    lynkid_url: 'https://lynk.id/examgo',
    playstore_url: 'https://play.google.com/store/apps/details?id=com.kemenag.examgo&hl=id',
    appstore_url: 'https://apps.apple.com/id/app/examgo/id6759708435?l=id',
    download_apk_url: 'https://github.com/ekiq11/Exam-Go/releases/latest',
    whatsapp_number: '6289693652230',
    whatsapp_message: 'Halo Admin ExamGO, saya ingin membeli token tryout / konsultasi paket ujian',
    price_siswa: 'Rp 25.000',
    price_guru: 'Rp 35.000',
    lynkid_siswa_url: 'https://lynk.id/examgo',
    lynkid_guru_url: 'https://lynk.id/examgo',
    announcement_text: '⚡ Beli sekarang hanya Rp.49000 akses seumur hidup, khusus 1000 peserta',
    is_announcement_active: true,
    is_featured_event_active: true
  };

  if (!projectId) return defaultSettings;

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/app_settings/landing_page';
  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + accessToken, 'Cache-Control': 'no-cache' },
      muteHttpExceptions: true
    });

    if (resp.getResponseCode() === 200) {
      var data = JSON.parse(resp.getContentText());
      var f = data.fields || {};
      return {
        hero_badge: (f.hero_badge && f.hero_badge.stringValue) || defaultSettings.hero_badge,
        hero_title: (f.hero_title && f.hero_title.stringValue) || defaultSettings.hero_title,
        hero_subtitle: (f.hero_subtitle && f.hero_subtitle.stringValue) || defaultSettings.hero_subtitle,
        featured_event_title: (f.featured_event_title && f.featured_event_title.stringValue) || defaultSettings.featured_event_title,
        featured_event_desc: (f.featured_event_desc && f.featured_event_desc.stringValue) || defaultSettings.featured_event_desc,
        featured_event_date: (f.featured_event_date && f.featured_event_date.stringValue) || defaultSettings.featured_event_date,
        promo_price_original: (f.promo_price_original && f.promo_price_original.stringValue) || defaultSettings.promo_price_original,
        promo_price_discount: (f.promo_price_discount && f.promo_price_discount.stringValue) || defaultSettings.promo_price_discount,
        promo_tag: (f.promo_tag && f.promo_tag.stringValue) || defaultSettings.promo_tag,
        lynkid_url: (function() {
          var lu = (f.lynkid_url && f.lynkid_url.stringValue) || '';
          if (!lu || lu === 'https://lynk.id' || lu === 'https://lynk.id/') return 'https://lynk.id/examgo';
          return lu;
        })(),
        playstore_url: (f.playstore_url && f.playstore_url.stringValue) || defaultSettings.playstore_url,
        appstore_url: (f.appstore_url && f.appstore_url.stringValue) || defaultSettings.appstore_url,
        download_apk_url: (f.download_apk_url && f.download_apk_url.stringValue) || defaultSettings.download_apk_url,
        whatsapp_number: (f.whatsapp_number && f.whatsapp_number.stringValue) || defaultSettings.whatsapp_number,
        whatsapp_message: (f.whatsapp_message && f.whatsapp_message.stringValue) || defaultSettings.whatsapp_message,
        price_siswa: (f.price_siswa && f.price_siswa.stringValue) || defaultSettings.price_siswa,
        price_guru: (f.price_guru && f.price_guru.stringValue) || defaultSettings.price_guru,
        lynkid_siswa_url: (f.lynkid_siswa_url && f.lynkid_siswa_url.stringValue) || defaultSettings.lynkid_siswa_url,
        lynkid_guru_url: (f.lynkid_guru_url && f.lynkid_guru_url.stringValue) || defaultSettings.lynkid_guru_url,
        announcement_text: (f.announcement_text && f.announcement_text.stringValue) || defaultSettings.announcement_text,
        is_announcement_active: f.is_announcement_active ? (f.is_announcement_active.booleanValue === true) : true,
        is_featured_event_active: f.is_featured_event_active ? (f.is_featured_event_active.booleanValue === true) : true
      };
    } else {
      return defaultSettings;
    }
  } catch(e) {
    return defaultSettings;
  }
}

/**
 * Menyimpan konfigurasi konten Landing Page ke Firestore (Khusus Admin)
 */
function saveLandingPageSettings(settings, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/app_settings/landing_page';
  var fields = {
    hero_badge: { stringValue: String(settings.hero_badge || '').trim() },
    hero_title: { stringValue: String(settings.hero_title || '').trim() },
    hero_subtitle: { stringValue: String(settings.hero_subtitle || '').trim() },
    featured_event_title: { stringValue: String(settings.featured_event_title || '').trim() },
    featured_event_desc: { stringValue: String(settings.featured_event_desc || '').trim() },
    featured_event_date: { stringValue: String(settings.featured_event_date || '').trim() },
    promo_price_original: { stringValue: String(settings.promo_price_original || '').trim() },
    promo_price_discount: { stringValue: String(settings.promo_price_discount || '').trim() },
    promo_tag: { stringValue: String(settings.promo_tag || '').trim() },
    lynkid_url: { stringValue: String(settings.lynkid_url || '').trim() },
    playstore_url: { stringValue: String(settings.playstore_url || '').trim() },
    appstore_url: { stringValue: String(settings.appstore_url || '').trim() },
    download_apk_url: { stringValue: String(settings.download_apk_url || '').trim() },
    whatsapp_number: { stringValue: String(settings.whatsapp_number || '').trim() },
    whatsapp_message: { stringValue: String(settings.whatsapp_message || '').trim() },
    price_siswa: { stringValue: String(settings.price_siswa || '').trim() },
    price_guru: { stringValue: String(settings.price_guru || '').trim() },
    lynkid_siswa_url: { stringValue: String(settings.lynkid_siswa_url || '').trim() },
    lynkid_guru_url: { stringValue: String(settings.lynkid_guru_url || '').trim() },
    announcement_text: { stringValue: String(settings.announcement_text || '').trim() },
    is_announcement_active: { booleanValue: settings.is_announcement_active === true },
    is_featured_event_active: { booleanValue: settings.is_featured_event_active === true },
    updated_at: { timestampValue: new Date().toISOString() }
  };

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
      return { success: true, message: 'Pengaturan Landing Page berhasil disimpan!' };
    } else {
      return { error: 'Gagal menyimpan ke Firestore (' + resp.getResponseCode() + ')' };
    }
  } catch(e) {
    return { error: e.message };
  }
}

// ─────────────────────────────────────────────────────────────
// SINKRONISASI BANK SOAL GOOGLE SHEETS → FIRESTORE (READ-ONLY)
// ─────────────────────────────────────────────────────────────

function _extractSpreadsheetId(sheetUrlOrId) {
  if (!sheetUrlOrId || typeof sheetUrlOrId !== 'string') {
    return '1VLByNy1aYrfY1gXiATg-sqzR3KH8HkHMdIUJw4bboMg';
  }
  var str = sheetUrlOrId.trim();
  var match = str.match(/\/d\/([a-zA-Z0-9_-]+)/);
  if (match && match[1]) return match[1];
  var idMatch = str.match(/^[a-zA-Z0-9_-]{25,}$/);
  if (idMatch) return idMatch[0];
  return str || '1VLByNy1aYrfY1gXiATg-sqzR3KH8HkHMdIUJw4bboMg';
}

function _findSheetByGidOrNames(ss, targetGid, candidateNames) {
  if (!ss) return null;
  var sheets = ss.getSheets();
  if (targetGid) {
    for (var i = 0; i < sheets.length; i++) {
      if (String(sheets[i].getSheetId()) === String(targetGid)) {
        return sheets[i];
      }
    }
  }
  for (var j = 0; j < candidateNames.length; j++) {
    var sh = ss.getSheetByName(candidateNames[j]);
    if (sh) return sh;
  }
  for (var k = 0; k < sheets.length; k++) {
    var sClean = sheets[k].getName().toLowerCase().replace(/[\s_-]+/g, '');
    for (var m = 0; m < candidateNames.length; m++) {
      if (sClean === candidateNames[m].toLowerCase().replace(/[\s_-]+/g, '')) {
        return sheets[k];
      }
    }
  }
  return null;
}

function _readSheetTableRows(sheet) {
  if (!sheet) return [];
  var values = sheet.getDataRange().getValues();
  if (!values || values.length < 2) return [];
  var headers = values[0].map(function(h) {
    return String(h || '').trim().toLowerCase().replace(/[\s_-]+/g, '_');
  });
  var rows = [];
  for (var r = 1; r < values.length; r++) {
    var rowObj = { _rowIndex: r + 1 };
    var hasContent = false;
    for (var c = 0; c < headers.length; c++) {
      var val = values[r][c];
      if (val !== undefined && val !== null && String(val).trim() !== '') {
        hasContent = true;
      }
      rowObj[headers[c]] = val !== undefined && val !== null ? val : '';
    }
    if (hasContent) rows.push(rowObj);
  }
  return rows;
}

function _formatSheetDateToYMD(val) {
  if (!val) return '';
  if (val instanceof Date) {
    if (isNaN(val.getTime())) return '';
    var y = val.getFullYear();
    var m = String(val.getMonth() + 1);
    if (m.length < 2) m = '0' + m;
    var d = String(val.getDate());
    if (d.length < 2) d = '0' + d;
    return y + '-' + m + '-' + d;
  }
  var s = String(val).trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  var parsed = Date.parse(s);
  if (!isNaN(parsed)) {
    var dt = new Date(parsed);
    if (!isNaN(dt.getTime())) {
      var y2 = dt.getFullYear();
      var m2 = String(dt.getMonth() + 1);
      if (m2.length < 2) m2 = '0' + m2;
      var d2 = String(dt.getDate());
      if (d2.length < 2) d2 = '0' + d2;
      return y2 + '-' + m2 + '-' + d2;
    }
  }
  return s;
}

function _formatDriveImageUrl(url) {
  if (!url) return '';
  var s = String(url).trim();
  if (s.indexOf('=IMAGE(') === 0) {
    var imgMatch = s.match(/"([^"]+)"/);
    if (imgMatch && imgMatch[1]) s = imgMatch[1].trim();
  }
  var match = s.match(/id=([a-zA-Z0-9_-]+)/) || s.match(/\/d\/([a-zA-Z0-9_-]+)/);
  if (match && match[1]) {
    return 'https://drive.google.com/thumbnail?id=' + match[1] + '&sz=w1200';
  }
  return s;
}

/**
 * Step 1: Tarik data dari Google Sheets (Read-Only) & Pratinjau Sementara
 * Dilengkapi Delta Detection untuk mendeteksi paket yang sudah pernah disinkronkan ke Firestore.
 */
function previewTryoutFromSheets(sheetUrlOrId, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var ssId = _extractSpreadsheetId(sheetUrlOrId);
  var ss = null;
  try {
    ss = SpreadsheetApp.openById(ssId);
  } catch(e) {
    return { error: 'Gagal membuka Google Sheets (' + ssId + '): ' + e.message };
  }

  // 1. Dapatkan daftar paket yang SUDAH ADA di Firestore saat ini (Delta Detection)
  var existingRes = getAdminPaketTryout(username, password);
  var existingMap = {};
  if (existingRes && existingRes.packages && Array.isArray(existingRes.packages)) {
    existingRes.packages.forEach(function(pkg) {
      if (pkg.paket_id) existingMap[String(pkg.paket_id).trim().toUpperCase()] = true;
      if (pkg.id) existingMap[String(pkg.id).trim().toUpperCase()] = true;
    });
  }

  // 2. Baca 4 Sheet/Tab sesuai GID user (Read-Only!)
  // GID 370672055 -> tryout_soal
  // GID 1773556508 -> paket_tryout
  // GID 1806613765 -> subtest
  // GID 1401624701 -> jadwal_ujian
  var shSoal = _findSheetByGidOrNames(ss, '370672055', ['tryout_soal', 'soal_tryout', 'soal', 'bank_soal']);
  var shPaket = _findSheetByGidOrNames(ss, '1773556508', ['paket_tryout', 'paket_soal', 'paket']);
  var shSubtest = _findSheetByGidOrNames(ss, '1806613765', ['subtest', 'subtests', 'sub_test']);
  var shJadwal = _findSheetByGidOrNames(ss, '1401624701', ['jadwal_ujian', 'jadwal', 'jadwal_tryout']);

  var rowsPaket = _readSheetTableRows(shPaket);
  var rowsSubtest = _readSheetTableRows(shSubtest);
  var rowsSoal = _readSheetTableRows(shSoal);
  var rowsJadwal = _readSheetTableRows(shJadwal);

  // Group subtests by paket_id
  var subtestsByPaket = {};
  var subtestMap = {};
  rowsSubtest.forEach(function(st, idx) {
    var pId = String(st.paket_id || '').trim().toUpperCase();
    var sId = String(st.subtest_id || (pId ? (pId + '-ST' + (idx + 1)) : ('ST-' + (idx + 1)))).trim();
    var sObj = {
      subtest_id: sId,
      paket_id: pId,
      judul_subtest: String(st.judul_subtest || st.judul || st.nama_subtest || ('Subtest ' + (idx + 1))).trim(),
      durasi_menit: parseInt(String(st.durasi_menit || st.durasi || '0'), 10) || 0,
      order_index: idx,
      soal_count: 0
    };
    if (pId) {
      if (!subtestsByPaket[pId]) subtestsByPaket[pId] = [];
      subtestsByPaket[pId].push(sObj);
    }
    subtestMap[sId] = sObj;
  });

  // Group questions by subtest_id & paket_id
  var questionsBySubtest = {};
  var questionsByPaket = {};
  rowsSoal.forEach(function(q, qIdx) {
    var sId = String(q.subtest_id || '').trim();
    var pId = String(q.paket_id || '').trim().toUpperCase();
    if (!pId && sId && subtestMap[sId]) {
      pId = subtestMap[sId].paket_id;
    }
    var qNum = parseInt(String(q.nomor_soal || q.no || (qIdx + 1)), 10) || (qIdx + 1);
    var qObj = {
      soal_id: String(q.soal_id || (sId ? (sId + '-Q' + qNum) : ('Q-' + (qIdx + 1)))).trim(),
      subtest_id: sId,
      paket_id: pId,
      nomor_soal: qNum,
      pertanyaan: String(q.pertanyaan || q.soal || '').trim(),
      opsi_a: String(q.a || q.opsi_a || '').trim(),
      opsi_b: String(q.b || q.opsi_b || '').trim(),
      opsi_c: String(q.c || q.opsi_c || '').trim(),
      opsi_d: String(q.d || q.opsi_d || '').trim(),
      opsi_e: String(q.e || q.opsi_e || '').trim(),
      gam_a: _formatDriveImageUrl(q.gam_a || q.gambar_a || ''),
      gam_b: _formatDriveImageUrl(q.gam_b || q.gambar_b || ''),
      gam_c: _formatDriveImageUrl(q.gam_c || q.gambar_c || ''),
      gam_d: _formatDriveImageUrl(q.gam_d || q.gambar_d || ''),
      gam_e: _formatDriveImageUrl(q.gam_e || q.gambar_e || ''),
      kunci: String(q.kunci || q.kunci_jawaban || 'A').trim().toUpperCase(),
      pembahasan: String(q.pembahasan || '').trim(),
      gambar: _formatDriveImageUrl(q.gambar_soal || q.gambar || ''),
      tabel: String(q.baris_tabel || q.tabel || '').trim(),
      bobot: String(q.bobot || '1').trim()
    };
    if (sId) {
      if (!questionsBySubtest[sId]) questionsBySubtest[sId] = [];
      questionsBySubtest[sId].push(qObj);
    }
    if (pId) {
      if (!questionsByPaket[pId]) questionsByPaket[pId] = [];
      questionsByPaket[pId].push(qObj);
    }
  });

  // Update soal_count on subtest objects
  Object.keys(subtestMap).forEach(function(sId) {
    if (questionsBySubtest[sId]) {
      subtestMap[sId].soal_count = questionsBySubtest[sId].length;
    }
  });

  // Group jadwal by paket_id
  var schedulesByPaket = {};
  rowsJadwal.forEach(function(j) {
    var pId = String(j.paket_id || '').trim().toUpperCase();
    if (pId) {
      if (!schedulesByPaket[pId]) schedulesByPaket[pId] = [];
      schedulesByPaket[pId].push({
        test_id: String(j.test_id || '').trim(),
        paket_id: pId,
        nama_ujian: String(j.nama_ujian || j.nama_paket || '').trim(),
        tanggal: _formatSheetDateToYMD(j.tanggal),
        waktu: String(j.waktu || '').trim(),
        status: String(j.status || 'aktif').trim()
      });
    }
  });

  // Compile package preview list
  var packages = [];
  var newCount = 0;
  var existingCount = 0;

  // Fallback: If paket_tryout sheet is empty but subtests exist, deduce packages
  if (rowsPaket.length === 0 && Object.keys(subtestsByPaket).length > 0) {
    Object.keys(subtestsByPaket).forEach(function(pId) {
      rowsPaket.push({
        paket_id: pId,
        nama_paket: 'Paket ' + pId,
        jenis_test: pId.indexOf('SKD') >= 0 ? 'SKD' : (pId.indexOf('TKA') >= 0 ? 'TKA' : 'SNBT'),
        jenis_waktu: 'per_subtest'
      });
    });
  }

  rowsPaket.forEach(function(r, idx) {
    var pId = String(r.paket_id || ('TO-' + (idx + 1))).trim().toUpperCase();
    var pSubtests = subtestsByPaket[pId] || [];
    var pQuestions = questionsByPaket[pId] || [];
    var pSchedules = schedulesByPaket[pId] || [];

    // Sum durasi from subtests if not explicit in paket
    var totalDurasi = parseInt(String(r.durasi_menit || '0'), 10);
    if (!totalDurasi && pSubtests.length > 0) {
      pSubtests.forEach(function(st) { totalDurasi += st.durasi_menit; });
    }
    if (!totalDurasi) totalDurasi = 90;

    var isSynced = !!existingMap[pId];
    if (isSynced) {
      existingCount++;
    } else {
      newCount++;
    }

    var schedTanggal = pSchedules.length > 0 ? pSchedules[0].tanggal : _formatSheetDateToYMD(r.tanggal);
    var schedWaktu = pSchedules.length > 0 ? pSchedules[0].waktu : (String(r.jam_mulai || '08:00') + ' - ' + String(r.jam_selesai || '23:59'));

    packages.push({
      paket_id: pId,
      nama_paket: String(r.nama_paket || ('Tryout ' + pId)).trim(),
      deskripsi: String(r.deskripsi || '').trim(),
      jenis_test: String(r.jenis_test || (pId.indexOf('SKD') >= 0 ? 'SKD' : 'SNBT')).trim().toUpperCase(),
      jenis_waktu: String(r.jenis_waktu || (pSubtests.length > 1 ? 'per_subtest' : 'total')).trim(),
      durasi_menit: totalDurasi,
      tanggal: schedTanggal,
      waktu: schedWaktu,
      total_soal: pQuestions.length || parseInt(String(r.total_soal || '0'), 10) || 0,
      subtest_count: pSubtests.length,
      subtests: pSubtests.map(function(st) {
        return {
          subtest_id: st.subtest_id,
          judul_subtest: st.judul_subtest,
          durasi_menit: st.durasi_menit,
          soal_count: st.soal_count,
          questions: questionsBySubtest[st.subtest_id] || []
        };
      }),
      questions: pQuestions,
      is_synced: isSynced,
      sync_status: isSynced ? 'already_synced' : 'new',
      // Hanya paket baru yang dicentang secara default!
      selected: !isSynced
    });
  });

  return {
    success: true,
    spreadsheet_id: ssId,
    total_packages: packages.length,
    new_packages: newCount,
    already_synced_packages: existingCount,
    total_subtests: rowsSubtest.length,
    total_questions: rowsSoal.length,
    total_schedules: rowsJadwal.length,
    packages: packages
  };
}

/**
 * Step 2: Sinkronkan paket terpilih ke Firestore (Read-Only dari Sheet, Write ke Firestore)
 * Menggunakan chunk batch commits agar tidak melampaui limit Google Apps Script / Firestore REST.
 */
function syncTryoutSheetsToFirestore(sheetUrlOrId, selectedPaketIds, forceOverwrite, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };
  if (!selectedPaketIds || !Array.isArray(selectedPaketIds) || selectedPaketIds.length === 0) {
    return { error: 'Tidak ada paket soal yang dipilih untuk disinkronkan.' };
  }

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID Firebase belum diatur.' };

  var ssId = _extractSpreadsheetId(sheetUrlOrId);
  var ss = null;
  try {
    ss = SpreadsheetApp.openById(ssId);
  } catch(e) {
    return { error: 'Gagal membuka Google Sheets: ' + e.message };
  }

  // Filter set paket yang akan disinkronkan
  var targetPaketSet = {};
  selectedPaketIds.forEach(function(pid) {
    targetPaketSet[String(pid).trim().toUpperCase()] = true;
  });

  // Baca 4 tab (Pure Read-Only!)
  var shSoal = _findSheetByGidOrNames(ss, '370672055', ['tryout_soal', 'soal_tryout', 'soal', 'bank_soal']);
  var shPaket = _findSheetByGidOrNames(ss, '1773556508', ['paket_tryout', 'paket_soal', 'paket']);
  var shSubtest = _findSheetByGidOrNames(ss, '1806613765', ['subtest', 'subtests', 'sub_test']);
  var shJadwal = _findSheetByGidOrNames(ss, '1401624701', ['jadwal_ujian', 'jadwal', 'jadwal_tryout']);

  var rowsPaket = _readSheetTableRows(shPaket);
  var rowsSubtest = _readSheetTableRows(shSubtest);
  var rowsSoal = _readSheetTableRows(shSoal);
  var rowsJadwal = _readSheetTableRows(shJadwal);

  // Filter paket yang dipilih
  var selectedPaketRows = rowsPaket.filter(function(r) {
    var pid = String(r.paket_id || '').trim().toUpperCase();
    return !!targetPaketSet[pid];
  });

  // Jika paket_tryout kosong di sheet, ambil dari subtest
  if (selectedPaketRows.length === 0) {
    Object.keys(targetPaketSet).forEach(function(pid) {
      selectedPaketRows.push({
        paket_id: pid,
        nama_paket: 'Tryout ' + pid,
        jenis_test: pid.indexOf('SKD') >= 0 ? 'SKD' : 'SNBT',
        jenis_waktu: 'per_subtest'
      });
    });
  }

  // Petakan Subtest untuk paket terpilih
  var selectedSubtests = [];
  var subtestMap = {};
  var subtestsByPaket = {};
  rowsSubtest.forEach(function(st, idx) {
    var pId = String(st.paket_id || '').trim().toUpperCase();
    if (targetPaketSet[pId]) {
      var sId = String(st.subtest_id || (pId + '-ST' + (idx + 1))).trim();
      var sObj = {
        subtest_id: sId,
        paket_id: pId,
        judul_subtest: String(st.judul_subtest || st.judul || ('Subtest ' + (idx + 1))).trim(),
        durasi_menit: parseInt(String(st.durasi_menit || st.durasi || '0'), 10) || 0,
        order_index: idx,
        soal_count: 0
      };
      selectedSubtests.push(sObj);
      subtestMap[sId] = sObj;
      if (!subtestsByPaket[pId]) subtestsByPaket[pId] = [];
      subtestsByPaket[pId].push(sObj);
    }
  });

  // Petakan Soal untuk paket terpilih
  var selectedQuestions = [];
  rowsSoal.forEach(function(q, qIdx) {
    var sId = String(q.subtest_id || '').trim();
    var pId = String(q.paket_id || '').trim().toUpperCase();
    if (!pId && sId && subtestMap[sId]) {
      pId = subtestMap[sId].paket_id;
    }
    if (pId && targetPaketSet[pId]) {
      var qNum = parseInt(String(q.nomor_soal || q.no || (qIdx + 1)), 10) || (qIdx + 1);
      var qId = String(q.soal_id || (sId ? (sId + '-Q' + qNum) : (pId + '-Q' + (qIdx + 1)))).trim();
      var qObj = {
        soal_id: qId,
        paket_id: pId,
        subtest_id: sId || (pId + '-ST1'),
        nomor_soal: qNum,
        pertanyaan: String(q.pertanyaan || q.soal || '').trim(),
        opsi_a: String(q.a || q.opsi_a || '').trim(),
        opsi_b: String(q.b || q.opsi_b || '').trim(),
        opsi_c: String(q.c || q.opsi_c || '').trim(),
        opsi_d: String(q.d || q.opsi_d || '').trim(),
        opsi_e: String(q.e || q.opsi_e || '').trim(),
        gam_a: _formatDriveImageUrl(q.gam_a || q.gambar_a || ''),
        gam_b: _formatDriveImageUrl(q.gam_b || q.gambar_b || ''),
        gam_c: _formatDriveImageUrl(q.gam_c || q.gambar_c || ''),
        gam_d: _formatDriveImageUrl(q.gam_d || q.gambar_d || ''),
        gam_e: _formatDriveImageUrl(q.gam_e || q.gambar_e || ''),
        kunci: String(q.kunci || q.kunci_jawaban || 'A').trim().toUpperCase(),
        pembahasan: String(q.pembahasan || '').trim(),
        gambar: _formatDriveImageUrl(q.gambar_soal || q.gambar || ''),
        tabel: String(q.baris_tabel || q.tabel || '').trim(),
        bobot: String(q.bobot || '1').trim()
      };
      selectedQuestions.push(qObj);
      if (subtestMap[qObj.subtest_id]) {
        subtestMap[qObj.subtest_id].soal_count++;
      }
    }
  });

  // Petakan Jadwal untuk paket terpilih
  var selectedSchedules = [];
  rowsJadwal.forEach(function(j, jIdx) {
    var pId = String(j.paket_id || '').trim().toUpperCase();
    if (targetPaketSet[pId]) {
      var tId = String(j.test_id || ('TEST-' + (jIdx + 1))).trim();
      selectedSchedules.push({
        test_id: tId,
        paket_id: pId,
        nama_paket: String(j.nama_paket || '').trim(),
        jenis_test: String(j.jenis_test || '').trim(),
        nama_ujian: String(j.nama_ujian || j.nama_paket || '').trim(),
        tanggal: _formatSheetDateToYMD(j.tanggal),
        waktu: String(j.waktu || '').trim(),
        status: String(j.status || 'aktif').trim()
      });
    }
  });

  // 3. Susun Write Operations ke Firestore
  var writes = [];
  var nowIso = new Date().toISOString();

  // (a) Dokumen /paket_tryout
  selectedPaketRows.forEach(function(p) {
    var pId = String(p.paket_id).trim().toUpperCase();
    var pSubtests = subtestsByPaket[pId] || [];
    var pQuestions = selectedQuestions.filter(function(q) { return q.paket_id === pId; });
    var pSched = selectedSchedules.filter(function(s) { return s.paket_id === pId; });

    var durasi = parseInt(String(p.durasi_menit || '0'), 10);
    if (!durasi && pSubtests.length > 0) {
      pSubtests.forEach(function(st) { durasi += st.durasi_menit; });
    }
    if (!durasi) durasi = 90;

    var tanggal = _formatSheetDateToYMD(pSched.length > 0 ? pSched[0].tanggal : p.tanggal);
    var jamMulai = '08:00';
    var jamSelesai = '23:59';
    if (pSched.length > 0 && pSched[0].waktu) {
      var parts = pSched[0].waktu.split('-');
      if (parts[0]) jamMulai = parts[0].trim();
      if (parts[1]) jamSelesai = parts[1].trim();
    }

    // Bangun subtests_meta untuk ExamPackage di Flutter
    var subtestsMetaValues = pSubtests.map(function(st) {
      return {
        mapValue: {
          fields: {
            subtest_id: { stringValue: st.subtest_id },
            judul: { stringValue: st.judul_subtest },
            durasi_menit: { integerValue: String(st.durasi_menit) },
            jumlah_soal: { integerValue: String(st.soal_count) }
          }
        }
      };
    });

    var pFields = {
      paket_id: { stringValue: pId },
      nama_paket: { stringValue: String(p.nama_paket || pId).trim() },
      deskripsi: { stringValue: String(p.deskripsi || '').trim() },
      jenis_test: { stringValue: String(p.jenis_test || (pId.indexOf('SKD') >= 0 ? 'SKD' : 'SNBT')).trim().toUpperCase() },
      jenis_waktu: { stringValue: String(p.jenis_waktu || (pSubtests.length > 1 ? 'per_subtest' : 'total')).trim() },
      tanggal: { stringValue: tanggal },
      jam_mulai: { stringValue: jamMulai },
      jam_selesai: { stringValue: jamSelesai },
      durasi_menit: { integerValue: String(durasi) },
      total_soal: { integerValue: String(pQuestions.length || parseInt(String(p.total_soal || '0'), 10) || 0) },
      status: { stringValue: 'aktif' },
      target_exam_id: { stringValue: String(p.target_exam_id || '').trim().toUpperCase() },
      pass_percentage: { integerValue: String(parseInt(String(p.pass_percentage || '65'), 10)) },
      is_premium_only: { booleanValue: true },
      is_lifetime: { booleanValue: !tanggal },
      allow_retake: { booleanValue: true },
      subtest_count: { integerValue: String(pSubtests.length) },
      subtests_meta: { arrayValue: { values: subtestsMetaValues } },
      updated_at: { timestampValue: nowIso },
      synced_source: { stringValue: 'google_sheets' },
      synced_sheet_id: { stringValue: ssId }
    };

    var pDocPath = 'projects/' + projectId + '/databases/(default)/documents/paket_tryout/' + encodeURIComponent(pId);
    writes.push({
      update: {
        name: pDocPath,
        fields: pFields
      }
    });
  });

  // (b) Dokumen /subtest
  selectedSubtests.forEach(function(st) {
    var stDocPath = 'projects/' + projectId + '/databases/(default)/documents/subtest/' + encodeURIComponent(st.subtest_id);
    writes.push({
      update: {
        name: stDocPath,
        fields: {
          subtest_id: { stringValue: st.subtest_id },
          paket_id: { stringValue: st.paket_id },
          judul_subtest: { stringValue: st.judul_subtest },
          durasi_menit: { integerValue: String(st.durasi_menit) },
          soal_count: { integerValue: String(st.soal_count) },
          order_index: { integerValue: String(st.order_index) },
          updated_at: { timestampValue: nowIso }
        }
      }
    });
  });

  // (c) Dokumen /tryout_soal
  selectedQuestions.forEach(function(q) {
    var qDocPath = 'projects/' + projectId + '/databases/(default)/documents/tryout_soal/' + encodeURIComponent(q.soal_id);
    writes.push({
      update: {
        name: qDocPath,
        fields: {
          soal_id: { stringValue: q.soal_id },
          paket_id: { stringValue: q.paket_id },
          subtest_id: { stringValue: q.subtest_id },
          nomor_soal: { integerValue: String(q.nomor_soal) },
          pertanyaan: { stringValue: q.pertanyaan },
          opsi_a: { stringValue: q.opsi_a },
          opsi_b: { stringValue: q.opsi_b },
          opsi_c: { stringValue: q.opsi_c },
          opsi_d: { stringValue: q.opsi_d },
          opsi_e: { stringValue: q.opsi_e },
          gam_a: { stringValue: q.gam_a },
          gam_b: { stringValue: q.gam_b },
          gam_c: { stringValue: q.gam_c },
          gam_d: { stringValue: q.gam_d },
          gam_e: { stringValue: q.gam_e },
          kunci: { stringValue: q.kunci },
          pembahasan: { stringValue: q.pembahasan },
          gambar: { stringValue: q.gambar },
          tabel: { stringValue: q.tabel },
          bobot: { stringValue: q.bobot }
        }
      }
    });
  });

  // (d) Dokumen /jadwal_ujian
  selectedSchedules.forEach(function(s) {
    var sDocPath = 'projects/' + projectId + '/databases/(default)/documents/jadwal_ujian/' + encodeURIComponent(s.test_id);
    writes.push({
      update: {
        name: sDocPath,
        fields: {
          test_id: { stringValue: s.test_id },
          paket_id: { stringValue: s.paket_id },
          nama_paket: { stringValue: s.nama_paket },
          jenis_test: { stringValue: s.jenis_test },
          nama_ujian: { stringValue: s.nama_ujian },
          tanggal: { stringValue: s.tanggal },
          waktu: { stringValue: s.waktu },
          status: { stringValue: s.status }
        }
      }
    });
  });

  // 4. Eksekusi batch commit ke Firestore (dibagi per chunk 150-200 dokumen)
  try {
    var accessToken = _getAccessToken();
    var chunkSize = 150;
    for (var i = 0; i < writes.length; i += chunkSize) {
      var chunk = writes.slice(i, i + chunkSize);
      _commitWrites(projectId, accessToken, chunk);
    }

    return {
      success: true,
      packagesCount: selectedPaketRows.length,
      subtestsCount: selectedSubtests.length,
      questionsCount: selectedQuestions.length,
      schedulesCount: selectedSchedules.length,
      message: 'Berhasil menyinkronkan ' + selectedPaketRows.length + ' paket, ' +
               selectedSubtests.length + ' subtest, dan ' + selectedQuestions.length +
               ' butir soal ke Firestore.'
    };
  } catch(e) {
    return { error: 'Gagal melakukan sinkronisasi ke Firestore: ' + e.message };
  }
}

/**
 * Fungsi sekali klik untuk memicu popup otorisasi Google (OAuth) izin kirim email (MailApp).
 * Jalankan fungsi ini 1x dari Google Apps Script Editor agar MailApp diizinkan mengirim email ke pembeli Lynk.id.
 */
function testAuthorizeEmail() {
  var email = Session.getEffectiveUser().getEmail() || Session.getActiveUser().getEmail();
  MailApp.sendEmail({
    to: email,
    subject: '✅ Otorisasi Email ExamGO Berhasil',
    htmlBody: '<p>Selamat! Izin kirim email untuk Webhook Lynk.id & ExamGO telah berhasil diotorisasi.</p>'
  });
  Logger.log('✅ Otorisasi sukses! Email verifikasi dikirim ke: ' + email);
}

// ═══════════════════════════════════════════════════════════════════
// IKLAN (APP ADS) — Kelola iklan popup di aplikasi ExamGO
// Tipe: 'student' (siswa free), 'teacher' (guru), 'event' (semua user)
// Disimpan di Firestore `app_settings/popup_ads` & Sheet `app_ads`
// ═══════════════════════════════════════════════════════════════════

function _getDefaultPopupAds() {
  return {
    student: {
      imageUrl: 'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=800&auto=format&fit=crop&q=80',
      ctaUrl: 'https://lynk.id',
      isActive: true,
      title: 'Tryout Akbar SNBT & SKD 2026'
    },
    teacher: {
      imageUrl: 'https://images.unsplash.com/photo-1524178232363-1fb2b075b655?w=800&auto=format&fit=crop&q=80',
      ctaUrl: 'https://lynk.id',
      isActive: true,
      title: 'Akses Guru Premium ExamGO'
    },
    event: {
      imageUrl: '',
      ctaUrl: 'https://lynk.id',
      isActive: false,
      title: 'Event Spesial ExamGO'
    }
  };
}

/** Ambil konfigurasi iklan popup dari Firestore (atau default) */
function getPopupAdsSettings() {
  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  var def = _getDefaultPopupAds();

  if (!projectId) return def;

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/app_settings/popup_ads';
  try {
    var accessToken = _getAccessToken();
    var resp = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + accessToken, 'Cache-Control': 'no-cache' },
      muteHttpExceptions: true
    });
    if (resp.getResponseCode() === 200) {
      var data = JSON.parse(resp.getContentText());
      var f = data.fields || {};
      function parseAd(key, fallback) {
        if (!f[key] || !f[key].mapValue || !f[key].mapValue.fields) return fallback;
        var m = f[key].mapValue.fields;
        return {
          imageUrl: (m.imageUrl && m.imageUrl.stringValue) || fallback.imageUrl,
          ctaUrl: (m.ctaUrl && m.ctaUrl.stringValue) || fallback.ctaUrl,
          isActive: m.isActive ? (m.isActive.booleanValue === true) : fallback.isActive,
          title: (m.title && m.title.stringValue) || fallback.title
        };
      }
      return {
        student: parseAd('student', def.student),
        teacher: parseAd('teacher', def.teacher),
        event: parseAd('event', def.event)
      };
    }
  } catch(e) {}
  return def;
}

/** Simpan konfigurasi iklan popup ke Firestore (Khusus Admin) */
function savePopupAdsSettings(ads, username, password) {
  if (!_checkUserLogin(username, password)) return { error: 'unauthorized' };

  var props = PropertiesService.getScriptProperties();
  var projectId = props.getProperty('PROJECT_ID');
  if (!projectId) return { error: 'PROJECT_ID belum di-set.' };

  var url = 'https://firestore.googleapis.com/v1/projects/' + projectId + '/databases/(default)/documents/app_settings/popup_ads';
  function toMapField(ad) {
    ad = ad || {};
    return {
      mapValue: {
        fields: {
          imageUrl: { stringValue: String(ad.imageUrl || '').trim() },
          ctaUrl: { stringValue: String(ad.ctaUrl || '').trim() },
          isActive: { booleanValue: ad.isActive === true },
          title: { stringValue: String(ad.title || '').trim() }
        }
      }
    };
  }

  var fields = {
    student: toMapField(ads.student),
    teacher: toMapField(ads.teacher),
    event: toMapField(ads.event)
  };

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
      return { success: true };
    } else {
      return { error: 'Firestore error: ' + resp.getContentText() };
    }
  } catch(e) {
    return { error: e.message };
  }
}

/** Upload gambar iklan ke Google Drive dari panel admin (Khusus Admin) */
function uploadAdImageToDrive(fileData, username, password) {
  // 1. Verifikasi hak akses admin
  if (username && password) {
    if (!_checkUserLogin(username, password)) {
      return { success: false, error: 'Autentikasi admin tidak valid atau sesi telah berakhir. Silakan login ulang.' };
    }
  } else {
    try {
      var email = Session.getActiveUser().getEmail();
      if (!email && !_checkUserLogin(username, password)) {
        return { success: false, error: 'Sesi login admin tidak ditemukan. Silakan login ulang ke panel admin.' };
      }
    } catch(eAuth) {}
  }

  // 2. Validasi kelengkapan payload
  if (!fileData || !fileData.base64 || !fileData.filename) {
    return { success: false, error: 'Data file gambar tidak lengkap atau rusak.' };
  }

  try {
    var contentType = fileData.mimeType || 'image/png';
    // Bersihkan prefix data:image/...;base64 jika terbawa oleh FileReader
    var raw = String(fileData.base64).replace(/^data:image\/[^;]+;base64,/, '').trim();
    var decodedBytes = Utilities.base64Decode(raw);
    var blob = Utilities.newBlob(decodedBytes, contentType, fileData.filename);

    var props = PropertiesService.getScriptProperties();
    var targetFolderId = props.getProperty('DRIVE_FOLDER_SOAL_IMAGE') || props.getProperty('DRIVE_FOLDER_ID') || '1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ';
    var targetFolder;

    try {
      if (targetFolderId) {
        targetFolder = DriveApp.getFolderById(targetFolderId);
      }
    } catch(eFolderId) {}

    if (!targetFolder) {
      try {
        var folderName = 'ExamGO_Uploads';
        var folders = DriveApp.getFoldersByName(folderName);
        targetFolder = folders.hasNext() ? folders.next() : DriveApp.createFolder(folderName);
      } catch(eFallback) {
        targetFolder = DriveApp.getRootFolder();
      }
    }

    // Hindari crash jika domain Google Workspace melarang setSharing pada folder
    try {
      targetFolder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch(eSh) {}

    var file = targetFolder.createFile(blob);

    // Pastikan file gambar dapat diakses publik oleh aplikasi
    try {
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    } catch(eSh2) {}

    var fileId = file.getId();
    var cdnUrl = 'https://lh3.googleusercontent.com/d/' + fileId;
    var thumbUrl = 'https://drive.google.com/thumbnail?id=' + fileId + '&sz=w1000';
    var directUrl = 'https://drive.google.com/uc?export=view&id=' + fileId;

    return {
      success: true,
      url: cdnUrl,
      cdnUrl: cdnUrl,
      thumbnailUrl: thumbUrl,
      directUrl: directUrl,
      fileId: fileId,
      filename: file.getName()
    };
  } catch(e) {
    return { success: false, error: 'Gagal mengunggah gambar ke Google Drive: ' + e.message };
  }
}

function _getAdsSheet() {
  var props = PropertiesService.getScriptProperties();
  var ssId = props.getProperty('SPREADSHEET_ID') || props.getProperty('SHEET_ID');
  var ss;
  if (ssId) {
    try { ss = SpreadsheetApp.openById(ssId); } catch(e) {}
  }
  if (!ss) {
    try { ss = SpreadsheetApp.getActiveSpreadsheet(); } catch(e) {}
  }
  if (!ss) return null;

  var sheet = ss.getSheetByName('app_ads');
  if (!sheet) {
    // Buat sheet baru jika belum ada
    sheet = ss.insertSheet('app_ads');
    sheet.appendRow(['id', 'type', 'title', 'imageUrl', 'ctaUrl', 'isActive']);
    sheet.getRange(1, 1, 1, 6).setFontWeight('bold');
  }
  return sheet;
}

/** Ambil semua iklan aktif berdasarkan tipe. Dipanggil dari Flutter via GET ?action=get_ads&type=student */
function getAds(type) {
  try {
    var sheet = _getAdsSheet();
    if (!sheet) return { ads: [] };

    var rows = sheet.getDataRange().getValues();
    if (rows.length <= 1) return { ads: [] };

    var headers = rows[0];
    var idIdx = headers.indexOf('id');
    var typeIdx = headers.indexOf('type');
    var titleIdx = headers.indexOf('title');
    var imgIdx = headers.indexOf('imageUrl');
    var ctaIdx = headers.indexOf('ctaUrl');
    var activeIdx = headers.indexOf('isActive');

    var ads = [];
    for (var i = 1; i < rows.length; i++) {
      var row = rows[i];
      var rowType = String(row[typeIdx] || '').toLowerCase();
      var isActive = row[activeIdx];
      // isActive bisa boolean atau string 'TRUE'/'true'
      var active = (isActive === true || String(isActive).toLowerCase() === 'true');
      if (!active) continue;
      // Filter: kembalikan tipe yang diminta ATAU tipe 'event' (muncul untuk semua)
      if (rowType !== type.toLowerCase() && rowType !== 'event') continue;

      ads.push({
        id: String(row[idIdx] || ''),
        type: rowType,
        title: String(row[titleIdx] || ''),
        imageUrl: String(row[imgIdx] || ''),
        ctaUrl: String(row[ctaIdx] || ''),
      });
    }
    return { ads: ads };
  } catch(e) {
    return { ads: [], error: e.message };
  }
}

/** Simpan/update iklan dari admin panel. Dipanggil dari admin.html via doPost action=saveAd */
function saveAd(adData) {
  try {
    var sheet = _getAdsSheet();
    if (!sheet) return { error: 'Sheet tidak tersedia' };

    var rows = sheet.getDataRange().getValues();
    var headers = rows[0];
    var idIdx = headers.indexOf('id');

    // Cari baris yang sudah ada berdasarkan id
    for (var i = 1; i < rows.length; i++) {
      if (String(rows[i][idIdx]) === String(adData.id)) {
        // Update baris yang ada
        sheet.getRange(i + 1, 1, 1, 6).setValues([[
          adData.id, adData.type, adData.title, adData.imageUrl, adData.ctaUrl, adData.isActive
        ]]);
        return { success: true, action: 'updated' };
      }
    }

    // Tambah baris baru
    var newId = adData.id || String(Date.now());
    sheet.appendRow([newId, adData.type, adData.title, adData.imageUrl, adData.ctaUrl, adData.isActive]);
    return { success: true, action: 'created', id: newId };
  } catch(e) {
    return { error: e.message };
  }
}

/** Hapus iklan berdasarkan id. Dipanggil dari admin.html via doPost action=deleteAd */
function deleteAd(adId) {
  try {
    var sheet = _getAdsSheet();
    if (!sheet) return { error: 'Sheet tidak tersedia' };

    var rows = sheet.getDataRange().getValues();
    var headers = rows[0];
    var idIdx = headers.indexOf('id');

    for (var i = 1; i < rows.length; i++) {
      if (String(rows[i][idIdx]) === String(adId)) {
        sheet.deleteRow(i + 1);
        return { success: true };
      }
    }
    return { error: 'Iklan tidak ditemukan' };
  } catch(e) {
    return { error: e.message };
  }
}

// ─────────────────────────────────────────────────────────────────────
// UTILITAS: Bersihkan Script Properties yang tidak digunakan
// Cara pakai:
//   1. Buka GAS Editor (script.google.com)
//   2. Pilih fungsi "auditScriptProperties" → Run → lihat Execution Log
//   3. Kalau sudah yakin, jalankan "cleanupScriptProperties"
// ─────────────────────────────────────────────────────────────────────

/**
 * Daftar property yang WAJIB dipertahankan.
 * Semua property lain yang tidak ada di sini akan dianggap aman dihapus.
 */
var _REQUIRED_PROPS = [
  'API_KEY',
  'PROJECT_ID',
  'SA_EMAIL',
  'SA_PRIVATE_KEY',
  'SPREADSHEET_ID',
  'SHEET_ID',
  'DRIVE_FOLDER_SOAL_IMAGE',
  'LYNK_WEBHOOK_SECRET',
  'LYNK_MERCHANT_KEY',
  // Diisi otomatis oleh kode — jangan hapus
  'ACCESS_TOKEN_V2',
  'ACCESS_TOKEN_EXP_V2',
  'TEACHER_FCM_TOKEN',
  'TEACHER_FCM_TOKENS'
];

/**
 * Jalankan ini DULU untuk melihat laporan semua property.
 * Cek Execution Log (Ctrl+Enter) untuk hasilnya.
 */
function auditScriptProperties() {
  var props = PropertiesService.getScriptProperties().getProperties();
  var keys  = Object.keys(props).sort();
  var required = _REQUIRED_PROPS;

  var keep = [];
  var remove = [];

  keys.forEach(function(key) {
    var isAuto = key.indexOf('TEACHER_TOKENS_') === 0; // per-exam FCM token cache
    if (required.indexOf(key) !== -1 || isAuto) {
      keep.push(key);
    } else {
      var val = String(props[key] || '');
      var preview = val.length > 80 ? val.substring(0, 80) + '...' : val;
      remove.push({ key: key, preview: preview });
    }
  });

  Logger.log('════════════ AUDIT SCRIPT PROPERTIES ════════════');
  Logger.log('Total: ' + keys.length + ' property ditemukan');
  Logger.log('');
  Logger.log('✅ SIMPAN (' + keep.length + '):');
  keep.forEach(function(k) { Logger.log('   ' + k); });
  Logger.log('');
  Logger.log('🗑️  HAPUS (' + remove.length + '):');
  if (remove.length === 0) {
    Logger.log('   (tidak ada yang perlu dihapus)');
  } else {
    remove.forEach(function(item) {
      Logger.log('   ' + item.key + '  =  ' + item.preview);
    });
    Logger.log('');
    Logger.log('👉 Jalankan cleanupScriptProperties() untuk menghapusnya.');
  }
  Logger.log('══════════════════════════════════════════════════');
}

/**
 * Jalankan ini SETELAH auditScriptProperties() dan Anda sudah yakin.
 * Semua property yang tidak ada di _REQUIRED_PROPS akan dihapus permanen.
 */
function cleanupScriptProperties() {
  var props = PropertiesService.getScriptProperties();
  var all   = props.getProperties();
  var required = _REQUIRED_PROPS;

  var deleted = [];
  Object.keys(all).forEach(function(key) {
    var isAuto = key.indexOf('TEACHER_TOKENS_') === 0;
    if (required.indexOf(key) === -1 && !isAuto) {
      props.deleteProperty(key);
      deleted.push(key);
    }
  });

  if (deleted.length === 0) {
    Logger.log('✅ Tidak ada property yang perlu dihapus. Sudah bersih!');
  } else {
    Logger.log('🗑️  Berhasil menghapus ' + deleted.length + ' property:');
    deleted.forEach(function(k) { Logger.log('   - ' + k); });
    Logger.log('✅ Selesai. Jalankan auditScriptProperties() untuk verifikasi.');
  }
}

/**
 * Jalankan SEKALI dari GAS Editor untuk set semua key Lynk.id otomatis.
 * Cek Execution Log setelah selesai.
 */
function setupWebhookSecret() {
  var props = PropertiesService.getScriptProperties();
  var secret = '26BE452F6A53F62F620F083311799A10';
  var merchantKey = 'GA0zWSkRdf2rsctwm8AnngKUeuU4LASf';

  props.setProperty('LYNK_WEBHOOK_SECRET', secret);
  props.setProperty('LYNK_MERCHANT_KEY', merchantKey);

  Logger.log('✅ LYNK_WEBHOOK_SECRET diset.');
  Logger.log('✅ LYNK_MERCHANT_KEY diset: ' + merchantKey.substring(0, 8) + '••••');
  Logger.log('');
  Logger.log('══════════ SELESAI ══════════');
  Logger.log('URL Webhook aktif: https://examgo.id/webhook?secret=' + secret);
  Logger.log('Verifikasi HMAC Merchant Key: AKTIF');
  Logger.log('════════════════════════════════');
}

function _escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

/**
 * Render Web UI untuk inspeksi dan pembersihan Script Properties yang melebihi kuota 50
 */
function _renderPropsManagerHtmlOutput(e) {
  var user = (e && e.parameter && (e.parameter.user || e.parameter.username)) || '';
  var pass = (e && e.parameter && (e.parameter.pass || e.parameter.password)) || '';
  var isAuthed = false;

  if (user && pass) {
    isAuthed = _checkUserLogin(user, pass);
  }

  // Jika belum login, tampilkan form login
  if (!isAuthed) {
    var loginErrorHtml = (user || pass) ? '<div style="background:rgba(239,68,68,0.15);border:1px solid #ef4444;color:#fca5a5;padding:12px;border-radius:12px;font-size:13px;margin-bottom:16px;">❌ Username atau password salah. Coba lagi.</div>' : '';
    var loginHtml = '<!DOCTYPE html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Login Pengelola Properti ExamGO</title>' +
      '<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;700;800&family=JetBrains+Mono:wght@600&display=swap" rel="stylesheet">' +
      '<style>' +
      '* { box-sizing: border-box; margin:0; padding:0; }' +
      'body { background: #090d16; color: #f8fafc; font-family: \'Plus Jakarta Sans\', sans-serif; min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; }' +
      '.card { background: #0f172a; border: 1px solid rgba(16, 185, 129, 0.25); border-radius: 24px; padding: 36px 28px; max-width: 440px; width: 100%; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5); }' +
      'h2 { font-size: 20px; font-weight: 800; margin-bottom: 6px; color: #fff; }' +
      'p.desc { font-size: 13px; color: #94a3b8; margin-bottom: 24px; line-height: 1.5; }' +
      'label { display: block; font-size: 12px; font-weight: 700; text-transform: uppercase; color: #cbd5e1; margin-bottom: 6px; letter-spacing: 0.5px; }' +
      'input { width: 100%; padding: 12px 14px; background: #1e293b; border: 1px solid #334155; border-radius: 12px; color: #fff; font-size: 14px; margin-bottom: 16px; outline: none; }' +
      'input:focus { border-color: #10b981; }' +
      'button { width: 100%; padding: 14px; background: linear-gradient(135deg, #10b981, #059669); border: none; border-radius: 12px; color: #fff; font-size: 14px; font-weight: 800; cursor: pointer; transition: 0.2s; }' +
      'button:hover { opacity: 0.95; transform: translateY(-1px); }' +
      '</style></head><body>' +
      '<div class="card">' +
        '<div style="display:inline-block;padding:4px 12px;border-radius:999px;background:rgba(16,185,129,0.15);border:1px solid rgba(16,185,129,0.3);color:#34d399;font-size:11px;font-weight:800;margin-bottom:12px;text-transform:uppercase;">Admin Tool</div>' +
        '<h2>🧹 ExamGO Properties Cleaner</h2>' +
        '<p class="desc">Masuk dengan akun admin ExamGO untuk melihat dan menghapus properti skrip yang melebihi batas kuota 50.</p>' +
        loginErrorHtml +
        '<form method="GET">' +
          '<input type="hidden" name="action" value="props_manager">' +
          '<label>Username</label>' +
          '<input type="text" name="user" value="' + _escapeHtml(user || 'admin') + '" required>' +
          '<label>Password</label>' +
          '<input type="password" name="pass" placeholder="Password admin" required autofocus>' +
          '<button type="submit">Buka Pengelola Properti &rarr;</button>' +
        '</form>' +
      '</div></body></html>';
    return HtmlService.createHtmlOutput(loginHtml).setTitle('Login ExamGO Properties Cleaner').addMetaTag('viewport', 'width=device-width, initial-scale=1');
  }

  // Jika sudah login, cek aksi pembersihan
  var propsService = PropertiesService.getScriptProperties();
  var cleanedCount = 0;
  var deletedKeys = [];
  if (e && e.parameter && (e.parameter.do_cleanup === '1' || e.parameter.confirm === 'yes')) {
    var currAll = propsService.getProperties();
    Object.keys(currAll).forEach(function(k) {
      var isAuto = k.indexOf('TEACHER_TOKENS_') === 0;
      if (_REQUIRED_PROPS.indexOf(k) === -1 && !isAuto) {
        propsService.deleteProperty(k);
        deletedKeys.push(k);
      }
    });
    cleanedCount = deletedKeys.length;
  }

  // Ambil data terbaru setelah aksi
  var allProps = propsService.getProperties();
  var allKeys = Object.keys(allProps).sort();
  var keepList = [];
  var unusedList = [];

  allKeys.forEach(function(k) {
    var isAuto = k.indexOf('TEACHER_TOKENS_') === 0;
    var rawVal = String(allProps[k] || '');
    var maskedVal = rawVal;
    if (k === 'SA_PRIVATE_KEY' || k === 'API_KEY' || k === 'LYNK_WEBHOOK_SECRET' || k === 'LYNK_MERCHANT_KEY') {
      maskedVal = rawVal.length > 15 ? rawVal.substring(0, 8) + '••••••••' + rawVal.substring(rawVal.length - 4) : '••••••••';
    } else if (rawVal.length > 70) {
      maskedVal = rawVal.substring(0, 70) + '...';
    }

    if (_REQUIRED_PROPS.indexOf(k) !== -1 || isAuto) {
      keepList.push({ key: k, value: maskedVal, isAuto: isAuto });
    } else {
      unusedList.push({ key: k, value: maskedVal });
    }
  });

  var totalCount = allKeys.length;
  var statusBadgeClass = totalCount >= 50 ? 'bg-red-500/20 text-red-400 border-red-500/30' : (totalCount > 20 ? 'bg-amber-500/20 text-amber-400 border-amber-500/30' : 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30');

  var cleanedBanner = '';
  if (cleanedCount > 0) {
    cleanedBanner = '<div style="background:rgba(16,185,129,0.15);border:1px solid #10b981;color:#6ee7b7;padding:16px 20px;border-radius:16px;margin-bottom:24px;font-size:14px;line-height:1.5;">' +
      '<strong>🎉 Sukses! Berhasil menghapus ' + cleanedCount + ' properti usang.</strong><br>' +
      '<span style="font-size:12px;color:#cbd5e1;">Sekarang skrip Anda hanya memiliki ' + totalCount + ' properti (jauh di bawah batas 50). Editor Google Apps Script kini normal dan tidak lagi read-only!</span>' +
    '</div>';
  }

  var cleanupActionBox = '';
  if (unusedList.length > 0) {
    cleanupActionBox = '<div style="background:rgba(239,68,68,0.1);border:1px solid rgba(239,68,68,0.3);padding:24px;border-radius:20px;margin-bottom:28px;">' +
      '<div style="display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;">' +
        '<div>' +
          '<h3 style="font-size:16px;font-weight:800;color:#fca5a5;margin-bottom:4px;">⚠️ Ditemukan ' + unusedList.length + ' Properti Usang / Tidak Terpakai</h3>' +
          '<p style="font-size:13px;color:#94a3b8;line-height:1.5;">Properti ini adalah sisa konfigurasi/testing lama yang tidak pernah dibaca lagi oleh sistem ExamGO. Menghapusnya aman 100% dan akan membebaskan kuota Google Apps Script Anda.</p>' +
        '</div>' +
        '<form method="GET" style="margin:0;">' +
          '<input type="hidden" name="action" value="props_manager">' +
          '<input type="hidden" name="user" value="' + _escapeHtml(user) + '">' +
          '<input type="hidden" name="pass" value="' + _escapeHtml(pass) + '">' +
          '<input type="hidden" name="do_cleanup" value="1">' +
          '<button type="submit" onclick="return confirm(\'Yakin ingin menghapus semua ' + unusedList.length + ' properti usang ini sekarang?\');" style="background:#ef4444;color:#fff;border:none;padding:14px 24px;border-radius:12px;font-weight:800;font-size:14px;cursor:pointer;white-space:nowrap;box-shadow:0 10px 15px -3px rgba(239,68,68,0.3);">' +
            '🗑️ Hapus Semua ' + unusedList.length + ' Properti Usang' +
          '</button>' +
        '</form>' +
      '</div>' +
    '</div>';
  } else {
    cleanupActionBox = '<div style="background:rgba(16,185,129,0.1);border:1px solid rgba(16,185,129,0.3);padding:20px;border-radius:20px;margin-bottom:28px;display:flex;align-items:center;gap:14px;">' +
      '<div style="font-size:28px;">✅</div>' +
      '<div>' +
        '<h3 style="font-size:15px;font-weight:800;color:#34d399;margin-bottom:2px;">Properti Skrip Sudah Sangat Bersih!</h3>' +
        '<p style="font-size:13px;color:#94a3b8;">Hanya tersisa ' + keepList.length + ' properti aktif yang dibutuhkan untuk operasional ExamGO. Tidak ada properti sampah yang terbuang.</p>' +
      '</div>' +
    '</div>';
  }

  // Render list properti yang disimpan
  var keepRowsHtml = '';
  keepList.forEach(function(item) {
    var tag = item.isAuto ? '<span style="background:rgba(148,163,184,0.15);color:#94a3b8;font-size:11px;padding:3px 8px;border-radius:6px;font-weight:700;">Cache Token</span>' : '<span style="background:rgba(16,185,129,0.15);color:#34d399;font-size:11px;padding:3px 8px;border-radius:6px;font-weight:700;">Wajib Inti</span>';
    keepRowsHtml += '<tr>' +
      '<td style="padding:12px 16px;border-bottom:1px solid #1e293b;font-family:\'JetBrains Mono\',monospace;font-weight:700;color:#38bdf8;font-size:13px;">' + _escapeHtml(item.key) + '</td>' +
      '<td style="padding:12px 16px;border-bottom:1px solid #1e293b;">' + tag + '</td>' +
      '<td style="padding:12px 16px;border-bottom:1px solid #1e293b;font-family:\'JetBrains Mono\',monospace;color:#94a3b8;font-size:12px;max-width:320px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + _escapeHtml(item.value) + '</td>' +
    '</tr>';
  });

  // Render list properti usang
  var unusedRowsHtml = '';
  if (unusedList.length === 0) {
    unusedRowsHtml = '<tr><td colspan="2" style="padding:24px;text-align:center;color:#64748b;font-size:13px;">(Kosong — Tidak ada properti usang)</td></tr>';
  } else {
    unusedList.forEach(function(item) {
      unusedRowsHtml += '<tr>' +
        '<td style="padding:12px 16px;border-bottom:1px solid #1e293b;font-family:\'JetBrains Mono\',monospace;font-weight:700;color:#f87171;font-size:13px;">' + _escapeHtml(item.key) + '</td>' +
        '<td style="padding:12px 16px;border-bottom:1px solid #1e293b;font-family:\'JetBrains Mono\',monospace;color:#94a3b8;font-size:12px;max-width:320px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + _escapeHtml(item.value) + '</td>' +
      '</tr>';
    });
  }

  var html = '<!DOCTYPE html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>ExamGO Script Properties Manager</title>' +
    '<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;600;700;800&family=JetBrains+Mono:wght@600;700&display=swap" rel="stylesheet">' +
    '<style>' +
    '* { box-sizing: border-box; margin:0; padding:0; }' +
    'body { background: #090d16; color: #f8fafc; font-family: \'Plus Jakarta Sans\', sans-serif; min-height: 100vh; padding: 32px 20px; }' +
    '.container { max-width: 900px; margin: 0 auto; }' +
    '.header { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 24px; flex-wrap: wrap; }' +
    'h1 { font-size: 24px; font-weight: 800; color: #fff; }' +
    'p.sub { font-size: 13px; color: #94a3b8; margin-top: 4px; }' +
    '.badge-count { font-size: 13px; font-weight: 800; padding: 6px 14px; border-radius: 999px; border: 1px solid rgba(255,255,255,0.1); }' +
    '.card { background: #0f172a; border: 1px solid #1e293b; border-radius: 20px; overflow: hidden; margin-bottom: 28px; box-shadow: 0 10px 25px -5px rgba(0,0,0,0.3); }' +
    '.card-header { padding: 18px 20px; background: rgba(30,41,59,0.5); border-bottom: 1px solid #1e293b; display: flex; align-items: center; justify-content: space-between; }' +
    '.card-title { font-size: 15px; font-weight: 800; color: #fff; }' +
    'table { width: 100%; border-collapse: collapse; text-align: left; }' +
    'th { padding: 12px 16px; background: rgba(15,23,42,0.8); color: #64748b; font-size: 11px; text-transform: uppercase; font-weight: 700; letter-spacing: 0.5px; border-bottom: 1px solid #1e293b; }' +
    '</style></head><body>' +
    '<div class="container">' +
      '<div class="header">' +
        '<div>' +
          '<h1>🧹 ExamGO Properties Manager</h1>' +
          '<p class="sub">Pembersih otomatis Script Properties yang melebihi batas kuota 50 Google Apps Script.</p>' +
        '</div>' +
        '<div class="badge-count ' + statusBadgeClass + '">Total Properti: ' + totalCount + ' / 50</div>' +
      '</div>' +
      cleanedBanner +
      cleanupActionBox +
      '<div class="card">' +
        '<div class="card-header">' +
          '<div class="card-title">🛡️ Properti Inti & Aktif (' + keepList.length + ' item)</div>' +
          '<span style="font-size:12px;color:#10b981;font-weight:700;">Wajib Dipertahankan</span>' +
        '</div>' +
        '<table>' +
          '<thead><tr><th>Nama Properti (Key)</th><th>Tipe</th><th>Nilai (Masked)</th></tr></thead>' +
          '<tbody>' + keepRowsHtml + '</tbody>' +
        '</table>' +
      '</div>' +
      '<div class="card">' +
        '<div class="card-header" style="background:rgba(239,68,68,0.05);">' +
          '<div class="card-title" style="color:#fca5a5;">🗑️ Properti Usang / Siap Dihapus (' + unusedList.length + ' item)</div>' +
          '<span style="font-size:12px;color:#ef4444;font-weight:700;">Aman Dihapus</span>' +
        '</div>' +
        '<table>' +
          '<thead><tr><th>Nama Properti (Key)</th><th>Nilai</th></tr></thead>' +
          '<tbody>' + unusedRowsHtml + '</tbody>' +
        '</table>' +
      '</div>' +
    '</div></body></html>';

  return HtmlService.createHtmlOutput(html)
    .setTitle('ExamGO Properties Cleaner')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

