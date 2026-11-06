import 'package:flutter/services.dart';

/// Formatter pintar untuk kode lisensi dan token:
/// - Otomatis kapital (uppercase)
/// - Format prefix SISWA (5 karakter): SISWA-XXXX-YYYY
/// - Format prefix GURU (4 karakter): GURU-XXXX-YYYY
/// - Format umum (kelipatan 4 karakter): XXXX-YYYY-ZZZZ
class TokenInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.toUpperCase();
    final clean = text.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    if (clean.isEmpty) {
      return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
    }

    String formatted = '';

    if (clean.startsWith('SISWA')) {
      // Prefix 5 huruf: SISWA-XXXX-YYYY (Maks 13 karakter bersih / 15 berformat)
      final buf = StringBuffer();
      final len = clean.length.clamp(0, 13);
      buf.write(clean.substring(0, len > 5 ? 5 : len));
      if (len > 5) {
        buf.write('-');
        buf.write(clean.substring(5, len > 9 ? 9 : len));
      }
      if (len > 9) {
        buf.write('-');
        buf.write(clean.substring(9, len));
      }
      formatted = buf.toString();
    } else if (clean.startsWith('GURU')) {
      // Prefix 4 huruf: GURU-XXXX-YYYY (Maks 12 karakter bersih / 14 berformat)
      final buf = StringBuffer();
      final len = clean.length.clamp(0, 12);
      buf.write(clean.substring(0, len > 4 ? 4 : len));
      if (len > 4) {
        buf.write('-');
        buf.write(clean.substring(4, len > 8 ? 8 : len));
      }
      if (len > 8) {
        buf.write('-');
        buf.write(clean.substring(8, len));
      }
      formatted = buf.toString();
    } else {
      // Format umum per 4 karakter: XXXX-YYYY-ZZZZ (Maks 16 karakter bersih)
      final buf = StringBuffer();
      for (int i = 0; i < clean.length && i < 16; i++) {
        if (i > 0 && i % 4 == 0) buf.write('-');
        buf.write(clean[i]);
      }
      formatted = buf.toString();
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
