import 'package:xml/xml.dart';

/// Utilitas untuk mengonversi notasi matematika umum & Office Math Word ke sintaks LaTeX standar.
/// Memungkinkan guru menulis soal secara alami di Word tanpa perlu mengetik kode LaTeX manual.
class MathLatexConverter {
  /// Peta superskrip Unicode ke angka biasa
  static const Map<String, String> _superscripts = {
    '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4',
    '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9',
    '⁺': '+', '⁻': '-', 'ⁿ': 'n', 'ᵃ': 'a', 'ᵇ': 'b',
    'ˣ': 'x', 'ʸ': 'y',
  };

  /// Peta subskrip Unicode ke angka biasa
  static const Map<String, String> _subscripts = {
    '₀': '0', '₁': '1', '₂': '2', '₃': '3', '₄': '4',
    '₅': '5', '₆': '6', '₇': '7', '₈': '8', '₉': '9',
    '₊': '+', '₋': '-', 'ₐ': 'a', 'ₑ': 'e', 'ₒ': 'o',
    'ₓ': 'x',
  };

  /// Mengonversi teks biasa yang memuat ekspresi matematika umum menjadi LaTeX.
  /// Jika teks memuat tag HTML (<...>) atau sintaks LaTeX ($...$), bagian tersebut dipertahankan.
  static String convertPlainTextToLatex(String input) {
    if (input.trim().isEmpty) return input;

    // Tokenize teks menjadi: tag HTML (<...>), blok LaTeX ($...$), atau teks biasa
    final pattern = RegExp(r'(<[^>]+>|\$[^\$]+\$)');
    final matches = pattern.allMatches(input);
    final sb = StringBuffer();
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        final textBetween = input.substring(lastEnd, match.start);
        sb.write(_convertSegment(textBetween));
      }
      sb.write(match.group(0)); // Pertahankan tag HTML atau blok LaTeX asli
      lastEnd = match.end;
    }

    if (lastEnd < input.length) {
      sb.write(_convertSegment(input.substring(lastEnd)));
    }

    return sb.toString();
  }

  static String _convertSegment(String segment) {
    if (segment.trim().isEmpty) return segment;

    String res = segment;

    // 1. Simbol perbandingan & operasi matematika umum
    res = res.replaceAll('≤', r' \le ');
    res = res.replaceAll('≥', r' \ge ');
    res = res.replaceAll('≠', r' \ne ');
    res = res.replaceAll('±', r' \pm ');
    res = res.replaceAll('×', r' \times ');
    res = res.replaceAll('÷', r' \div ');
    res = res.replaceAll('≈', r' \approx ');
    res = res.replaceAll('°', r'^\circ ');
    res = res.replaceAll('∞', r' \infty ');
    res = res.replaceAll('π', r' \pi ');
    res = res.replaceAll('α', r' \alpha ');
    res = res.replaceAll('β', r' \beta ');
    res = res.replaceAll('θ', r' \theta ');
    res = res.replaceAll('λ', r' \lambda ');

    // 2. Konversi superskrip Unicode: contoh x² -> x^{2}, (a+b)³ -> (a+b)^{3}
    for (final entry in _superscripts.entries) {
      res = res.replaceAll(entry.key, '^{${entry.value}}');
    }

    // 3. Konversi subskrip Unicode: contoh x₁ -> x_{1}
    for (final entry in _subscripts.entries) {
      res = res.replaceAll(entry.key, '_{${entry.value}}');
    }

    // 4. Konversi tanda akar √: contoh √3 -> \sqrt{3}, √(x + 1) -> \sqrt{x + 1}
    res = res.replaceAllMapped(
      RegExp(r'√\(([^)]+)\)'),
      (m) => '\\sqrt{${m.group(1)!}}',
    );
    res = res.replaceAllMapped(
      RegExp(r'√([0-9a-zA-Z]+)'),
      (m) => '\\sqrt{${m.group(1)!}}',
    );

    // 5. Konversi kata "akar X" yang sering diketik guru: misal "akar 3" -> \sqrt{3}
    res = res.replaceAllMapped(
      RegExp(r'\bakar\s+([0-9a-zA-Z]+)\b', caseSensitive: false),
      (m) => '\\sqrt{${m.group(1)!}}',
    );

    // 6. Konversi pecahan bentuk (A) / (B) yang memuat simbol matematika
    res = res.replaceAllMapped(
      RegExp(r'\(([^)]+)\)\s*/\s*\(([^)]+)\)'),
      (m) {
        final num = m.group(1)!.trim();
        final den = m.group(2)!.trim();
        if (_hasMathContent(num) || _hasMathContent(den)) {
          return '\\frac{$num}{$den}';
        }
        return m.group(0)!;
      },
    );

    // 7. Konversi pecahan sederhana seperti \sqrt{...} / N
    res = res.replaceAllMapped(
      RegExp(r'(\\\w+{[^}]+}(?:\s*[\+\-]\s*\\\w+{[^}]+})*)\s*/\s*([0-9a-zA-Z]+)'),
      (m) => '\\frac{${m.group(1)!.trim()}}{${m.group(2)!.trim()}}',
    );

    // 8. Deteksi jika segmen memiliki formula matematika (ada \sqrt, \frac, ^{...}, x = ...):
    // Bungkus bagian rumus dengan $ agar flutter_math merendernya
    return _wrapFormulasInDollar(res);
  }

  static bool _hasMathContent(String s) {
    return s.contains(r'\') ||
        s.contains('^') ||
        s.contains('_') ||
        s.contains('√') ||
        RegExp(r'[0-9a-zA-Z]\s*[\+\-\*\/=]\s*[0-9a-zA-Z]').hasMatch(s);
  }

  static String _wrapFormulasInDollar(String text) {
    String res = text;

    // 1. Tangkap persamaan / pertidaksamaan matematika lengkap:
    // Contoh: "x^{2} + 2x - 15 = 0" atau "(x + 5)(x - 3) = 0" atau "x = 3" atau "x > 0"
    res = res.replaceAllMapped(
      RegExp(r'(?<!\$)\b([a-zA-Z0-9\(\)\{\}\^\_\+\-\*\/\\]+(?:\s*[+\-*\/]\s*[a-zA-Z0-9\(\)\{\}\^\_\+\-\*\/\\]+)*\s*(?:=|\\ge|\\le|>|<|\\ne|\\approx)\s*[a-zA-Z0-9\(\)\{\}\^\_\+\-\*\/\\]+(?:\s*[+\-*\/]\s*[a-zA-Z0-9\(\)\{\}\^\_\+\-\*\/\\]+)*)\b(?!\$)'),
      (m) => '\$${m.group(1)!.trim()}\$',
    );

    // 2. Tangkap ekspresi pecahan \frac{...}{...} atau akar \sqrt{...} yang belum diapit $
    res = res.replaceAllMapped(
      RegExp(r'(?<!\$)((\\frac\{[^{}]*\}\{[^{}]*\}|\\sqrt(?:\[[^\]]*\])?\{[^{}]*\})(?:\s*[+\-*\/]\s*(?:\\frac\{[^{}]*\}\{[^{}]*\}|\\sqrt(?:\[[^\]]*\])?\{[^{}]*\}|[a-zA-Z0-9]+))*)(?!\$)'),
      (m) => '\$${m.group(1)!.trim()}\$',
    );

    // 3. Tangkap variabel berpangkat / bersubskrip yang berdiri sendiri: contoh x^{2}, y_{1}
    res = res.replaceAllMapped(
      RegExp(r'(?<!\$)\b([a-zA-Z0-9]+(?:\^\{[^{}]+\}|_\{[^{}]+\}))\b(?!\$)'),
      (m) => '\$${m.group(1)!}\$',
    );

    // 4. Bersihkan double dollar bertetangga jika ada: $...$ $...$ -> $... ...$
    res = res.replaceAllMapped(
      RegExp(r'\$([^\$]+)\$\s*\$([^\$]+)\$'),
      (m) => '\$${m.group(1)!} ${m.group(2)!}\$',
    );

    return res;
  }

  /// Mengonversi elemen XML Equation Word (`<m:oMath>` atau `<m:oMathPara>`) menjadi sintaks LaTeX.
  static String convertOMathElementToLatex(XmlElement node) {
    final sb = StringBuffer();
    _parseOMathNode(node, sb);
    final math = sb.toString().trim();
    if (math.isEmpty) return '';
    return '\$$math\$';
  }

  static void _parseOMathNode(XmlNode node, StringBuffer sb) {
    if (node is XmlElement) {
      final name = node.name.local;

      switch (name) {
        case 't': // Math Text
          sb.write(node.innerText);
          break;

        case 'f': // Fraction: <m:f><m:num>...</m:num><m:den>...</m:den></m:f>
          final numEl = node.findElements('m:num').firstOrNull ?? node.findElements('num').firstOrNull;
          final denEl = node.findElements('m:den').firstOrNull ?? node.findElements('den').firstOrNull;
          sb.write(r'\frac{');
          if (numEl != null) _parseOMathNode(numEl, sb);
          sb.write('}{');
          if (denEl != null) _parseOMathNode(denEl, sb);
          sb.write('}');
          break;

        case 'rad': // Radical / Akar: <m:rad><m:radPr><m:deg/></m:radPr><m:e>...</m:e></m:rad>
          final degEl = node.findAllElements('m:deg').firstOrNull ?? node.findAllElements('deg').firstOrNull;
          final eEl = node.findElements('m:e').firstOrNull ?? node.findElements('e').firstOrNull;
          final degText = degEl?.innerText.trim() ?? '';
          if (degText.isNotEmpty) {
            sb.write('\\sqrt[$degText]{');
          } else {
            sb.write(r'\sqrt{');
          }
          if (eEl != null) _parseOMathNode(eEl, sb);
          sb.write('}');
          break;

        case 'sSup': // Superscript / Pangkat: <m:sSup><m:e>...</m:e><m:sup>...</m:sup></m:sSup>
          final baseEl = node.findElements('m:e').firstOrNull ?? node.findElements('e').firstOrNull;
          final supEl = node.findElements('m:sup').firstOrNull ?? node.findElements('sup').firstOrNull;
          sb.write('{');
          if (baseEl != null) _parseOMathNode(baseEl, sb);
          sb.write('}^{');
          if (supEl != null) _parseOMathNode(supEl, sb);
          sb.write('}');
          break;

        case 'sSub': // Subscript: <m:sSub><m:e>...</m:e><m:sub>...</m:sub></m:sSub>
          final baseSub = node.findElements('m:e').firstOrNull ?? node.findElements('e').firstOrNull;
          final subEl = node.findElements('m:sub').firstOrNull ?? node.findElements('sub').firstOrNull;
          sb.write('{');
          if (baseSub != null) _parseOMathNode(baseSub, sb);
          sb.write('}_{');
          if (subEl != null) _parseOMathNode(subEl, sb);
          sb.write('}');
          break;

        case 'sSubSup': // Sub-Superscript ganda
          final baseSubSup = node.findElements('m:e').firstOrNull ?? node.findElements('e').firstOrNull;
          final subPart = node.findElements('m:sub').firstOrNull ?? node.findElements('sub').firstOrNull;
          final supPart = node.findElements('m:sup').firstOrNull ?? node.findElements('sup').firstOrNull;
          sb.write('{');
          if (baseSubSup != null) _parseOMathNode(baseSubSup, sb);
          sb.write('}_{');
          if (subPart != null) _parseOMathNode(subPart, sb);
          sb.write('}^{');
          if (supPart != null) _parseOMathNode(supPart, sb);
          sb.write('}');
          break;

        case 'd': // Delimiter: kurung ( )
          final eDelim = node.findElements('m:e').firstOrNull ?? node.findElements('e').firstOrNull;
          sb.write(r'\left(');
          if (eDelim != null) _parseOMathNode(eDelim, sb);
          sb.write(r'\right)');
          break;

        default:
          for (final child in node.children) {
            _parseOMathNode(child, sb);
          }
      }
    }
  }
}
