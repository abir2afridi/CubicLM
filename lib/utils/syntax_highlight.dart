/// Lightweight regex-based syntax highlighter for multiple languages.
/// Returns a list of [SyntaxToken]s for rendering with RichText.
library;

import 'package:flutter/material.dart';

class SyntaxToken {
  final String text;
  final Color color;
  const SyntaxToken(this.text, this.color);
}

/// Color palette (Catppuccin-inspired, works on both dark and light BGs).
class SyntaxColors {
  static const keyword = Color(0xFFCBA6F7); // purple
  static const string = Color(0xFFA6E3A1); // green
  static const comment = Color(0xFF6C7086); // gray
  static const tag = Color(0xFFF38BA8); // red/pink
  static const attr = Color(0xFFFAB387); // orange
  static const number = Color(0xFFF9E2AF); // yellow
  static const punct = Color(0xFFBAC2DE); // gray text
  static const plain = Color(0xFFCDD6F4); // default text
}

/// Detect file type from path.
String _detectLang(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.html') || p.endsWith('.htm')) return 'html';
  if (p.endsWith('.css')) return 'css';
  if (p.endsWith('.js') || p.endsWith('.jsx') || p.endsWith('.mjs') || p.endsWith('.ts') || p.endsWith('.tsx')) {
    return 'js';
  }
  if (p.endsWith('.dart')) return 'dart';
  if (p.endsWith('.py')) return 'python';
  if (p.endsWith('.json')) return 'json';
  if (p.endsWith('.xml')) return 'xml';
  if (p.endsWith('.md') || p.endsWith('.markdown')) return 'md';
  return 'text';
}

/// Tokenize source code into colored spans.
List<SyntaxToken> highlight(String source, String path) {
  final lang = _detectLang(path);
  switch (lang) {
    case 'html':
    case 'xml':
      return _highlightHtml(source);
    case 'css':
      return _highlightCss(source);
    case 'js':
    case 'dart':
    case 'python':
      return _highlightCode(source, lang);
    case 'json':
      return _highlightJson(source);
    default:
      return [SyntaxToken(source, SyntaxColors.plain)];
  }
}

List<SyntaxToken> _highlightHtml(String src) {
  final tokens = <SyntaxToken>[];
  final re = RegExp(
    r'(<!--[\s\S]*?-->)' // 1: comment
    r'|(<\/?[a-zA-Z][\w-]*)' // 2: tag
    r'|(\s+[a-zA-Z][\w-]*=)' // 3: attr name
    r'|("([^"\\]|\\.)*")' // 4: double-quoted string
    r"|('([^'\\]|\\.)*')" // 5: single-quoted string
    r'|(>[^<]+)' // 6: text content
    r'|(\s+)', // 7: whitespace
    caseSensitive: false,
  );
  for (final m in re.allMatches(src)) {
    if (m.group(1) != null) {
      tokens.add(SyntaxToken(m.group(1)!, SyntaxColors.comment));
    } else if (m.group(2) != null) {
      tokens.add(SyntaxToken(m.group(2)!, SyntaxColors.tag));
    } else if (m.group(3) != null) {
      tokens.add(SyntaxToken(m.group(3)!, SyntaxColors.attr));
    } else if (m.group(4) != null) {
      tokens.add(SyntaxToken(m.group(4)!, SyntaxColors.string));
    } else if (m.group(5) != null) {
      tokens.add(SyntaxToken(m.group(5)!, SyntaxColors.string));
    } else if (m.group(6) != null) {
      tokens.add(SyntaxToken(m.group(6)!, SyntaxColors.plain));
    } else if (m.group(7) != null) {
      tokens.add(SyntaxToken(m.group(7)!, SyntaxColors.plain));
    }
  }
  if (tokens.isEmpty) {
    tokens.add(SyntaxToken(src, SyntaxColors.plain));
  }
  return tokens;
}

List<SyntaxToken> _highlightCss(String src) {
  final tokens = <SyntaxToken>[];
  final re = RegExp(
    r'(\/\*[\s\S]*?\*\/)' // 1: comment
    r'|("(\\.|[^"\\])*")' // 2: double string
    r"|('(\\.|[^'\\])*')" // 3: single string
    r'|(\#[0-9a-fA-F]{3,8})' // 4: hex color
    r'|(\.[a-zA-Z][\w-]*)' // 5: class selector
    r'|(\#[a-zA-Z][\w-]*)' // 6: id selector
    r'|(@[a-zA-Z]+)' // 7: at-rule
    r'|(:{1,2}[a-zA-Z][\w-]*)' // 8: pseudo
    r'|\b(\d+\.?\d*(px|em|rem|%|vh|vw|s|ms)?)\b' // 9: number
    r'|([{}();:,])' // 10: punct
    r'|(\s+)', // 11: ws
    caseSensitive: false,
  );
  for (final m in re.allMatches(src)) {
    if (m.group(1) != null) {
      tokens.add(SyntaxToken(m.group(1)!, SyntaxColors.comment));
    } else if (m.group(2) != null) {
      tokens.add(SyntaxToken(m.group(2)!, SyntaxColors.string));
    } else if (m.group(3) != null) {
      tokens.add(SyntaxToken(m.group(3)!, SyntaxColors.string));
    } else if (m.group(4) != null) {
      tokens.add(SyntaxToken(m.group(4)!, SyntaxColors.number));
    } else if (m.group(5) != null) {
      tokens.add(SyntaxToken(m.group(5)!, SyntaxColors.attr));
    } else if (m.group(6) != null) {
      tokens.add(SyntaxToken(m.group(6)!, SyntaxColors.attr));
    } else if (m.group(7) != null) {
      tokens.add(SyntaxToken(m.group(7)!, SyntaxColors.keyword));
    } else if (m.group(8) != null) {
      tokens.add(SyntaxToken(m.group(8)!, SyntaxColors.keyword));
    } else if (m.group(9) != null) {
      tokens.add(SyntaxToken(m.group(9)!, SyntaxColors.number));
    } else if (m.group(10) != null) {
      tokens.add(SyntaxToken(m.group(10)!, SyntaxColors.punct));
    } else if (m.group(11) != null) {
      tokens.add(SyntaxToken(m.group(11)!, SyntaxColors.plain));
    }
  }
  if (tokens.isEmpty) {
    tokens.add(SyntaxToken(src, SyntaxColors.plain));
  }
  return tokens;
}

List<SyntaxToken> _highlightCode(String src, String lang) {
  final tokens = <SyntaxToken>[];
  final String kwPattern;
  if (lang == 'js') {
    kwPattern = r'\b(const|let|var|function|return|if|else|for|while|do|switch|case|'
        r'break|continue|new|this|class|extends|import|export|from|default|'
        r'try|catch|finally|throw|async|await|yield|typeof|instanceof|in|of|'
        r'true|false|null|undefined|void|delete|super|static|get|set)\b';
  } else if (lang == 'dart') {
    kwPattern = r'\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|'
        r'covariant|default|deferred|do|dynamic|else|enum|export|extends|extension|'
        r'external|factory|false|final|finally|for|Function|get|hide|if|implements|'
        r'import|in|interface|is|late|library|mixin|new|null|on|operator|part|'
        r'required|rethrow|return|set|show|static|super|switch|sync|this|throw|'
        r'true|try|typedef|var|void|while|with|yield)\b';
  } else if (lang == 'python') {
    kwPattern = r'\b(False|None|True|and|as|assert|async|await|break|class|continue|'
        r'def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|'
        r'nonlocal|not|or|pass|raise|return|try|while|with|yield)\b';
  } else {
    kwPattern = r'\b(if|else|return)\b';
  }

  final kw = RegExp(kwPattern);
  final re = RegExp(
    r'(\/\/[^\n]*)' // 1: line comment
    r'|(\/\*[\s\S]*?\*\/)' // 2: block comment
    r'|(\#[^\n]*)' // 3: python line comment
    r'|("(\\.|[^"\\])*")' // 4: double string
    r"|('(\\.|[^'\\])*')" // 5: single string
    r'|(`(\\.|[^`])*`)' // 6: template string
    r'|(\b\d+\.?\d*([eE][+-]?\d+)?\b)' // 7: number
    r'|([a-zA-Z_$][\w$]*\s*:)' // 8: object key
    r'|([{}();:,.\[\]=+\-<>&|!?])' // 9: punct
    r'|(\s+)', // 10: ws
    caseSensitive: false,
  );
  for (final m in re.allMatches(src)) {
    if (m.group(1) != null || m.group(2) != null || m.group(3) != null) {
      tokens.add(SyntaxToken(m.group(0)!, SyntaxColors.comment));
    } else if (m.group(4) != null || m.group(5) != null || m.group(6) != null) {
      tokens.add(SyntaxToken(m.group(0)!, SyntaxColors.string));
    } else if (m.group(7) != null) {
      tokens.add(SyntaxToken(m.group(0)!, SyntaxColors.number));
    } else {
      final text = m.group(0)!;
      if (kw.hasMatch(text)) {
        tokens.add(SyntaxToken(text, SyntaxColors.keyword));
      } else if (m.group(8) != null) {
        tokens.add(SyntaxToken(text, SyntaxColors.attr));
      } else if (m.group(9) != null) {
        tokens.add(SyntaxToken(text, SyntaxColors.punct));
      } else {
        tokens.add(SyntaxToken(text, SyntaxColors.plain));
      }
    }
  }
  if (tokens.isEmpty) {
    tokens.add(SyntaxToken(src, SyntaxColors.plain));
  }
  return tokens;
}

List<SyntaxToken> _highlightJson(String src) {
  final tokens = <SyntaxToken>[];
  final re = RegExp(
    r'("(\\.|[^"\\])*")\s*:' // 1: key
    r'|("(\\.|[^"\\])*")' // 2: string value
    r'|\b(true|false|null)\b' // 3: literal
    r'|(-?\d+\.?\d*([eE][+-]?\d+)?)' // 4: number
    r'|([{}[\]:,])' // 5: punct
    r'|(\s+)', // 6: ws
  );
  for (final m in re.allMatches(src)) {
    if (m.group(1) != null) {
      tokens.add(SyntaxToken(m.group(1)!, SyntaxColors.attr));
    } else if (m.group(2) != null) {
      tokens.add(SyntaxToken(m.group(2)!, SyntaxColors.string));
    } else if (m.group(3) != null) {
      tokens.add(SyntaxToken(m.group(3)!, SyntaxColors.keyword));
    } else if (m.group(4) != null) {
      tokens.add(SyntaxToken(m.group(4)!, SyntaxColors.number));
    } else if (m.group(5) != null) {
      tokens.add(SyntaxToken(m.group(5)!, SyntaxColors.punct));
    } else if (m.group(6) != null) {
      tokens.add(SyntaxToken(m.group(6)!, SyntaxColors.plain));
    }
  }
  if (tokens.isEmpty) {
    tokens.add(SyntaxToken(src, SyntaxColors.plain));
  }
  return tokens;
}

/// Build a TextSpan tree from tokens for use with RichText.
TextSpan buildHighlightedSpan(List<SyntaxToken> tokens, {double fontSize = 12}) {
  return TextSpan(
    children: tokens
        .map((t) => TextSpan(
              text: t.text,
              style: TextStyle(
                color: t.color,
                fontFamily: 'FiraCode',
                fontSize: fontSize,
                height: 1.5,
              ),
            ))
        .toList(),
  );
}

/// A specialized controller that applies syntax highlighting as you type.
class SyntaxHighlightingController extends TextEditingController {
  final String path;
  SyntaxHighlightingController({super.text, required this.path});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final tokens = highlight(text, path);
    return buildHighlightedSpan(tokens, fontSize: style?.fontSize ?? 12);
  }
}
