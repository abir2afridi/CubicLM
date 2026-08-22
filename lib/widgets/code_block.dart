import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../core/colors.dart';

class CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  CodeBlockBuilder(this.context);

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final code = element.textContent;
    String? language;
    if (element.attributes.containsKey('class')) {
      language = element.attributes['class']?.replaceFirst('language-', '');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _CodeBlock(code: code, language: language),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const _CodeBlock({required this.code, this.language});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _shareCode() {
    Share.share(widget.code);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = widget.language ?? '';
    final lines = widget.code.split('\n');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                if (lang.isNotEmpty) ...[
                  Icon(Icons.code_rounded,
                      size: 14,
                      color: isDark
                          ? AppColors.textMuted
                          : const Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Text(lang.toUpperCase(),
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textMuted
                            : const Color(0xFF64748B),
                      )),
                ] else
                  Text('CODE',
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textMuted
                            : const Color(0xFF64748B),
                      )),
                const Spacer(),
                _actionButton(
                  icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                  label: _copied ? 'Copied' : 'Copy',
                  color: _copied ? AppColors.success : null,
                  onTap: _copyCode,
                  isDark: isDark,
                ),
                const SizedBox(width: 4),
                _actionButton(
                  icon: Icons.ios_share_rounded,
                  label: 'Export',
                  onTap: _shareCode,
                  isDark: isDark,
                ),
              ],
            ),
          ),
          // Code body
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: _highlightedCode(lines, lang, isDark),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon,
                size: 13,
                color: color ??
                    (isDark
                        ? AppColors.textMuted
                        : const Color(0xFF64748B))),
            const SizedBox(width: 3),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color ??
                      (isDark
                          ? AppColors.textMuted
                          : const Color(0xFF64748B)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _highlightedCode(List<String> lines, String lang, bool isDark) {
    final codeColor = isDark ? const Color(0xFFCDD6F4) : const Color(0xFF1E293B);
    final keywordColor = isDark ? const Color(0xFFCBA6F7) : const Color(0xFF7C3AED);
    final stringColor = isDark ? const Color(0xFFA6E3A1) : const Color(0xFF059669);
    final commentColor = isDark ? const Color(0xFF6C7086) : const Color(0xFF94A3B8);
    final numberColor = isDark ? const Color(0xFFFAB387) : const Color(0xFFEA580C);
    final funcColor = isDark ? const Color(0xFF89DCEB) : const Color(0xFF2563EB);
    final lineNumColor = isDark ? Colors.white24 : Colors.black26;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines.length, (i) {
        return Row(
          // The parent is a horizontally scrolling SingleChildScrollView, so
          // incoming width is unbounded. Shrink-wrap and never use a flex child
          // here: a flex under unbounded width leaves the RenderFlex unlaid out.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.right,
                style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: lineNumColor,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _highlightedLine(
                lines[i],
                lang,
                codeColor,
                keywordColor,
                stringColor,
                commentColor,
                numberColor,
                funcColor,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _highlightedLine(
    String line,
    String lang,
    Color codeColor,
    Color keywordColor,
    Color stringColor,
    Color commentColor,
    Color numberColor,
    Color funcColor,
  ) {
    final spans = _highlightLine(line, lang, keywordColor, stringColor, commentColor, numberColor, funcColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(children: spans),
        style: GoogleFonts.firaCode(
          fontSize: 13,
          color: codeColor,
          height: 1.6,
        ),
      ),
    );
  }

  List<TextSpan> _highlightLine(
    String line,
    String lang,
    Color keywordColor,
    Color stringColor,
    Color commentColor,
    Color numberColor,
    Color funcColor,
  ) {
    if (line.trimLeft().startsWith('//') ||
        line.trimLeft().startsWith('#') ||
        line.trimLeft().startsWith('/*') ||
        line.trimLeft().startsWith('*')) {
      return [TextSpan(text: line, style: TextStyle(color: commentColor))];
    }

    final spans = <TextSpan>[];
    final pattern = RegExp(
      r"""('[^']*'|"[^"]*"|`[^`]*`)"""
      r"""|(\b(?:import|export|class|extends|implements|void|int|double|String|bool|final|const|var|return|if|else|for|while|do|switch|case|break|continue|new|this|super|static|async|await|try|catch|throw|finally|yield|get|set|factory|abstract|enum|mixin|required|late|dynamic|Map|List|Set|Future|Stream|Function|true|false|null|none|True|False|None|def|lambda|from|as|in|is|not|and|or|with|pass|raise|except|elif|global|nonlocal|assert|del|print|self)\b)"""
      r"""|(\b\d+\.?\d*\b)"""
      r"""|(\w+(?=\s*\())""",
      multiLine: true,
    );

    int lastEnd = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: line.substring(lastEnd, match.start)));
      }

      if (match.group(1) != null) {
        spans.add(TextSpan(text: match.group(1), style: TextStyle(color: stringColor)));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(text: match.group(2), style: TextStyle(color: keywordColor, fontWeight: FontWeight.w600)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(3), style: TextStyle(color: numberColor)));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: match.group(4), style: TextStyle(color: funcColor)));
      }

      lastEnd = match.end;
    }

    if (lastEnd < line.length) {
      spans.add(TextSpan(text: line.substring(lastEnd)));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: line));
    }

    return spans;
  }
}
