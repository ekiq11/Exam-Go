import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/utils/math_widget_factory.dart';
import 'package:examgo/services/math_latex_converter.dart';

void main() {
  group('MathHtmlFormatter & LaTeX rendering tests', () {
    test(r'Mengubah inline LaTeX $...$ menjadi span math-tex', () {
      const input = r'Jika $x + 2 = 5$, maka nilai x adalah 3.';
      final output = MathHtmlFormatter.format(input);

      expect(output, contains('class="math-tex inline"'));
      expect(output, contains('data-math="x%20%2B%202%20%3D%205"'));
    });

    test(r'Mengubah display LaTeX $$...$$ menjadi span math-tex display', () {
      const input = "Rumus Pythagoras:\n\$\$a^2 + b^2 = c^2\$\$";
      final output = MathHtmlFormatter.format(input);

      expect(output, contains('class="math-tex display"'));
      expect(output, contains('data-math="a%5E2%20%2B%20b%5E2%20%3D%20c%5E2"'));
    });

    test('Mengubah pecahan dan akar dalam LaTeX', () {
      const input = r'Hitunglah nilai dari $\frac{1}{2} + \sqrt{16}$.';
      final output = MathHtmlFormatter.format(input);

      expect(output, contains('class="math-tex inline"'));
      expect(
        output,
        contains('data-math="%5Cfrac%7B1%7D%7B2%7D%20%2B%20%5Csqrt%7B16%7D"'),
      );
    });

    test('Mengonversi link Google Drive thumbnail dan uc menjadi viewable CDN', () {
      // 1. Google Drive ID biasa
      const rawId = '1djyOjoZrPjcVzh21B9BY_cT3oRHnaRB5';
      final converted1 = MathHtmlFormatter.convertDriveUrl(rawId);
      expect(
        converted1,
        equals(
          'https://lh3.googleusercontent.com/d/1djyOjoZrPjcVzh21B9BY_cT3oRHnaRB5',
        ),
      );

      // 2. Google Drive file URL
      const fileUrl =
          'https://drive.google.com/file/d/1djyOjoZrPjcVzh21B9BY_cT3oRHnaRB5/view?usp=sharing';
      final converted2 = MathHtmlFormatter.convertDriveUrl(fileUrl);
      expect(
        converted2,
        equals(
          'https://lh3.googleusercontent.com/d/1djyOjoZrPjcVzh21B9BY_cT3oRHnaRB5',
        ),
      );

      // 3. Google Drive thumbnail URL
      const thumbUrl =
          'https://drive.google.com/thumbnail?id=1djyOjoZrPjcVzh21B9BY_cT3oRHnaRB5&sz=w1000';
      final converted3 = MathHtmlFormatter.convertDriveUrl(thumbUrl);
      expect(
        converted3,
        equals(
          'https://lh3.googleusercontent.com/d/1djyOjoZrPjcVzh21B9BY_cT3oRHnaRB5',
        ),
      );
    });

    test(
      'MathLatexConverter mengonversi Unicode matematika & superskrip ke LaTeX',
      () {
        const input = 'x² + 2x ≤ 10';
        final latex = MathLatexConverter.convertPlainTextToLatex(input);

        expect(latex, contains(r'x^{2}'));
        expect(latex, contains(r'\le'));
      },
    );

    test(r'MathLatexConverter mempertahankan blok $...$ yang sudah ada', () {
      const input = r'Hitung nilai $\sqrt{x^2 + y^2}$.';
      final latex = MathLatexConverter.convertPlainTextToLatex(input);

      expect(latex, equals(input));
    });

    test('MathHtmlFormatter mengenali LaTeX dalam kurung biasa misal (\\frac{5}{11})', () {
      const input = r'Satuan Tugas menyatakan pada Sabtu (\frac{5}{11}), penambahan kasus.';
      final output = MathHtmlFormatter.format(input);

      expect(output, contains('class="math-tex inline"'));
      expect(output, contains(Uri.encodeComponent(r'\frac{5}{11}')));
    });

    test('MathHtmlFormatter mengubah \\pm lepas menjadi simbol ±', () {
      const input = r'Menghasilkan \pm 2.971 kilometer.';
      final output = MathHtmlFormatter.format(input);

      expect(output, contains('± 2.971'));
      expect(output, isNot(contains(r'\pm')));
    });

    test('MathHtmlFormatter mengenali format \\(...\\) dan \\[...\\] tanpa merusak kontennya', () {
      const input = r'Selesaikan persamaan \(\frac{1}{2}x + 3 = 7\) dan rumus display: \[E = mc^2\]';
      final output = MathHtmlFormatter.format(input);

      expect(output, contains('class="math-tex inline"'));
      expect(output, contains(Uri.encodeComponent(r'\frac{1}{2}x + 3 = 7')));
      expect(output, contains('class="math-tex display"'));
      expect(output, contains(Uri.encodeComponent(r'E = mc^2')));
    });

    test('MathHtmlFormatter menangani pecahan dengan nested braces di pembilang atau penyebut', () {
      const input = r'Bentuk sederhana dari \frac{\sqrt{3} + 1}{2} adalah...';
      final output = MathHtmlFormatter.format(input);

      expect(output, contains('class="math-tex inline"'));
      expect(output, contains(Uri.encodeComponent(r'\frac{\sqrt{3} + 1}{2}')));
    });
  });
}
