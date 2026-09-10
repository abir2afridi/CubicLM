/// CubicDataSheet formula engine — faithful port of the DataSheet web
/// `utils/formulas.ts`. Pure Dart, no I/O: cell refs (A1, ranges A1:B3,
/// cross-sheet Sheet!A1), SUM/AVERAGE/COUNT/MAX/MIN/CONCAT/UPPER/LOWER/
/// LEN, inline arithmetic and the same error sentinels (#NAME?, #REF!,
/// #CIRCULAR!, #DIV/0!, #ERROR!). Source cell content is never mutated.
library;

import 'models.dart';

int colLabelToIdx(String label) {
  var idx = 0;
  final upper = label.trim().toUpperCase();
  for (var i = 0; i < upper.length; i++) {
    idx = idx * 26 + (upper.codeUnitAt(i) - 64);
  }
  return idx - 1;
}

String idxToColLabel(int idx) {
  var label = '';
  var temp = idx;
  while (temp >= 0) {
    label = String.fromCharCode((temp % 26) + 65) + label;
    temp = temp ~/ 26 - 1;
  }
  return label;
}

class ParsedAddress {
  final String? sheetName;
  final String colLabel;
  final int rowNumber;
  final int colIdx;
  final int rowIdx;

  const ParsedAddress({
    required this.sheetName,
    required this.colLabel,
    required this.rowNumber,
    required this.colIdx,
    required this.rowIdx,
  });
}

ParsedAddress? parseCellAddress(String address) {
  final clean = address.trim().toUpperCase();
  String? sheetName;
  var remaining = clean;
  if (clean.contains('!')) {
    final parts = clean.split('!');
    sheetName = parts[0].replaceAll(RegExp('[\'"]'), '');
    remaining = parts.sublist(1).join('!');
  }
  final match = RegExp(r'^([A-Z]+)([0-9]+)$').firstMatch(remaining);
  if (match == null) return null;
  final colLabel = match.group(1)!;
  final rowNumber = int.parse(match.group(2)!);
  return ParsedAddress(
    sheetName: sheetName,
    colLabel: colLabel,
    rowNumber: rowNumber,
    colIdx: colLabelToIdx(colLabel),
    rowIdx: rowNumber - 1,
  );
}

List<String> expandRange(String rangeStr) {
  final parts = rangeStr.split(':');
  if (parts.length != 2) return [rangeStr];
  final start = parseCellAddress(parts[0]);
  final end = parseCellAddress(parts[1]);
  if (start == null || end == null) return [];
  final minRow = start.rowIdx < end.rowIdx ? start.rowIdx : end.rowIdx;
  final maxRow = start.rowIdx > end.rowIdx ? start.rowIdx : end.rowIdx;
  final minCol = start.colIdx < end.colIdx ? start.colIdx : end.colIdx;
  final maxCol = start.colIdx > end.colIdx ? start.colIdx : end.colIdx;
  final prefix = start.sheetName != null ? '${start.sheetName}!' : '';
  final out = <String>[];
  for (var r = minRow; r <= maxRow; r++) {
    for (var c = minCol; c <= maxCol; c++) {
      out.add('$prefix${idxToColLabel(c)}${r + 1}');
    }
  }
  return out;
}

/// JS parseFloat semantics (leading numeric prefix, e.g. "12abc" → 12).
/// Dart's double.tryParse is strict, so match the web engine here.
double? _jsParseFloat(String s) {
  final m = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?')
      .firstMatch(s.trim());
  if (m == null) return null;
  return double.tryParse(m.group(0)!);
}

SheetData? _targetSheet(
    List<SheetData> sheets, String currentSheetId, String? sheetName) {
  SheetData? target;
  for (final s in sheets) {
    if (s.id == currentSheetId) {
      target = s;
      break;
    }
  }
  if (sheetName != null) {
    for (final s in sheets) {
      if (s.name.toUpperCase() == sheetName) {
        target = s;
        break;
      }
    }
  }
  return target;
}

String getCellValue(
  String address,
  List<SheetData> sheets,
  String currentSheetId,
  Set<String> visited,
) {
  final parsed = parseCellAddress(address);
  if (parsed == null) return '0';
  final target = _targetSheet(sheets, currentSheetId, parsed.sheetName);
  if (target == null) return '#REF!';
  final cellKey = '${parsed.colLabel}${parsed.rowNumber}';
  final cell = target.cells[cellKey];
  if (cell == null) return '';
  if (cell.formula != null && cell.formula!.startsWith('=')) {
    final coord = '${target.id}!$cellKey';
    if (visited.contains(coord)) return '#CIRCULAR!';
    final next = Set<String>.of(visited)..add(coord);
    return evaluateFormula(cell.formula!, sheets, target.id, next);
  }
  return cell.value;
}

const _fnNames = {
  'SUM',
  'AVERAGE',
  'COUNT',
  'MAX',
  'MIN',
  'CONCAT',
  'UPPER',
  'LOWER',
  'LEN'
};

String evaluateFormula(
  String formula,
  List<SheetData> sheets,
  String currentSheetId, [
  Set<String>? visited,
]) {
  final seen = visited ?? <String>{};
  if (!formula.startsWith('=')) return formula;
  final rawExpression = formula.substring(1).trim();
  final upperExpr = rawExpression.toUpperCase();
  try {
    final funcMatch =
        RegExp(r'^([A-Z0-9_]+)\((.*)\)$', dotAll: true).firstMatch(upperExpr);
    if (funcMatch != null) {
      final funcName = funcMatch.group(1)!;
      final argsRaw = funcMatch.group(2)!;
      final args = <String>[];
      final current = StringBuffer();
      var parenDepth = 0;
      var inQuote = false;
      for (var i = 0; i < argsRaw.length; i++) {
        final ch = argsRaw[i];
        if (ch == '"') {
          inQuote = !inQuote;
        } else if (ch == '(' && !inQuote) {
          parenDepth++;
        } else if (ch == ')' && !inQuote) {
          parenDepth--;
        }
        if (ch == ',' && parenDepth == 0 && !inQuote) {
          args.add(current.toString().trim());
          current.clear();
        } else {
          current.write(ch);
        }
      }
      if (current.toString().trim().isNotEmpty) {
        args.add(current.toString().trim());
      }

      final resolvedValues = <double>[];
      final stringValues = <String>[];
      for (final arg in args) {
        if (arg.contains(':')) {
          for (final c in expandRange(arg)) {
            final val = getCellValue(c, sheets, currentSheetId, seen);
            stringValues.add(val);
            final num = _jsParseFloat(val);
            if (num != null) resolvedValues.add(num);
          }
        } else {
          final isCell = parseCellAddress(arg);
          if (isCell != null) {
            final val = getCellValue(arg, sheets, currentSheetId, seen);
            stringValues.add(val);
            final num = _jsParseFloat(val);
            if (num != null) resolvedValues.add(num);
          } else if ((arg.startsWith('"') && arg.endsWith('"') && arg.length >= 2) ||
              (arg.startsWith("'") && arg.endsWith("'") && arg.length >= 2)) {
            stringValues.add(arg.substring(1, arg.length - 1));
          } else {
            final num = _jsParseFloat(arg);
            if (num != null) {
              resolvedValues.add(num);
              stringValues.add(arg);
            } else {
              stringValues.add(arg);
            }
          }
        }
      }

      double sum() => resolvedValues.fold(0.0, (a, b) => a + b);
      switch (funcName) {
        case 'SUM':
          return _numToString(sum());
        case 'AVERAGE':
          if (resolvedValues.isEmpty) return '0';
          final avg = sum() / resolvedValues.length;
          var s = avg.toStringAsFixed(2);
          if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
          return s;
        case 'COUNT':
          return resolvedValues.length.toString();
        case 'MAX':
          if (resolvedValues.isEmpty) return '0';
          return _numToString(
              resolvedValues.reduce((a, b) => a > b ? a : b));
        case 'MIN':
          if (resolvedValues.isEmpty) return '0';
          return _numToString(
              resolvedValues.reduce((a, b) => a < b ? a : b));
        case 'CONCAT':
          return stringValues.join('');
        case 'UPPER':
          return stringValues.join(' ').toUpperCase();
        case 'LOWER':
          return stringValues.join(' ').toLowerCase();
        case 'LEN':
          return (stringValues.isEmpty ? '' : stringValues[0]).length
              .toString();
        default:
          return '#NAME? ($funcName)';
      }
    }

    var evalStr = rawExpression;
    String? replacementError;
    evalStr = evalStr.replaceAllMapped(
      RegExp(r'\b([a-zA-Z!_]+[0-9]+)\b'),
      (m) {
        final match = m.group(0)!;
        if (_fnNames.contains(match.toUpperCase())) return match;
        final val = getCellValue(match, sheets, currentSheetId, seen);
        if (val == '#CIRCULAR!') {
          replacementError = '#CIRCULAR!';
          return '0';
        }
        if (val == '#REF!') {
          replacementError = '#REF!';
          return '0';
        }
        final num = _jsParseFloat(val);
        return num != null ? _numToString(num) : '"$val"';
      },
    );
    if (replacementError != null) return replacementError!;

    if (!RegExp(r'^[0-9+\-*/().\s]+$').hasMatch(evalStr)) {
      return '#ERROR!';
    }
    final result = _evalArithmetic(evalStr);
    if (result == null) return '#ERROR!';
    if (result.isInfinite) return '#DIV/0!';
    if (result.isNaN) return '#ERROR!';
    return _numToString(result);
  } catch (_) {
    return '#ERROR!';
  }
}

String _numToString(double v) {
  if (v == v.truncateToDouble()) return v.truncate().toString();
  return v.toString();
}

/// Minimal arithmetic evaluator (+ - * / parens, unary minus, decimals).
/// Returns null when the expression is malformed.
double? _evalArithmetic(String expr) {
  final tokens = <String>[];
  var i = 0;
  while (i < expr.length) {
    final ch = expr[i];
    if (ch == ' ' || ch == '\t' || ch == '\n') {
      i++;
      continue;
    }
    if (ch == '(' || ch == ')' || ch == '+' || ch == '*' || ch == '/') {
      tokens.add(ch);
      i++;
      continue;
    }
    if (ch == '-') {
      final prev = tokens.isEmpty ? '' : tokens.last;
      if (tokens.isEmpty || prev == '(' || prev == '+' || prev == '-' ||
          prev == '*' || prev == '/') {
        var j = i + 1;
        while (j < expr.length &&
            ((expr.codeUnitAt(j) >= 48 && expr.codeUnitAt(j) <= 57) ||
                expr[j] == '.')) {
          j++;
        }
        if (j == i + 1) return null;
        tokens.add(expr.substring(i, j));
        i = j;
        continue;
      }
      tokens.add(ch);
      i++;
      continue;
    }
    if ((ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) || ch == '.') {
      var j = i;
      while (j < expr.length &&
          ((expr.codeUnitAt(j) >= 48 && expr.codeUnitAt(j) <= 57) ||
              expr[j] == '.')) {
        j++;
      }
      tokens.add(expr.substring(i, j));
      i = j;
      continue;
    }
    return null;
  }
  final pos = _Parser(tokens);
  final result = pos.parseExpr();
  if (result == null || pos.index != tokens.length) return null;
  return result;
}

class _Parser {
  final List<String> tokens;
  int index = 0;
  _Parser(this.tokens);

  double? parseExpr() {
    var left = parseTerm();
    if (left == null) return null;
    while (index < tokens.length &&
        (tokens[index] == '+' || tokens[index] == '-')) {
      final op = tokens[index++];
      final right = parseTerm();
      if (right == null) return null;
      left = op == '+' ? left! + right : left! - right;
    }
    return left;
  }

  double? parseTerm() {
    var left = parseFactor();
    if (left == null) return null;
    while (index < tokens.length &&
        (tokens[index] == '*' || tokens[index] == '/')) {
      final op = tokens[index++];
      final right = parseFactor();
      if (right == null) return null;
      left = op == '*' ? left! * right : left! / right;
    }
    return left;
  }

  double? parseFactor() {
    if (index >= tokens.length) return null;
    final t = tokens[index++];
    if (t == '(') {
      final v = parseExpr();
      if (v == null || index >= tokens.length || tokens[index++] != ')') {
        return null;
      }
      return v;
    }
    return double.tryParse(t);
  }
}

/// Early static check for malformed formulas (unbalanced parens,
//  literal division by zero). Null = looks fine.
String? detectFormulaError(String formula) {
  if (!formula.startsWith('=')) return null;
  final upper = formula.toUpperCase();
  var parenCount = 0;
  for (var i = 0; i < upper.length; i++) {
    if (upper[i] == '(') parenCount++;
    if (upper[i] == ')') parenCount--;
    if (parenCount < 0) return 'Mismatched Parentheses';
  }
  if (parenCount != 0) return 'Unclosed Parentheses';
  if (upper.contains('/0') && !upper.contains('/0.')) {
    return 'Potential division by zero';
  }
  return null;
}
