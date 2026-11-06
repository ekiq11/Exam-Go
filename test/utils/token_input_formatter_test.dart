import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/utils/token_input_formatter.dart';

void main() {
  group('TokenInputFormatter Tests', () {
    final formatter = TokenInputFormatter();

    TextEditingValue format(String text) {
      return formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
    }

    test('Formats SISWA token with 5-letter prefix correctly without mangling', () {
      // Mengetik kata SISWA tidak boleh ada tanda strip di tengah (misal SISW-A)
      expect(format('siswa').text, equals('SISWA'));
      expect(format('SISWA').text, equals('SISWA'));
      
      // Lanjut mengetik karakter setelah SISWA
      expect(format('siswa7').text, equals('SISWA-7'));
      expect(format('siswa7k9p').text, equals('SISWA-7K9P'));
      expect(format('siswa7k9p2').text, equals('SISWA-7K9P-2'));
      expect(format('siswa7k9p2m4q').text, equals('SISWA-7K9P-2M4Q'));
    });

    test('Formats GURU token with 4-letter prefix correctly', () {
      expect(format('guru').text, equals('GURU'));
      expect(format('guru1').text, equals('GURU-1'));
      expect(format('guru1234').text, equals('GURU-1234'));
      expect(format('guru1234abcd').text, equals('GURU-1234-ABCD'));
    });

    test('Pasting token with or without dashes formats cleanly', () {
      // Paste dari email Lynk.id
      expect(format('SISWA-7K9P-2M4Q').text, equals('SISWA-7K9P-2M4Q'));
      expect(format('GURU-ABCD-1234').text, equals('GURU-ABCD-1234'));
      
      // Paste tanpa tanda strip
      expect(format('SISWA7K9P2M4Q').text, equals('SISWA-7K9P-2M4Q'));
      expect(format('GURUABCD1234').text, equals('GURU-ABCD-1234'));
    });

    test('Generic 4-character tokens (misal TONAS2026 atau kode acak)', () {
      expect(format('abcd1234').text, equals('ABCD-1234'));
      expect(format('12345678abcd').text, equals('1234-5678-ABCD'));
    });
  });
}

