import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart' as fwfh;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter_math_fork/flutter_math.dart';

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

      meta.register(BuildOp(
        onVisitChild: (tree, subTree) => false,
        onParsed: (tree) {
          final widget = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              text,
              mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
              textStyle: TextStyle(fontSize: fontSize),
              onErrorFallback: (err) => Text(
                text,
                style: TextStyle(color: Colors.red.shade700, fontSize: fontSize),
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
}

/// Helper utilitas untuk normalisasi teks soal & format LaTeX ke HTML
class MathHtmlFormatter {
  MathHtmlFormatter._();

  /// Mengubah rumus LaTeX ($...$, $$...$$, \(...\), \[...\]) menjadi tag HTML
  /// yang dapat dibaca oleh MathWidgetFactory.
  static String format(String text) {
    if (text.isEmpty) return '';
    String html = text;

    // Normalisasi line break
    html = html.replaceAll('\r\n', '\n');

    // Bold (**text**) & Italic (*text*)
    html = html.replaceAllMapped(
      RegExp(r'\*\*(?!\s)(.*?)(?<!\s)\*\*', dotAll: true),
      (match) => '<b>${match.group(1)}</b>',
    );
    html = html.replaceAllMapped(
      RegExp(r'(?<![A-Za-z0-9_])\*(?!\s)(.*?)(?<!\s)\*(?![A-Za-z0-9_])', dotAll: true),
      (match) => '<i>${match.group(1)}</i>',
    );

    // Normalisasi backslash berlebih
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

    // $...$ → inline math (single dollar, diproses setelah $$)
    html = html.replaceAllMapped(RegExp(r'\$([^\$\n]+?)\$'), (match) {
      final mathStr = Uri.encodeComponent(match.group(1)!.trim());
      return '<span class="math-tex inline" data-math="$mathStr"></span>';
    });

    // Replace newline dengan <br/> jika belum dibungkus tag HTML blok
    if (!html.contains('<p>') && !html.contains('<div>')) {
      html = html.replaceAll('\n', '<br/>');
    }

    return html;
  }

  /// Menormalisasi link Google Drive agar langsung dapat di-load sebagai image
  static String convertDriveUrl(String url) {
    if (url.isEmpty) return url;
    if (!url.startsWith('http') && !url.contains('/')) {
      return 'https://drive.google.com/uc?export=view&id=$url';
    }
    if (url.contains('uc?export=view') ||
        (url.contains('uc?id=') && url.contains('export=view'))) {
      return url;
    }
    if (url.contains('googleusercontent.com')) return url;
    final fileMatch = RegExp(r'/file/d/([^/?&]+)').firstMatch(url);
    if (fileMatch != null) {
      final id = fileMatch.group(1)!;
      return 'https://drive.google.com/uc?export=view&id=$id';
    }
    final idMatch = RegExp(r'[?&]id=([^&]+)').firstMatch(url);
    if (idMatch != null) {
      final id = idMatch.group(1)!;
      return 'https://drive.google.com/uc?export=view&id=$id';
    }
    final openMatch = RegExp(r'open\?id=([^&]+)').firstMatch(url);
    if (openMatch != null) {
      final id = openMatch.group(1)!;
      return 'https://drive.google.com/uc?export=view&id=$id';
    }
    return url;
  }
}

