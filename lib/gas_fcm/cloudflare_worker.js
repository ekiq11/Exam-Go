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
const GAS_ADMIN_URL = "https://script.google.com/macros/s/AKfycbyz4bm0GIgLkyGDLBE0u9yPsZnNB6OvObMszvyY-g6UxwlsByBnpnEchoHKrahoay2ZUA/exec?page=admin";
const GAS_PRIVACY_URL = "https://script.google.com/macros/s/AKfycbyz4bm0GIgLkyGDLBE0u9yPsZnNB6OvObMszvyY-g6UxwlsByBnpnEchoHKrahoay2ZUA/exec?page=privacy";
const GAS_WEBHOOK_URL = "https://script.google.com/macros/s/AKfycbyz4bm0GIgLkyGDLBE0u9yPsZnNB6OvObMszvyY-g6UxwlsByBnpnEchoHKrahoay2ZUA/exec?action=webhook_lynk";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.toLowerCase().replace(/\/+$/, "");

    // 1. RUTE WEBHOOK LYNK.ID: examgo.id/webhook atau examgo.id/api/webhook
    // Berfungsi sebagai Reverse Proxy Gateway untuk Lynk.id!
    // Mengubah HTTP 302 redirect dari Google Apps Script menjadi HTTP 200 OK murni,
    // sehingga Lynk.id tidak akan pernah gagal (mengatasi error "Webhook delivery failed (HTTP 302)").
    if (path === "/webhook" || path === "/api/webhook" || path === "/webhook_lynk") {
      // Tangani CORS Preflight jika ada
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
        reqHeaders.delete("host"); // Hapus host cloudflare

        const body = (reqMethod === "POST" || reqMethod === "PUT" || reqMethod === "PATCH") 
          ? await request.text() 
          : undefined;

        // Fetch ke Google Apps Script dengan redirect: "follow"
        const forwardResp = await fetch(GAS_WEBHOOK_URL, {
          method: reqMethod,
          headers: reqHeaders,
          body: body,
          redirect: "follow"
        });

        const respText = await forwardResp.text();
        return new Response(respText, {
          status: 200, // Selalu return 200 OK murni ke Lynk.id
          headers: {
            "Content-Type": forwardResp.headers.get("Content-Type") || "application/json; charset=UTF-8",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS"
          }
        });
      } catch (err) {
        return new Response(JSON.stringify({ status: "error", message: err.message }), {
          status: 200, // Tetap 200 dengan payload JSON agar Lynk.id tidak menganggap drop koneksi
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
