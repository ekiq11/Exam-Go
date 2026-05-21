import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/utils/webview_error_handler.dart';

void main() {
  group('WebViewErrorHandler TDD Tests', () {
    test('Identifies OOM Error', () {
      final msg = WebViewErrorHandler.getErrorMessage(-12, 'net::ERR_OUT_OF_MEMORY');
      expect(msg, contains('memori'));
      
      final shouldRetry = WebViewErrorHandler.shouldRetrySilently(-12);
      expect(shouldRetry, isFalse);
    });

    test('Identifies Network Disconnected', () {
      final msg = WebViewErrorHandler.getErrorMessage(-2, 'net::ERR_INTERNET_DISCONNECTED');
      expect(msg, contains('Koneksi terputus'));
      
      final shouldRetry = WebViewErrorHandler.shouldRetrySilently(-2);
      expect(shouldRetry, isTrue);
    });

    test('Identifies Timeout', () {
      final msg = WebViewErrorHandler.getErrorMessage(-8, 'net::ERR_CONNECTION_TIMED_OUT');
      expect(msg, contains('Waktu koneksi habis'));
      
      final shouldRetry = WebViewErrorHandler.shouldRetrySilently(-8);
      expect(shouldRetry, isTrue);
    });

    test('Fallback generic error', () {
      final msg = WebViewErrorHandler.getErrorMessage(-999, 'UNKNOWN_ERR');
      expect(msg, contains('Gagal memuat'));
      
      final shouldRetry = WebViewErrorHandler.shouldRetrySilently(-999);
      expect(shouldRetry, isFalse);
    });
  });
}
