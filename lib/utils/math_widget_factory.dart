import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart' as fwfh;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/math_latex_converter.dart';

/// Factory widget untuk merender tag matematika LaTeX di dalam flutter_widget_from_html
class MathWidgetFactory extends fwfh.WidgetFactory {
  final double fontSize;
  MathWidgetFactory({this.fontSize = 14.5});

  @override
  void parse(BuildTree meta) {
    if (meta.element.classes.contains('math-tex')) {
      final isDisplay = meta.element.classes.contains('display');
      final rawData = meta.element.attributes['data-math'] ?? '';
      String text = rawData;
      try {
        text = Uri.decodeComponent(rawData);
      } catch (_) {}

      // Sanitasi kode LaTeX agar ramah parsing KaTeX
      final sanitizedText = _sanitizeLatexForKatex(text);

      meta.register(BuildOp(
        onVisitChild: (tree, subTree) => false,
        onParsed: (tree) {
          final widget = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              sanitizedText,
              mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
              textStyle: TextStyle(fontSize: fontSize),
              onErrorFallback: (err) => Text(
                _latexToHumanReadable(text),
                style: TextStyle(
                  color: const Color(0xFF1E293B),
                  fontSize: fontSize,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );

          if (isDisplay) {
            tree.append(WidgetBit.block(
              tree,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: widget,
              ),
            ));
          } else {
            tree.append(WidgetBit.inline(
              tree,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: widget,
              ),
            ));
          }
          return tree;
        },
      ));
      return;
    }
    super.parse(meta);
  }

  /// Membersihkan sintaks LaTeX umum yang sering salah format dari Google Forms / Word
  static String _sanitizeLatexForKatex(String text) {
    String res = text.trim();

    // 0. Hapus pembungkus $ atau $$ jika tersisa di dalam data-math
    if (res.startsWith(r'$$') && res.endsWith(r'$$') && res.length >= 4) {
      res = res.substring(2, res.length - 2).trim();
    } else if (res.startsWith(r'$') && res.endsWith(r'$') && res.length >= 2) {
      res = res.substring(1, res.length - 1).trim();
    }
    // Hapus pembungkus \( \) atau \[ \] jika tersisa
    if (res.startsWith(r'\(') && res.endsWith(r'\)') && res.length >= 4) {
      res = res.substring(2, res.length - 2).trim();
    } else if (res.startsWith(r'\[') && res.endsWith(r'\]') && res.length >= 4) {
      res = res.substring(2, res.length - 2).trim();
    }

    // Bersihkan tanda dollar liar di dalam data-math (KaTeX selalu berjalan di math mode)
    res = res.replaceAll(RegExp(r'(?<!\\)\$'), '');

    // 1. Normalisasi backslash berlebih (contoh: \\frac -> \frac)
    res = res.replaceAll(RegExp(r'\\{2,}([a-zA-Z])'), r'\\$1');

    // 2. Escape persen lepas agar tidak dianggap komentar LaTeX yang memotong rumus
    res = res.replaceAllMapped(RegExp(r'(?<!\\)%'), (m) => r'\%');

    // 3. Bersihkan backslash menggantung di akhir
    res = res.replaceAll(RegExp(r'\\+$'), '');

    return res;
  }

  /// Fallback konversi kode LaTeX ke teks matematika Unicode yang terbaca alami
  static String _latexToHumanReadable(String text) {
    String res = text;
    res = res.replaceAll(RegExp(r'\\{2,}'), r'\');

    // Pecahan \frac{A}{B} -> (A / B)
    res = res.replaceAllMapped(
      RegExp(r'\\frac\{([^{}]*)\}\{([^{}]*)\}'),
      (m) => '(${m.group(1)} / ${m.group(2)})',
    );

    // Akar \sqrt{A} -> √(A)
    res = res.replaceAllMapped(
      RegExp(r'\\sqrt(?:\[[^\]]*\])?\{([^{}]*)\}'),
      (m) => '√(${m.group(1)})',
    );

    res = res.replaceAll(r'\times', '×');
    res = res.replaceAll(r'\div', '÷');
    res = res.replaceAll(r'\pm', '±');
    res = res.replaceAll(r'\le', '≤');
    res = res.replaceAll(r'\ge', '≥');
    res = res.replaceAll(r'\ne', '≠');
    res = res.replaceAll(r'\cdot', '·');
    res = res.replaceAll(r'\approx', '≈');
    res = res.replaceAll(r'\infty', '∞');
    res = res.replaceAll(r'\pi', 'π');
    res = res.replaceAll(r'^\circ', '°');

    res = res.replaceAllMapped(
      RegExp(r'\\text\{([^{}]*)\}'),
      (m) => m.group(1)!,
    );

    res = res.replaceAll('{', '').replaceAll('}', '');
    res = res.replaceAll(r'\', '');

    return res.trim();
  }
}

/// Helper utilitas untuk normalisasi teks soal & format LaTeX ke HTML
class MathHtmlFormatter {
  MathHtmlFormatter._();

  /// Mengubah rumus LaTeX ($...$, $$...$$, \(...\), \[...\]) menjadi tag HTML
  /// yang dapat dibaca oleh MathWidgetFactory.
  static String format(String text) {
    if (text.isEmpty) return '';

    // Normalisasi line break
    String html = text.replaceAll('\r\n', '\n');

    // Normalisasi backslash berlebih sebelum perintah LaTeX
    html = html.replaceAll(RegExp(r'\\{2,}([a-zA-Z\(\)\[\]])'), r'\\$1');

    // 1. Tangani ekspresi kurung biasa yang memuat perintah LaTeX tanpa $ atau \(:
    // Contoh: (\frac{5}{11}) -> \(\frac{5}{11}\)
    html = html.replaceAllMapped(
      RegExp(r'\(([^)]*\\[a-zA-Z]+[^)]*)\)'),
      (match) => '\\(${match.group(1)!}\\)',
    );

    // 2. Konversi ekspresi teks matematika dan bungkus rumus bare (\frac, \sqrt, dll) ke sintaks LaTeX standar ($...$)
    html = MathLatexConverter.convertPlainTextToLatex(html);

    // 3. Konversi simbol matematika tunggal yang lepas di luar rumus ke simbol Unicode ramah-baca
    html = html.replaceAll(RegExp(r'(?<!\$)\\(pm|plusminus)(?!\w)(?!\$)'), '±');
    html = html.replaceAll(RegExp(r'(?<!\$)\\times(?!\w)(?!\$)'), '×');
    html = html.replaceAll(RegExp(r'(?<!\$)\\div(?!\w)(?!\$)'), '÷');
    html = html.replaceAll(RegExp(r'(?<!\$)\\le(q)?(?!\w)(?!\$)'), '≤');
    html = html.replaceAll(RegExp(r'(?<!\$)\\ge(q)?(?!\w)(?!\$)'), '≥');
    html = html.replaceAll(RegExp(r'(?<!\$)\\ne(q)?(?!\w)(?!\$)'), '≠');
    html = html.replaceAll(RegExp(r'(?<!\$)\\approx(?!\w)(?!\$)'), '≈');
    html = html.replaceAll(RegExp(r'(?<!\$)\\infty(?!\w)(?!\$)'), '∞');
    html = html.replaceAll(RegExp(r'(?<!\$)\\(degree|deg)(?!\w)(?!\$)'), '°');
    html = html.replaceAll(RegExp(r'(?<!\$)\\sim(?!\w)(?!\$)'), '~');
    html = html.replaceAll(RegExp(r'(?<!\$)\\rightarrow(?!\w)(?!\$)'), '→');
    html = html.replaceAll(RegExp(r'(?<!\$)\\leftarrow(?!\w)(?!\$)'), '←');
    html = html.replaceAll(RegExp(r'(?<!\$)\\alpha(?!\w)(?!\$)'), 'α');
    html = html.replaceAll(RegExp(r'(?<!\$)\\beta(?!\w)(?!\$)'), 'β');
    html = html.replaceAll(RegExp(r'(?<!\$)\\pi(?!\w)(?!\$)'), 'π');

    // Decode HTML entities umum dari dokumen/web
    html = html.replaceAll('&le;', '≤');
    html = html.replaceAll('&ge;', '≥');
    html = html.replaceAll('&plusmn;', '±');
    html = html.replaceAll('&times;', '×');
    html = html.replaceAll('&divide;', '÷');
    html = html.replaceAll('&ne;', '≠');
    html = html.replaceAll('&deg;', '°');
    html = html.replaceAll('&nbsp;', ' ');

    // Normalisasi tag HTML bold & italic standar
    html = html.replaceAll(RegExp(r'<strong(?:\s+[^>]*)?>', caseSensitive: false), '<b>');
    html = html.replaceAll(RegExp(r'<\/strong>', caseSensitive: false), '</b>');
    html = html.replaceAll(RegExp(r'<em(?:\s+[^>]*)?>', caseSensitive: false), '<i>');
    html = html.replaceAll(RegExp(r'<\/em>', caseSensitive: false), '</i>');
    html = html.replaceAll(RegExp(r'<b(?:\s+[^>]*)?>', caseSensitive: false), '<b>');
    html = html.replaceAll(RegExp(r'<\/b>', caseSensitive: false), '</b>');
    html = html.replaceAll(RegExp(r'<i(?:\s+[^>]*)?>', caseSensitive: false), '<i>');
    html = html.replaceAll(RegExp(r'<\/i>', caseSensitive: false), '</i>');
    html = html.replaceAll(RegExp(r'<u(?:\s+[^>]*)?>', caseSensitive: false), '<u>');
    html = html.replaceAll(RegExp(r'<\/u>', caseSensitive: false), '</u>');

    // Konversi tabel format Markdown (| Kolom 1 | Kolom 2 |) jika ada di teks soal
    if (html.contains('|') && html.contains('---')) {
      final lines = html.split('\n');
      final newLines = <String>[];
      final tableBuffer = <String>[];
      bool inTable = false;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
          inTable = true;
          tableBuffer.add(trimmed);
        } else {
          if (inTable && tableBuffer.isNotEmpty) {
            newLines.add(_renderMarkdownTableHtml(tableBuffer));
            tableBuffer.clear();
            inTable = false;
          }
          newLines.add(line);
        }
      }
      if (inTable && tableBuffer.isNotEmpty) {
        newLines.add(_renderMarkdownTableHtml(tableBuffer));
      }
      html = newLines.join('\n');
    }

    // Bold (**text**) & Italic (*text*)
    html = html.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*', dotAll: true),
      (match) => '<b>${match.group(1)}</b>',
    );
    html = html.replaceAllMapped(
      RegExp(r'(?<![A-Za-z0-9_\*])\*([^*\n]+)\*(?![A-Za-z0-9_\*])', dotAll: true),
      (match) => '<i>${match.group(1)}</i>',
    );

    // Normalisasi backslash berlebih pada pembungkus LaTeX
    html = html.replaceAll(RegExp(r'\\{3,}\('), r'\(');
    html = html.replaceAll(RegExp(r'\\{3,}\)'), r'\)');
    html = html.replaceAll(RegExp(r'\\{3,}\['), r'\[');
    html = html.replaceAll(RegExp(r'\\{3,}\]'), r'\]');

    // $$...$$ → display math (block)
    html = html.replaceAllMapped(RegExp(r'\$\$(.*?)\$\$', dotAll: true), (match) {
      final mathStr = Uri.encodeComponent(match.group(1)!.trim());
      return '<span class="math-tex display" data-math="$mathStr"></span>';
    });

    // \[...\] → display math (block)
    html = html.replaceAllMapped(RegExp(r'\\\[(.*?)\\\]', dotAll: true), (match) {
      final mathStr = Uri.encodeComponent(match.group(1)!.trim());
      return '<span class="math-tex display" data-math="$mathStr"></span>';
    });

    // \(...\) → inline math
    html = html.replaceAllMapped(RegExp(r'\\\((.*?)\\\)', dotAll: true), (match) {
      final mathStr = Uri.encodeComponent(match.group(1)!.trim());
      return '<span class="math-tex inline" data-math="$mathStr"></span>';
    });

    // $...$ → inline math (single dollar, diproses setelah $$, mendukung formula multi-baris)
    html = html.replaceAllMapped(RegExp(r'\$([^\$]+?)\$', dotAll: true), (match) {
      final inner = match.group(1)!.trim();
      if (inner.isEmpty) return '';
      final mathStr = Uri.encodeComponent(inner);
      return '<span class="math-tex inline" data-math="$mathStr"></span>';
    });

    // Normalisasi tag <table> HTML agar selalu scrollable horizontal & bergaris rapi
    if (html.contains('<table') && !html.contains('overflow-x:auto') && !html.contains('overflow-x')) {
      html = html.replaceAllMapped(
        RegExp(r'<table(?:\s+[^>]*)?>[\s\S]*?<\/table>', caseSensitive: false),
        (match) {
          String tbl = match.group(0)!;
          if (!tbl.contains('border=')) {
            tbl = tbl.replaceFirst(
              RegExp(r'<table(?:\s+[^>]*)?>', caseSensitive: false),
              '<table border="1" cellpadding="6" style="border-collapse:collapse;width:100%;font-size:12.5px;border-color:#cbd5e1;">',
            );
          }
          return '<div style="overflow-x:auto;margin:8px 0;">$tbl</div>';
        },
      );
    }

    // Replace newline dengan <br/> jika belum dibungkus tag HTML blok
    if (!html.contains('<p>') && !html.contains('<div>')) {
      if (!html.contains('<table')) {
        html = html.replaceAll('\n', '<br/>');
      } else {
        // Ganti baris baru di luar tabel dengan <br/> agar wacana tetap rapi
        final parts = html.split(RegExp(r'(<div[^>]*>[\s\S]*?<\/div>|<table[\s\S]*?<\/table>)', caseSensitive: false));
        final matches = RegExp(r'(<div[^>]*>[\s\S]*?<\/div>|<table[\s\S]*?<\/table>)', caseSensitive: false).allMatches(html).toList();
        final sb = StringBuffer();
        for (int i = 0; i < parts.length; i++) {
          sb.write(parts[i].replaceAll('\n', '<br/>'));
          if (i < matches.length) {
            sb.write(matches[i].group(0));
          }
        }
        html = sb.toString();
      }
    }

    return html;
  }

  /// Mengonversi baris tabel Markdown menjadi tag <table> HTML bersih & rapi
  static String _renderMarkdownTableHtml(List<String> lines) {
    if (lines.isEmpty) return '';
    final rows = <List<String>>[];

    for (final line in lines) {
      if (line.contains('---')) continue;
      final parts = line.split('|');
      if (parts.length > 2) {
        final cells = parts.sublist(1, parts.length - 1).map((c) => c.trim()).toList();
        if (cells.isNotEmpty) rows.add(cells);
      }
    }

    if (rows.isEmpty) return lines.join('\n');

    final sb = StringBuffer();
    sb.writeln('<div style="overflow-x:auto;margin:8px 0;">');
    sb.writeln('<table border="1" cellpadding="6" style="border-collapse:collapse;width:100%;font-size:12.5px;border-color:#cbd5e1;">');

    for (int i = 0; i < rows.length; i++) {
      final isHeader = i == 0;
      final bg = isHeader ? '#f1f5f9' : (i.isEven ? '#fafafa' : '#ffffff');
      sb.writeln('<tr style="background-color:$bg;">');
      for (final cell in rows[i]) {
        final tag = isHeader ? 'th' : 'td';
        final weight = isHeader ? 'font-weight:600;' : '';
        sb.writeln('<$tag style="padding:6px 10px;border:1px solid #e2e8f0;$weight">$cell</$tag>');
      }
      sb.writeln('</tr>');
    }

    sb.writeln('</table>');
    sb.writeln('</div>');
    return sb.toString();
  }

  /// Header HTTP default untuk memuat gambar CDN (seperti Google Forms / Google Drive) tanpa diblokir oleh bot-protection / WAF
  static const Map<String, String> networkImageHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'Referer': 'https://docs.google.com/',
  };

  /// Menormalisasi link Google Drive / Google Form ke CDN resmi Google (lh3.googleusercontent.com)
  /// agar bebas dari blokir CORS, anti-hotlinking, dan cookie browser.
  static String convertDriveUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('data:image/')) return url;
    if (url.startsWith('/api/proxy-image?url=')) {
      final param = url.replaceFirst('/api/proxy-image?url=', '');
      try {
        return Uri.decodeComponent(param);
      } catch (_) {
        return param;
      }
    }
    if (url.startsWith('https://images.weserv.nl/?url=')) {
      final param = url.replaceFirst('https://images.weserv.nl/?url=', '');
      try {
        final decoded = Uri.decodeComponent(param);
        if (decoded.startsWith('http')) return decoded;
      } catch (_) {}
    }
    if (url.startsWith('/')) {
      return 'https://examgo.id$url';
    }
    if (url.contains('googleusercontent.com')) return url;

    // Bare File ID (misal: 1mM7PTjpZKQnHCQX14BdQiOcoqVRdMlZJ)
    if (!url.startsWith('http') && !url.contains('/')) {
      return 'https://lh3.googleusercontent.com/d/$url';
    }

    // 1. /file/d/{id}
    final fileMatch = RegExp(r'/file/d/([^/?&]+)').firstMatch(url);
    if (fileMatch != null) {
      return 'https://lh3.googleusercontent.com/d/${fileMatch.group(1)}';
    }

    // 2. /d/{id}
    final dMatch = RegExp(r'/d/([^/?&]+)').firstMatch(url);
    if (dMatch != null) {
      return 'https://lh3.googleusercontent.com/d/${dMatch.group(1)}';
    }

    // 3. ?id={id} atau &id={id} (termasuk uc?export=view&id=...)
    final idMatch = RegExp(r'[?&]id=([^&]+)').firstMatch(url);
    if (idMatch != null) {
      return 'https://lh3.googleusercontent.com/d/${idMatch.group(1)}';
    }

    // 4. open?id={id}
    final openMatch = RegExp(r'open\?id=([^&]+)').firstMatch(url);
    if (openMatch != null) {
      return 'https://lh3.googleusercontent.com/d/${openMatch.group(1)}';
    }

    return url;
  }

  /// Cache in-memory untuk decoded Base64 bytes agar tidak re-decode setiap detik saat timer ujian tick (mencegah kedip/flicker)
  static final Map<String, Uint8List> _base64BytesCache = {};

  /// Membangun widget gambar soal yang andal, anti-flicker (bebas kedip), dan kompatibel:
  /// - Mendukung Data URI Base64 (data:image/...) dengan in-memory cache & gapless playback
  /// - Mendukung Google Drive, Google Forms, dan CDN eksternal via CachedNetworkImage
  /// - Zero-flicker: tidak re-load saat timer ujian berdetik tiap detik
  static Widget buildQuestionImage(
    String rawUrl, {
    double? height,
    double? width,
    BoxFit fit = BoxFit.contain,
    BorderRadius? borderRadius,
  }) {
    final cleanUrl = rawUrl.trim();
    if (cleanUrl.isEmpty) return const SizedBox.shrink();

    Widget imgWidget;

    if (cleanUrl.startsWith('data:image/')) {
      try {
        Uint8List? bytes = _base64BytesCache[cleanUrl];
        if (bytes == null) {
          final commaIdx = cleanUrl.indexOf(',');
          final b64 = commaIdx != -1 ? cleanUrl.substring(commaIdx + 1) : cleanUrl;
          bytes = base64Decode(b64);
          if (_base64BytesCache.length > 100) {
            _base64BytesCache.remove(_base64BytesCache.keys.first);
          }
          _base64BytesCache[cleanUrl] = bytes;
        }

        imgWidget = Image.memory(
          bytes,
          key: ValueKey('b64_${cleanUrl.hashCode}'),
          gaplessPlayback: true,
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    } else {
      final processedUrl = convertDriveUrl(cleanUrl);
      imgWidget = CachedNetworkImage(
        key: ValueKey('cni_${processedUrl.hashCode}'),
        imageUrl: processedUrl,
        cacheKey: processedUrl,
        httpHeaders: networkImageHeaders,
        useOldImageOnUrlChange: true,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        height: height,
        width: width,
        fit: fit,
        placeholder: (context, url) => Container(
          height: height ?? 140,
          width: width ?? double.infinity,
          color: const Color(0xFFF1F5F9),
        ),
        errorWidget: (context, url, error) => Image.network(
          processedUrl,
          key: ValueKey('fallback_${processedUrl.hashCode}'),
          headers: networkImageHeaders,
          gaplessPlayback: true,
          height: height,
          width: width,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      );
    }

    if (borderRadius != null && borderRadius != BorderRadius.zero) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: imgWidget,
      );
    }
    return imgWidget;
  }
}

