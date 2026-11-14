/**
 * Cloudflare Worker untuk Domain examgo.id
 * 
 * Rute:
 * 1. https://examgo.id         -> Landing Page Resmi (Bebas Google Drive Error, Cepat, Responsif)
 * 2. https://examgo.id/admin   -> Redirect Langsung ke Google Apps Script Admin Console
 * 3. https://examgo.id/webhook -> Reverse Proxy Webhook Lynk.id (Menghilangkan HTTP 302 Redirect & Langsung HTTP 200 OK)
 */

const GITHUB_LANDING_PAGE_URL = "https://raw.githubusercontent.com/ekiq11/Exam-Go/main/lib/gas_fcm/gas/landing.html";
const GITHUB_PRIVACY_PAGE_URL = "https://raw.githubusercontent.com/ekiq11/Exam-Go/main/lib/gas_fcm/gas/privacy.html";
const GITHUB_GURU_PAGE_URL = "https://raw.githubusercontent.com/ekiq11/Exam-Go/main/lib/gas_fcm/gas/guru.html";
const GAS_ADMIN_URL = "https://script.google.com/macros/s/AKfycbw4HGiqmuBPPNfBptdT0zQTgJSldGlpQziKLjuN0zfnZA_zJSXyjedwBa9MA2_piWKloA/exec?page=admin";
const GAS_PRIVACY_URL = "https://script.google.com/macros/s/AKfycbw4HGiqmuBPPNfBptdT0zQTgJSldGlpQziKLjuN0zfnZA_zJSXyjedwBa9MA2_piWKloA/exec?page=privacy";
const GAS_WEBHOOK_URL = "https://script.google.com/macros/s/AKfycbw4HGiqmuBPPNfBptdT0zQTgJSldGlpQziKLjuN0zfnZA_zJSXyjedwBa9MA2_piWKloA/exec?action=webhook_lynk";

// Base64 template baku Word (.docx) untuk download instan tanpa 404
const DOCX_TEMPLATE_BASE64 = "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";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.toLowerCase().replace(/\/+$/, "");

    // 1. RUTE WEBHOOK LYNK.ID: examgo.id/webhook atau examgo.id/api/webhook
    // Berfungsi sebagai Reverse Proxy Gateway untuk Lynk.id!
    // Mengubah HTTP 302 redirect dari Google Apps Script menjadi HTTP 200 OK murni,
    // sehingga Lynk.id tidak akan pernah gagal (mengatasi error "Webhook delivery failed (HTTP 302)").
    if (path === "/webhook" || path === "/api/webhook" || path === "/webhook_lynk") {
      if (request.method === "OPTIONS") {
        return new Response(null, {
          status: 204,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Access-Control-Allow-Headers": "*"
          }
        });
      }

      try {
        const reqMethod = request.method;
        const body = (reqMethod === "POST" || reqMethod === "PUT" || reqMethod === "PATCH") 
          ? await request.text() 
          : undefined;

        // Teruskan query string (termasuk ?secret=...) ke Google Apps Script
        const targetWebhookUrl = new URL(GAS_WEBHOOK_URL);
        url.searchParams.forEach((val, key) => {
          if (key !== "action") targetWebhookUrl.searchParams.set(key, val);
        });

        // Forward ke Google Apps Script dengan follow redirect otomatis
        const forwardResp = await fetch(targetWebhookUrl.toString(), {
          method: reqMethod,
          headers: { "Content-Type": "application/json" },
          body: body,
          redirect: "follow"
        });

        const respText = await forwardResp.text();
        if (respText.trim().startsWith("<")) {
          return new Response(JSON.stringify({
            status: "error",
            message: "Server Google Apps Script mengembalikan respon non-JSON. Silakan coba kembali sesaat lagi."
          }), {
            status: 200,
            headers: {
              "Content-Type": "application/json; charset=UTF-8",
              "Access-Control-Allow-Origin": "*"
            }
          });
        }
        return new Response(respText, {
          status: 200,
          headers: {
            "Content-Type": "application/json; charset=UTF-8",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS"
          }
        });
      } catch (err) {
        return new Response(JSON.stringify({ status: "error", message: err.message }), {
          status: 200,
          headers: { "Content-Type": "application/json" }
        });
      }
    }

    // 1.5. RUTE API LANDING SETTINGS: examgo.id/api/landing-settings (GET & POST)
    // Reverse proxy ke Google Apps Script tanpa CORS atau cookie issue
    if (path === "/api/landing-settings" || path === "/api/landing_settings") {
      if (request.method === "OPTIONS") {
        return new Response(null, {
          status: 204,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Access-Control-Allow-Headers": "*"
          }
        });
      }

      try {
        const reqMethod = request.method;
        const reqHeaders = new Headers(request.headers);
        reqHeaders.delete("host");

        const targetGasUrl = (reqMethod === "GET")
          ? GAS_ADMIN_URL.replace("?page=admin", "") + "?action=get_landing_settings"
          : GAS_ADMIN_URL.replace("?page=admin", "");

        const body = (reqMethod === "POST") ? await request.text() : undefined;

        const forwardResp = await fetch(targetGasUrl, {
          method: reqMethod,
          headers: reqHeaders,
          body: body,
          redirect: "follow"
        });

        const respText = await forwardResp.text();
        if (respText.trim().startsWith("<")) {
          return new Response(JSON.stringify({
            status: "error",
            message: "Server Google Apps Script mengembalikan respon non-JSON. Silakan coba kembali sesaat lagi."
          }), {
            status: 200,
            headers: {
              "Content-Type": "application/json; charset=UTF-8",
              "Access-Control-Allow-Origin": "*"
            }
          });
        }
        return new Response(respText, {
          status: 200,
          headers: {
            "Content-Type": "application/json; charset=UTF-8",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS"
          }
        });
      } catch (err) {
        return new Response(JSON.stringify({ status: "error", message: err.message }), {
          status: 200,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      }
    }

    // 1.8. RUTE PROPERTIES CLEANER: examgo.id/props atau examgo.id/clean-props
    if (path === "/props" || path === "/clean-props") {
      const targetPropsUrl = new URL(GAS_ADMIN_URL.replace("?page=admin", "") + "?action=props_manager");
      url.searchParams.forEach((val, key) => targetPropsUrl.searchParams.set(key, val));
      return Response.redirect(targetPropsUrl.toString(), 302);
    }

    // 1.9. RUTE PROXY GOOGLE FORM: examgo.id/api/proxy-gform?url=...
    // Mengambil HTML Google Form publik server-side untuk menghindari blokir CORS di browser laptop guru
    if (path === "/api/proxy-gform" || path === "/api/gform-proxy") {
      const targetGformUrl = url.searchParams.get("url");
      if (!targetGformUrl) {
        return new Response(JSON.stringify({ error: "missing_url" }), {
          status: 400,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      }
      try {
        const gformResp = await fetch(targetGformUrl, {
          headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
          }
        });
        const html = await gformResp.text();
        return new Response(html, {
          status: 200,
          headers: {
            "Content-Type": "text/html; charset=UTF-8",
            "Access-Control-Allow-Origin": "*"
          }
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: e.message }), {
          status: 500,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      }
    }

    // 1.91. RUTE PROXY GAMBAR: examgo.id/api/proxy-image?url=...
    // Mengatasi net::ERR_BLOCKED_BY_RESPONSE.NotSameSite pada Google Form / Drive / UserContent
    if (path === "/api/proxy-image" || path === "/api/image-proxy") {
      if (request.method === "OPTIONS") {
        return new Response(null, {
          status: 204,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Cross-Origin-Resource-Policy": "cross-origin"
          }
        });
      }

      const imgTarget = url.searchParams.get("url");
      if (!imgTarget) {
        return new Response("Missing url parameter", {
          status: 400,
          headers: { "Access-Control-Allow-Origin": "*" }
        });
      }

      try {
        let decodedUrl = decodeURIComponent(imgTarget);
        if (!decodedUrl.startsWith("http://") && !decodedUrl.startsWith("https://")) {
          return new Response("Invalid URL protocol", { status: 400, headers: { "Access-Control-Allow-Origin": "*" } });
        }
        const driveMatch = decodedUrl.match(/(?:drive\.google\.com\/(?:file\/d\/|open\?id=|uc\?.*id=)|docs\.google\.com\/file\/d\/)([a-zA-Z0-9_-]+)/);
        if (driveMatch) {
          decodedUrl = "https://drive.google.com/thumbnail?id=" + driveMatch[1] + "&sz=w1200";
        }

        const imgResp = await fetch(decodedUrl, {
          headers: {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            "Referer": "https://docs.google.com/"
          },
          redirect: "follow"
        });

        if (!imgResp.ok) {
          return new Response("Image fetch failed: " + imgResp.status, {
            status: imgResp.status,
            headers: { "Access-Control-Allow-Origin": "*" }
          });
        }

        const contentType = imgResp.headers.get("Content-Type") || "image/jpeg";
        const imgBuffer = await imgResp.arrayBuffer();

        return new Response(imgBuffer, {
          status: 200,
          headers: {
            "Content-Type": contentType,
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Cross-Origin-Resource-Policy": "cross-origin",
            "Cross-Origin-Embedder-Policy": "unsafe-none",
            "Cache-Control": "public, max-age=604800, immutable"
          }
        });
      } catch (err) {
        return new Response("Proxy error: " + err.message, {
          status: 500,
          headers: { "Access-Control-Allow-Origin": "*" }
        });
      }
    }

    // 1.92. RUTE UNDUH TEMPLATE WORD: examgo.id/template-soal-examgo.docx
    // Mengarahkan langsung ke Google Docs resmi ExamGo untuk unduh format .docx
    if (path === "/template-soal-examgo.docx" || path === "/template-soal.docx" || path === "/template-soal") {
      return Response.redirect("https://docs.google.com/document/d/1Lq4IiXgU4_EMUuMMJD1Ns3eYL-XRgZkt/export?format=docx", 302);
    }

    // 1.95. RUTE API GURU CREATE EXAM: examgo.id/api/teacher-exam
    // Forward pembuatan paket ujian guru ke Google Apps Script tanpa CORS issue
    if (path === "/api/teacher-exam" || path === "/api/create-teacher-exam") {
      if (request.method === "OPTIONS") {
        return new Response(null, {
          status: 204,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Access-Control-Allow-Headers": "*"
          }
        });
      }
      try {
        const targetGasUrl = GAS_ADMIN_URL.replace("?page=admin", "");
        const body = await request.text();
        const forwardResp = await fetch(targetGasUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: body,
          redirect: "follow"
        });
        const respText = await forwardResp.text();
        if (respText.trim().startsWith("<")) {
          return new Response(JSON.stringify({
            status: "error",
            message: "Server Google Apps Script mengembalikan respon non-JSON. Silakan coba kembali sesaat lagi."
          }), {
            status: 200,
            headers: {
              "Content-Type": "application/json; charset=UTF-8",
              "Access-Control-Allow-Origin": "*"
            }
          });
        }
        return new Response(respText, {
          status: 200,
          headers: {
            "Content-Type": "application/json; charset=UTF-8",
            "Access-Control-Allow-Origin": "*"
          }
        });
      } catch (err) {
        return new Response(JSON.stringify({ status: "error", message: err.message }), {
          status: 200,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      }
    }

    // 1.99. RUTE PORTAL GURU: examgo.id/guru atau examgo.id/upload atau examgo.id/buat-ujian
    // Portal mandiri guru untuk mengunggah soal Word (.docx) atau Google Form dari laptop/PC
    if (path === "/guru" || path === "/upload" || path === "/buat-ujian" || path === "/upload-soal") {
      try {
        const response = await fetch(GITHUB_GURU_PAGE_URL, {
          cf: {
            cacheTtl: 300,
            cacheEverything: true
          }
        });

        if (response.ok) {
          const html = await response.text();
          return new Response(html, {
            headers: {
              "Content-Type": "text/html; charset=UTF-8",
              "Cache-Control": "public, max-age=300",
              "X-Frame-Options": "SAMEORIGIN"
            }
          });
        }
      } catch (err) {
        console.error("Gagal mengambil guru page dari GitHub:", err);
      }

      // Fallback ke GAS Guru page
      const targetGuruUrl = new URL(GAS_ADMIN_URL.replace("?page=admin", "") + "?page=guru");
      url.searchParams.forEach((val, key) => targetGuruUrl.searchParams.set(key, val));
      return fetch(targetGuruUrl.toString(), { redirect: "follow" });
    }

    // 2. RUTE ADMIN: examgo.id/admin disajikan langsung dalam full-viewport shell aman
    // URL browser tetap bertahan di https://examgo.id/admin tanpa pernah dialihkan ke script.google.com
    if (path === "/admin") {
      const targetUrl = new URL(GAS_ADMIN_URL);
      url.searchParams.forEach((val, key) => {
        if (key !== "page") targetUrl.searchParams.set(key, val);
      });

      const adminHtml = `<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>ExamGO — Portal Pengawas & Admin CBT</title>
  <link rel="icon" type="image/png" href="https://raw.githubusercontent.com/ekiq11/Exam-Go/main/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body {
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #090d16;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    #loader {
      position: fixed;
      inset: 0;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: #090d16;
      color: #ffffff;
      z-index: 100;
      transition: opacity 0.3s ease, visibility 0.3s ease;
    }
    .spinner {
      width: 44px;
      height: 44px;
      border: 3.5px solid rgba(16, 185, 129, 0.15);
      border-top-color: #10b981;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin-bottom: 16px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    iframe {
      width: 100%;
      height: 100%;
      border: none;
      display: block;
      background: #090d16;
    }
  </style>
</head>
<body>
  <div id="loader">
    <div class="spinner"></div>
    <div style="font-size: 15px; font-weight: 700; letter-spacing: 0.3px;">ExamGO Admin Portal</div>
    <div style="font-size: 12px; color: #94a3b8; margin-top: 6px;">Menghubungkan ke server aman Google Apps Script...</div>
  </div>
  <iframe id="admin-frame" src="${targetUrl.toString()}" allow="clipboard-read; clipboard-write; fullscreen; camera; microphone" onload="var l=document.getElementById('loader'); if(l){ l.style.opacity='0'; setTimeout(function(){ l.style.display='none'; }, 300); }"></iframe>
</body>
</html>`;

      return new Response(adminHtml, {
        headers: {
          "Content-Type": "text/html; charset=UTF-8",
          "X-Frame-Options": "SAMEORIGIN",
          "Cache-Control": "no-cache, no-store, must-revalidate"
        }
      });
    }

    // 2.4. RUTE SALIN TOKEN: examgo.id/salin?token=... atau examgo.id/copy?token=...
    if (path === "/salin" || path === "/copy" || path === "/salin-token") {
      const rawToken = (url.searchParams.get("token") || url.searchParams.get("code") || "")
        .replace(/[^A-Za-z0-9_-]/g, "")
        .substring(0, 32);
      const copyHtml = `<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Salin Token Lisensi ExamGO</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;700;800&family=JetBrains+Mono:wght@700;800&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0; padding: 20px; font-family: 'Plus Jakarta Sans', sans-serif;
      background: radial-gradient(circle at 50% 20%, #064e3b 0%, #022c22 40%, #090d16 100%);
      color: #f8fafc; min-height: 100vh; display: flex; align-items: center; justify-content: center;
    }
    .card {
      background: rgba(15, 23, 42, 0.95); border: 1px solid rgba(16, 185, 129, 0.35);
      border-radius: 24px; padding: 32px 24px; max-width: 440px; width: 100%;
      text-align: center; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.6);
    }
    .badge {
      display: inline-block; background: rgba(16, 185, 129, 0.15); border: 1px solid rgba(16, 185, 129, 0.4);
      color: #34d399; font-size: 11px; font-weight: 800; text-transform: uppercase;
      letter-spacing: 1px; padding: 5px 14px; border-radius: 999px; margin-bottom: 16px;
    }
    .token-box {
      background: #022c22; border: 2px dashed #10b981; border-radius: 14px;
      padding: 16px; font-family: 'JetBrains Mono', monospace; font-size: 24px;
      font-weight: 800; letter-spacing: 3px; color: #6ee7b7; margin: 18px 0;
      user-select: all; -webkit-user-select: all; word-break: break-all;
    }
    .btn-primary {
      display: block; width: 100%; background: linear-gradient(135deg, #10b981 0%, #059669 100%);
      color: #ffffff; text-decoration: none; font-weight: 800; font-size: 14px;
      padding: 14px; border-radius: 14px; box-shadow: 0 10px 15px -3px rgba(16, 185, 129, 0.3);
      margin-bottom: 10px;
    }
    .btn-secondary {
      display: block; width: 100%; background: #1e293b; color: #cbd5e1;
      text-decoration: none; font-weight: 700; font-size: 13px;
      padding: 12px; border-radius: 14px; border: 1px solid #334155; margin-bottom: 10px;
    }
    .status-copied { color: #34d399; font-size: 13px; font-weight: 700; margin-top: 8px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">LISENSI RESMI EXAMGO</div>
    <h1 style="margin: 0 0 6px; font-size: 22px; font-weight: 800; color: #ffffff;">Token Berhasil Disalin!</h1>
    <p style="margin: 0; font-size: 13px; color: #94a3b8; line-height: 1.5;">Kode token Anda telah otomatis tersalin ke clipboard perangkat Anda:</p>
    <div class="token-box" id="token-display">${rawToken || 'TOKEN-EXAMGO'}</div>
    <div id="copy-status" class="status-copied">✅ Siap ditempel (paste) di aplikasi ExamGO</div>
    <div style="margin-top: 24px;">
      <a href="https://play.google.com/store/apps/details?id=com.kemenag.examgo" class="btn-primary">🚀 Buka / Download di Play Store</a>
      <a href="https://apps.apple.com/id/app/examgo/id6759708435" class="btn-secondary">🍎 Unduh di Apple App Store</a>
      <a href="https://youtu.be/GFUgdGcGHzY" target="_blank" class="btn-secondary" style="border-color: #ef4444; color: #fca5a5;">📺 Tonton Tutorial Upload Soal (YouTube)</a>
    </div>
  </div>
  <script>
    const t = "${rawToken}";
    if (t && navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(t).then(() => {
        const el = document.getElementById('copy-status');
        if (el) el.innerText = '✅ Berhasil disalin ke clipboard!';
      }).catch(() => {});
    }
  </script>
</body>
</html>`;
      return new Response(copyHtml, {
        headers: {
          "Content-Type": "text/html; charset=UTF-8",
          "Cache-Control": "no-cache, no-store, must-revalidate"
        }
      });
    }

    // 2.5. RUTE KEBIJAKAN PRIVASI & TERMS: examgo.id/privacy atau examgo.id/terms
    if (path === "/privacy" || path === "/terms" || path === "/kebijakan-privasi" || path === "/syarat-ketentuan") {
      try {
        const response = await fetch(GITHUB_PRIVACY_PAGE_URL, {
          cf: {
            cacheTtl: 300,
            cacheEverything: true
          }
        });

        if (response.ok) {
          const html = await response.text();
          return new Response(html, {
            headers: {
              "Content-Type": "text/html; charset=UTF-8",
              "Cache-Control": "public, max-age=300",
              "X-Frame-Options": "SAMEORIGIN"
            }
          });
        }
      } catch (err) {
        console.error("Gagal mengambil privacy page dari GitHub:", err);
      }

      // Fallback ke Google Apps Script
      return fetch(GAS_PRIVACY_URL, { redirect: "follow" });
    }

    // 3. RUTE UTAMA: examgo.id menyajikan Landing Page Penjualan & Promosi Resmi
    // Di-cache di Cloudflare Edge Server (Global CDN) agar terbuka instan (< 100ms)
    // dan 100% BEBAS dari error "Maaf, saat ini tidak dapat membuka file" Google Drive.
    try {
      const response = await fetch(GITHUB_LANDING_PAGE_URL, {
        cf: {
          cacheTtl: 300,
          cacheEverything: true
        }
      });

      if (response.ok) {
        const html = await response.text();
        return new Response(html, {
          headers: {
            "Content-Type": "text/html; charset=UTF-8",
            "Cache-Control": "public, max-age=300",
            "X-Frame-Options": "SAMEORIGIN"
          }
        });
      }
    } catch (err) {
      console.error("Gagal mengambil landing page:", err);
    }

    // Fallback cadangan
    return new Response(
      "<!DOCTYPE html><html><head><meta charset='utf-8'><title>ExamGO</title></head><body style='font-family:sans-serif;text-align:center;padding:50px;'><h2>ExamGO sedang memuat...</h2><p>Silakan muat ulang halaman dalam beberapa detik.</p></body></html>",
      {
        status: 200,
        headers: { "Content-Type": "text/html; charset=UTF-8" }
      }
    );
  }
};
