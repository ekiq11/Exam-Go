/**
 * Cloudflare Worker untuk Domain examgo.id
 * 
 * Rute:
 * 1. https://examgo.id         -> Landing Page Resmi (Bebas Google Drive Error, Cepat, Responsif)
 * 2. https://examgo.id/admin   -> Redirect Langsung ke Google Apps Script Admin Console
 * 3. https://examgo.id/webhook -> Reverse Proxy Webhook Lynk.id (Menghilangkan HTTP 302 Redirect & Langsung HTTP 200 OK)
 */

const GITHUB_LANDING_PAGE_URL = "https://raw.githubusercontent.com/ekiq11/Exam-Go/main/lib/gas_fcm/gas/landing.html";
const GAS_ADMIN_URL = "https://script.google.com/macros/s/AKfycbyz4bm0GIgLkyGDLBE0u9yPsZnNB6OvObMszvyY-g6UxwlsByBnpnEchoHKrahoay2ZUA/exec?page=admin";
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

    // 2. RUTE ADMIN: examgo.id/admin langsung redirect ke portal admin
    if (path === "/admin") {
      return Response.redirect(GAS_ADMIN_URL, 302);
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
