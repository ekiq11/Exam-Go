class WebViewErrorHandler {
  /// Analyzes WebView errors to determine if a retry is feasible
  /// or if the user should be shown a fatal error (like OOM or Network loss).
  static String getErrorMessage(int errorCode, String description) {
    if (description.toLowerCase().contains('out of memory') || errorCode == -12) {
      return 'Perangkat kehabisan memori. Harap tutup aplikasi lain dan coba lagi.';
    }
    
    if (errorCode == -2 || description.toLowerCase().contains('net::err_internet_disconnected')) {
      return 'Koneksi terputus. Harap periksa jaringan internet Anda.';
    }
    
    if (errorCode == -8 || description.toLowerCase().contains('net::err_connection_timed_out')) {
      return 'Waktu koneksi habis. Server ujian mungkin sedang sibuk.';
    }

    return 'Gagal memuat halaman ujian (Kode: $errorCode).';
  }

  static bool shouldRetrySilently(int errorCode) {
    // Retry silently for temporary network glitches, but not OOM
    return errorCode == -8 || errorCode == -2;
  }
}
