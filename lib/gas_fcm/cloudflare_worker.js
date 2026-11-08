/**
 * Cloudflare Worker untuk Domain examgo.id
 * 
 * Rute:
 * 1. https://examgo.id         -> Landing Page Resmi (Bebas Google Drive Error, Cepat, Responsif)
 * 2. https://examgo.id/admin   -> Redirect Langsung ke Google Apps Script Admin Console
 */

const GITHUB_LANDING_PAGE_URL = "https://raw.githubusercontent.com/ekiq11/Exam-Go/main/lib/gas_fcm/gas/landing.html";
const GAS_ADMIN_URL = "https://script.google.com/a/macros/myolc.my.id/s/AKfycbyz4bm0GIgLkyGDLBE0u9yPsZnNB6OvObMszvyY-g6UxwlsByBnpnEchoHKrahoay2ZUA/exec?page=admin";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.toLowerCase().replace(/\/+$/, "");

    // 1. RUTE ADMIN: examgo.id/admin langsung redirect ke portal admin
    // Menggunakan redirect browser agar session login Google (@myolc.my.id) 
    // aktif sempurna tanpa diblokir oleh sistem keamanan third-party cookies Chrome.
    if (path === "/admin") {
      return Response.redirect(GAS_ADMIN_URL, 302);
    }

    // 2. RUTE UTAMA: examgo.id menyajikan Landing Page Penjualan & Promosi Resmi
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
