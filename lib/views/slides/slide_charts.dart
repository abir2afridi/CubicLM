import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/design_tokens.dart';
import '../../utils/slide_deck.dart';
import '../../utils/slide_palette.dart';
import 'slide_painters.dart';

/// Chart renderers (bar/donut/line) + layout-aware body widgets.
/// Extracted from views/slide_deck_view.dart.
///
/// [pal] re-skins charts to the active deck theme. Null keeps the legacy
/// dark-terracotta look (existing callers/tests unaffected).
Widget chartContent(Slide s, [SlidePalette? pal]) {
  pal ??= SlidePalette.fromTheme(SlideThemePresets.byName('Modern Terracotta'));
  final data = s.chartData;
  if (data.isEmpty) {
    // Fallback to bullets if chartData missing
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.title.isEmpty ? 'Chart' : s.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: pal.title)),
        const SizedBox(height: 6),
        for (final p in s.points.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('▸ $p',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5, color: pal.body)),
          ),
      ],
    );
  }
  final chartType = (data['type'] ?? 'bar').toString();
  final items = <Map<String, String>>[];
  if (data['items'] is List) {
    for (final e in (data['items'] as List)) {
      if (e is Map) {
        items.add({
          'label': (e['label'] ?? '').toString(),
          'value': (e['value'] ?? '0').toString(),
        });
      }
    }
  }
  if (items.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: pal.title)),
      ],
    );
  }

  // Parse numeric values for bar/line charts
  final nums = items.map((e) {
    final raw = e['value']?.replaceAll(RegExp(r'[^0-9.\-]'), '') ?? '0';
    return double.tryParse(raw) ?? 0;
  }).toList();
  final maxVal = nums.isEmpty ? 1.0 : nums.reduce((a, b) => a > b ? a : b);

  if (chartType == 'donut') {
    return donutChart(s.title, items, nums, pal: pal);
  }
  if (chartType == 'line') {
    return lineChart(s.title, items, nums, maxVal, pal: pal);
  }
  // Default: bar chart
  return barChart(s.title, items, nums, maxVal, pal: pal);
}

Widget barChart(String title, List<Map<String, String>> items,
    List<double> nums, double maxVal,
    {required SlidePalette pal}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.isEmpty ? 'Chart' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 10),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < items.length && i < 6; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(items[i]['value'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: pal.accent)),
                      const SizedBox(height: 3),
                      Container(
                        height: maxVal > 0 ? (nums[i] / maxVal) * 120 : 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                pal.accent,
                                pal.accent.withValues(alpha: 0.5)
                              ]),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(items[i]['label'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 8.5, color: pal.muted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

Widget donutChart(
    String title, List<Map<String, String>> items, List<double> nums,
    {required SlidePalette pal}) {
  final total = nums.isEmpty ? 1.0 : nums.fold(0.0, (a, b) => a + b);
  final colors = [
    pal.accent,
    pal.secondary,
    const Color(0xFF60A5FA),
    const Color(0xFFFBBF24),
    const Color(0xFFF87171),
    const Color(0xFFA78BFA),
  ];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.isEmpty ? 'Chart' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 15, fontWeight: FontWeight.w800, color: pal.title)),
      const SizedBox(height: 8),
      Expanded(
        child: Row(
          children: [
            // Legend
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length && i < 6; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: colors[i % colors.length],
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${items[i]['label']}  ${items[i]['value']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 10, color: pal.body),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
            // Donut circle
            SizedBox(
              width: 90,
              height: 90,
              child: CustomPaint(
                painter: DonutPainter(nums, total, colors),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget lineChart(String title, List<Map<String, String>> items,
    List<double> nums, double maxVal,
    {required SlidePalette pal}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.isEmpty ? 'Chart' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 15, fontWeight: FontWeight.w800, color: pal.title)),
      const SizedBox(height: 10),
      Expanded(
        child: LayoutBuilder(builder: (_, cons) {
          final w = cons.maxWidth;
          final h = cons.maxHeight;
          final pts = <Offset>[];
          for (var i = 0; i < nums.length && i < 8; i++) {
            final x = nums.length > 1 ? (i / (nums.length - 1)) * w : w / 2;
            final y = maxVal > 0 ? h - (nums[i] / maxVal) * (h - 20) : h / 2;
            pts.add(Offset(x, y));
          }
          return Stack(children: [
            CustomPaint(
              size: Size(w, h),
              painter: LineChartPainter(pts, items, nums, pal.accent),
            ),
          ]);
        }),
      ),
    ],
  );
}

/// Returns layout-aware body widgets for Docs and PDF canvases.
List<Widget> layoutBodyWidgets(Slide s, bool showImage,
    {double fontSize = 13,
    Color bulletColor = Dt.accent,
    Color textColor = const Color(0xFF2A2A2A)}) {
  final List<Widget> widgets = [];
  final hasImage = s.imageBytes != null && s.imageBytes!.isNotEmpty;

  if (s.layout == 'quote') {
    widgets.add(Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '"${s.points.join(" ")}"',
        style: GoogleFonts.plusJakartaSans(
            fontSize: fontSize + 1,
            fontStyle: FontStyle.italic,
            height: 1.6,
            color: textColor),
      ),
    ));
    if (s.quoteAuthor.isNotEmpty) {
      widgets.add(Text(
        '— ${s.quoteAuthor}',
        style: GoogleFonts.plusJakartaSans(
            fontSize: fontSize - 1,
            fontWeight: FontWeight.w700,
            color: bulletColor),
      ));
    }
  } else if (s.layout == 'comparison' && s.columns.length >= 2) {
    final c1 = s.columns[0];
    final c2 = s.columns[1];
    final maxLen = c1.length > c2.length ? c1.length : c2.length;
    for (var j = 0; j < maxLen; j++) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(
                child: Text(
              j < c1.length ? '• ${c1[j]}' : '',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: fontSize - 1, height: 1.4, color: textColor),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
              j < c2.length ? '• ${c2[j]}' : '',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: fontSize - 1, height: 1.4, color: textColor),
            )),
          ],
        ),
      ));
    }
  } else if (s.layout == 'stats' && s.stats.isNotEmpty) {
    for (final st in s.stats) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text('${st['value'] ?? ''}  ',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: fontSize + 1,
                    fontWeight: FontWeight.w900,
                    color: bulletColor)),
            Expanded(
                child: Text(st['label'] ?? '',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: fontSize - 1, color: textColor))),
          ],
        ),
      ));
    }
  } else if (s.layout == 'timeline' && s.points.isNotEmpty) {
    for (var i = 0; i < s.points.length; i++) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: fontSize + 2,
              height: fontSize + 2,
              margin: const EdgeInsets.only(top: 2, right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bulletColor,
              ),
              alignment: Alignment.center,
              child: Text('${i + 1}',
                  style: TextStyle(
                      fontSize: fontSize - 3,
                      color: Colors.white,
                      fontWeight: FontWeight.w800)),
            ),
            Expanded(
                child: Text(s.points[i],
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: fontSize - 1,
                        height: 1.4,
                        color: textColor))),
          ],
        ),
      ));
    }
  } else if (s.layout == 'chart' && s.chartData.isNotEmpty) {
    final data = s.chartData;
    final type = data['type'] ?? 'bar';
    final items = data['items'] is List ? data['items'] as List : [];
    if (items.isNotEmpty) {
      widgets.add(Text(
        'Chart (${type.toString().toUpperCase()})',
        style: GoogleFonts.plusJakartaSans(
            fontSize: fontSize - 1,
            fontWeight: FontWeight.w800,
            color: bulletColor),
      ));
      widgets.add(const SizedBox(height: 6));
      for (final e in items) {
        final label = e['label']?.toString() ?? '';
        final value = e['value']?.toString() ?? '';
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text('• $label: $value',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: fontSize - 1, color: textColor)),
        ));
      }
    }
  } else if (s.layout == 'summary') {
    for (final p in s.points) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('✓  ',
                style: TextStyle(
                    color: Color(0xFF2ECC71),
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
            Expanded(
                child: Text(p,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: fontSize - 1,
                        height: 1.4,
                        color: textColor))),
          ],
        ),
      ));
    }
  } else {
    // Default: title, bullets, image
    for (final p in s.points) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('•  ',
              style: TextStyle(
                  color: bulletColor,
                  fontWeight: FontWeight.w800,
                  fontSize: fontSize)),
          Expanded(
            child: Text(p,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: fontSize, height: 1.5, color: textColor)),
          ),
        ]),
      ));
    }
  }

  if (showImage && hasImage) {
    widgets.add(const SizedBox(height: 10));
    widgets.add(ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        Uint8List.fromList(s.imageBytes!),
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    ));
  }

  return widgets;
}
