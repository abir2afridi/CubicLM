import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'slide_deck.dart';

/// Generates a valid .pptx (OpenXML) file from a list of slides.
Future<List<int>> deckToPptx(String topic, List<Slide> slides, {SlideDeckTheme? theme}) async {
  final archive = Archive();

  final primaryHex = (theme?.primaryColor ?? 'D97757').replaceAll('#', '');
  final bgHex = (theme?.backgroundColor ?? '23232F').replaceAll('#', '');
  final textHex = (theme?.textColor ?? 'F2F0EA').replaceAll('#', '');

  // 1. [Content_Types].xml
  final contentTypesXml = _buildContentTypes(slides);
  archive.addFile(ArchiveFile('[Content_Types].xml', contentTypesXml.length, contentTypesXml));

  // 2. _rels/.rels
  final packageRelsXml = _buildPackageRels();
  archive.addFile(ArchiveFile('_rels/.rels', packageRelsXml.length, packageRelsXml));

  // 3. ppt/presentation.xml
  final presentationXml = _buildPresentation(slides);
  archive.addFile(ArchiveFile('ppt/presentation.xml', presentationXml.length, presentationXml));

  // 4. ppt/_rels/presentation.xml.rels
  final presentationRelsXml = _buildPresentationRels(slides);
  archive.addFile(ArchiveFile('ppt/_rels/presentation.xml.rels', presentationRelsXml.length, presentationRelsXml));

  // 5. ppt/theme/theme1.xml
  final themeXml = _buildTheme(primaryHex, bgHex, textHex);
  archive.addFile(ArchiveFile('ppt/theme/theme1.xml', themeXml.length, themeXml));

  // 6. ppt/slideMasters/slideMaster1.xml and rels
  final slideMasterXml = _buildSlideMaster(bgHex);
  archive.addFile(ArchiveFile('ppt/slideMasters/slideMaster1.xml', slideMasterXml.length, slideMasterXml));
  final slideMasterRelsXml = _buildSlideMasterRels();
  archive.addFile(ArchiveFile('ppt/slideMasters/_rels/slideMaster1.xml.rels', slideMasterRelsXml.length, slideMasterRelsXml));

  // 7. ppt/slideLayouts/slideLayout1.xml and rels
  final slideLayoutXml = _buildSlideLayout();
  archive.addFile(ArchiveFile('ppt/slideLayouts/slideLayout1.xml', slideLayoutXml.length, slideLayoutXml));
  final slideLayoutRelsXml = _buildSlideLayoutRels();
  archive.addFile(ArchiveFile('ppt/slideLayouts/_rels/slideLayout1.xml.rels', slideLayoutRelsXml.length, slideLayoutRelsXml));

  // 8. Slides, Notes, and Media
  int imageIdCounter = 1;
  for (int i = 0; i < slides.length; i++) {
    final slide = slides[i];
    final slideId = i + 1;
    bool hasNotes = slide.notes.isNotEmpty;
    bool hasImage = slide.imageBytes != null;
    int? currentImageId;

    if (hasImage) {
      currentImageId = imageIdCounter++;
      final imageBytes = slide.imageBytes!;
      archive.addFile(ArchiveFile('ppt/media/image$currentImageId.png', imageBytes.length, imageBytes));
    }

    final slideXml = _buildSlide(slide, currentImageId);
    archive.addFile(ArchiveFile('ppt/slides/slide$slideId.xml', slideXml.length, slideXml));

    final slideRelsXml = _buildSlideRels(hasNotes: hasNotes, imageId: currentImageId, slideId: slideId);
    archive.addFile(ArchiveFile('ppt/slides/_rels/slide$slideId.xml.rels', slideRelsXml.length, slideRelsXml));

    if (hasNotes) {
      final notesXml = _buildNotesSlide(slide);
      archive.addFile(ArchiveFile('ppt/notesSlides/notesSlide$slideId.xml', notesXml.length, notesXml));
      
      final notesRelsXml = _buildNotesRels(slideId);
      archive.addFile(ArchiveFile('ppt/notesSlides/_rels/notesSlide$slideId.xml.rels', notesRelsXml.length, notesRelsXml));
    }
  }

  // Encode the archive to zip
  final zipEncoder = ZipEncoder();
  final zipBytes = zipEncoder.encode(archive);
  return zipBytes;
}

// ---------------------------------------------------------------------------
// XML Generators
// ---------------------------------------------------------------------------

List<int> _utf8(String data) => utf8.encode(data);

List<int> _buildContentTypes(List<Slide> slides) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('Types', namespaces: {'http://schemas.openxmlformats.org/package/2006/content-types': ''}, nest: () {
    builder.element('Default', attributes: {'Extension': 'png', 'ContentType': 'image/png'});
    builder.element('Default', attributes: {'Extension': 'rels', 'ContentType': 'application/vnd.openxmlformats-package.relationships+xml'});
    builder.element('Default', attributes: {'Extension': 'xml', 'ContentType': 'application/xml'});
    builder.element('Override', attributes: {'PartName': '/ppt/presentation.xml', 'ContentType': 'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml'});
    builder.element('Override', attributes: {'PartName': '/ppt/slideMasters/slideMaster1.xml', 'ContentType': 'application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml'});
    builder.element('Override', attributes: {'PartName': '/ppt/slideLayouts/slideLayout1.xml', 'ContentType': 'application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml'});
    builder.element('Override', attributes: {'PartName': '/ppt/theme/theme1.xml', 'ContentType': 'application/vnd.openxmlformats-officedocument.theme+xml'});
    
    for (int i = 0; i < slides.length; i++) {
      builder.element('Override', attributes: {
        'PartName': '/ppt/slides/slide${i + 1}.xml', 
        'ContentType': 'application/vnd.openxmlformats-officedocument.presentationml.slide+xml'
      });
      if (slides[i].notes.isNotEmpty) {
        builder.element('Override', attributes: {
          'PartName': '/ppt/notesSlides/notesSlide${i + 1}.xml', 
          'ContentType': 'application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml'
        });
      }
    }
  });
  return _utf8(builder.buildDocument().toXmlString(pretty: false));
}

List<int> _buildPackageRels() {
  const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''';
  return _utf8(xml);
}

List<int> _buildPresentation(List<Slide> slides) {
  final buffer = StringBuffer();
  buffer.write('<?xml version="1.0" encoding="UTF-8"?>');
  buffer.write('<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">');
  buffer.write('<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>');
  buffer.write('<p:sldIdLst>');
  for (int i = 0; i < slides.length; i++) {
    int slideId = 256 + i;
    int rId = i + 2; // rId1 is slideMaster, rId2 is slide1, etc.
    buffer.write('<p:sldId id="$slideId" r:id="rId$rId"/>');
  }
  buffer.write('</p:sldIdLst>');
  // 16:9 standard size
  buffer.write('<p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>');
  buffer.write('<p:notesSz cx="6858000" cy="9144000"/>');
  buffer.write('</p:presentation>');
  return _utf8(buffer.toString());
}

List<int> _buildPresentationRels(List<Slide> slides) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('Relationships', namespaces: {'http://schemas.openxmlformats.org/package/2006/relationships': ''}, nest: () {
    builder.element('Relationship', attributes: {'Id': 'rId1', 'Type': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster', 'Target': 'slideMasters/slideMaster1.xml'});
    for (int i = 0; i < slides.length; i++) {
      int rId = i + 2;
      builder.element('Relationship', attributes: {
        'Id': 'rId$rId', 
        'Type': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide', 
        'Target': 'slides/slide${i + 1}.xml'
      });
    }
    // Theme is the last relationship
    int themeRId = slides.length + 2;
    builder.element('Relationship', attributes: {
      'Id': 'rId$themeRId', 
      'Type': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme', 
      'Target': 'theme/theme1.xml'
    });
  });
  return _utf8(builder.buildDocument().toXmlString(pretty: false));
}

List<int> _buildTheme(String primary, String bg, String text) {
  // A minimal valid theme with the specified colors
  final xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="CubicLM Theme">
  <a:themeElements>
    <a:clrScheme name="CubicLM">
      <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="$text"/></a:dk2>
      <a:lt2><a:srgbClr val="$bg"/></a:lt2>
      <a:accent1><a:srgbClr val="$primary"/></a:accent1>
      <a:accent2><a:srgbClr val="$primary"/></a:accent2>
      <a:accent3><a:srgbClr val="$primary"/></a:accent3>
      <a:accent4><a:srgbClr val="$primary"/></a:accent4>
      <a:accent5><a:srgbClr val="$primary"/></a:accent5>
      <a:accent6><a:srgbClr val="$primary"/></a:accent6>
      <a:hlink><a:srgbClr val="$primary"/></a:hlink>
      <a:folHlink><a:srgbClr val="$primary"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Office"><a:majorFont><a:latin typeface="Arial"/></a:majorFont><a:minorFont><a:latin typeface="Arial"/></a:minorFont></a:fontScheme>
    <a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>
  </a:themeElements>
  <a:objectDefaults/>
</a:theme>''';
  return _utf8(xml);
}

List<int> _buildSlideMaster(String bg) {
  final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg>
      <p:bgPr>
        <a:solidFill><a:srgbClr val="$bg"/></a:solidFill>
        <a:effectLst/>
      </p:bgPr>
    </p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
    </p:spTree>
  </p:cSld>
  <p:clrMap bg1="lt2" tx1="dk2" bg2="lt1" tx2="dk1" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst>
    <p:sldLayoutId id="2147483649" r:id="rId1"/>
  </p:sldLayoutIdLst>
</p:sldMaster>''';
  return _utf8(xml);
}

List<int> _buildSlideMasterRels() {
  const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>''';
  return _utf8(xml);
}

List<int> _buildSlideLayout() {
  const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">
  <p:cSld name="Blank">
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
    </p:spTree>
  </p:cSld>
</p:sldLayout>''';
  return _utf8(xml);
}

List<int> _buildSlideLayoutRels() {
  const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>''';
  return _utf8(xml);
}

String _escapeXml(String text) {
  return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}

String _textBox(int id, String text, int x, int y, int cx, int cy, {int fontSize = 2400, String align = "l", bool bold = false, String color = "F2F0EA"}) {
  final bld = bold ? ' b="1"' : '';
  return '''
<p:sp>
  <p:nvSpPr><p:cNvPr id="$id" name="TextBox"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
  <p:spPr>
    <a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
  </p:spPr>
  <p:txBody>
    <a:bodyPr wrap="square" rtlCol="0"><a:spAutoFit/></a:bodyPr>
    <a:lstStyle/>
    <a:p>
      <a:pPr algn="$align"/>
      <a:r>
        <a:rPr lang="en-US" sz="$fontSize"$bld><a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:rPr>
        <a:t>${_escapeXml(text)}</a:t>
      </a:r>
    </a:p>
  </p:txBody>
</p:sp>
''';
}

String _bulletList(int id, List<String> items, int x, int y, int cx, int cy, {int fontSize = 2400, String color = "F2F0EA"}) {
  final buffer = StringBuffer();
  buffer.write('''
<p:sp>
  <p:nvSpPr><p:cNvPr id="$id" name="List"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
  <p:spPr>
    <a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
  </p:spPr>
  <p:txBody>
    <a:bodyPr wrap="square" rtlCol="0"/>
    <a:lstStyle/>
''');

  for (final item in items) {
    buffer.write('''
    <a:p>
      <a:pPr marL="342900" indent="-342900">
        <a:buFont typeface="Arial"/>
        <a:buChar char="•"/>
      </a:pPr>
      <a:r>
        <a:rPr lang="en-US" sz="$fontSize"><a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:rPr>
        <a:t>${_escapeXml(item)}</a:t>
      </a:r>
    </a:p>
''');
  }

  buffer.write('''
  </p:txBody>
</p:sp>
''');
  return buffer.toString();
}

String _solidRect(int id, String fillColor, int x, int y, int cx, int cy, {String? lineColor}) {
  final ln = lineColor == null
      ? '<a:ln><a:noFill/></a:ln>'
      : '<a:ln><a:solidFill><a:srgbClr val="$lineColor"/></a:solidFill></a:ln>';
  return '''
<p:sp>
  <p:nvSpPr><p:cNvPr id="$id" name="Rect"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
  <p:spPr>
    <a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:solidFill><a:srgbClr val="$fillColor"/></a:solidFill>
    $ln
  </p:spPr>
  <p:txBody>
    <a:bodyPr wrap="none"><a:spAutoFit/></a:bodyPr>
    <a:lstStyle/>
    <a:p><a:endParaRPr lang="en-US"/></a:p>
  </p:txBody>
</p:sp>
''';
}

String _imageRect(int id, int imageRId, int x, int y, int cx, int cy) {
  return '''
<p:pic>
  <p:nvPicPr>
    <p:cNvPr id="$id" name="Picture"/>
    <p:cNvPicPr>
      <a:picLocks noChangeAspect="1"/>
    </p:cNvPicPr>
    <p:nvPr/>
  </p:nvPicPr>
  <p:blipFill>
    <a:blip r:embed="rId$imageRId"/>
    <a:stretch><a:fillRect/></a:stretch>
  </p:blipFill>
  <p:spPr>
    <a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
  </p:spPr>
</p:pic>
''';
}

List<int> _buildSlide(Slide slide, int? imageId) {
  final buffer = StringBuffer();
  buffer.write('''<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
''');

  int spId = 2;
  // Common dims
  const cxW = 12192000;
  const cyH = 6858000;
  const margin = 800000;

  switch (slide.layout) {
    case 'title':
      buffer.write(_textBox(spId++, slide.title, margin, 2000000, cxW - margin*2, 1000000, fontSize: 5400, align: "ctr", bold: true, color: "D97757"));
      if (slide.subtitle.isNotEmpty) {
        buffer.write(_textBox(spId++, slide.subtitle, margin, 3200000, cxW - margin*2, 1000000, fontSize: 2800, align: "ctr"));
      }
      break;

    case 'bullets':
    case 'timeline':
    case 'summary': // Can share standard layout structure
      buffer.write(_textBox(spId++, slide.title, margin, margin, cxW - margin*2, 1000000, fontSize: 4400, bold: true, color: "D97757"));
      var bodyY = margin + 1200000;
      if (slide.subtitle.isNotEmpty) {
        buffer.write(_textBox(spId++, slide.subtitle, margin, bodyY, cxW - margin*2, 600000, fontSize: 2400, color: "B8B2A6"));
        bodyY += 700000;
      }
      var bodyPts = slide.points;
      if (slide.layout == 'timeline') {
        bodyPts = [for (var i = 0; i < slide.points.length; i++) '${i + 1}. ${slide.points[i]}'];
      } else if (slide.layout == 'summary') {
        bodyPts = slide.points.map((p) => '✓ $p').toList();
      }
      buffer.write(_bulletList(spId++, bodyPts, margin, bodyY, cxW - margin*2, cyH - bodyY - margin, fontSize: 2800));
      break;

    case 'image':
      buffer.write(_textBox(spId++, slide.title, margin, margin, cxW - margin*2, 1000000, fontSize: 4400, bold: true, color: "D97757"));
      int leftW = (cxW - margin*3) ~/ 2;
      buffer.write(_bulletList(spId++, slide.points, margin, margin + 1200000, leftW, cyH - margin*2 - 1200000, fontSize: 2400));
      if (imageId != null) {
        // rId for image usually is next after slide layout, so rId2 (if notes don't conflict, wait, we set it specifically in rels)
        buffer.write(_imageRect(spId++, 2, margin*2 + leftW, margin + 1200000, leftW, cyH - margin*2 - 1200000));
      } else {
        buffer.write(_textBox(spId++, "Image Placeholder\n${slide.imagePrompt}", margin*2 + leftW, margin + 1200000, leftW, cyH - margin*2 - 1200000, fontSize: 2000, align: "ctr"));
      }
      break;

    case 'quote':
      buffer.write(_textBox(spId++, slide.title, margin, margin, cxW - margin*2, 1000000, fontSize: 4400, bold: true, color: "D97757"));
      buffer.write(_textBox(spId++, '"${slide.points.isNotEmpty ? slide.points.first : ""}"', margin, 2500000, cxW - margin*2, 2000000, fontSize: 4000, align: "ctr"));
      if (slide.quoteAuthor.isNotEmpty) {
        buffer.write(_textBox(spId++, "- ${slide.quoteAuthor}", margin, 4500000, cxW - margin*2, 1000000, fontSize: 2400, align: "ctr", color: "D97757"));
      }
      break;

    case 'comparison':
      buffer.write(_textBox(spId++, slide.title, margin, margin, cxW - margin*2, 1000000, fontSize: 4400, bold: true, color: "D97757"));
      int halfW = (cxW - margin*3) ~/ 2;
      if (slide.columns.isNotEmpty) {
        buffer.write(_bulletList(spId++, slide.columns[0], margin, margin + 1200000, halfW, cyH - margin*2 - 1200000, fontSize: 2400));
      }
      if (slide.columns.length > 1) {
        buffer.write(_bulletList(spId++, slide.columns[1], margin*2 + halfW, margin + 1200000, halfW, cyH - margin*2 - 1200000, fontSize: 2400));
      }
      break;

    case 'stats':
      buffer.write(_textBox(spId++, slide.title, margin, margin, cxW - margin*2, 1000000, fontSize: 4400, bold: true, color: "D97757"));
      if (slide.stats.isNotEmpty) {
        int statCount = slide.stats.length;
        int statW = (cxW - margin * (statCount + 1)) ~/ statCount;
        for (int i = 0; i < statCount; i++) {
          int x = margin + (margin + statW) * i;
          buffer.write(_textBox(spId++, slide.stats[i]['value'] ?? '', x, 2500000, statW, 1000000, fontSize: 6000, align: "ctr", bold: true, color: "D97757"));
          buffer.write(_textBox(spId++, slide.stats[i]['label'] ?? '', x, 3800000, statW, 1000000, fontSize: 2400, align: "ctr"));
        }
      }
      break;

    case 'chart':
      buffer.write(_textBox(spId++, slide.title, margin, margin, cxW - margin*2, 1000000, fontSize: 4400, bold: true, color: "D97757"));
      final chartData = slide.chartData;
      if (chartData.isNotEmpty && chartData['items'] is List) {
        final items = (chartData['items'] as List).whereType<Map>().take(8).toList();
        final type = (chartData['type'] ?? 'bar').toString();
        // Parse numeric values for scaling
        final vals = items.map((e) {
          final raw = (e['value'] ?? '0').toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
          return double.tryParse(raw) ?? 0.0;
        }).toList();
        final maxV = vals.fold<double>(0, (a, b) => b > a ? b : a);
        if (type == 'bar' && items.isNotEmpty && maxV > 0) {
          // Visual horizontal bars: label | bar | value
          const barAreaX = 3200000;
          const barAreaW = cxW - margin - barAreaX;
          const rowH = 550000;
          const gap = 150000;
          int y0 = 2000000;
          for (int i = 0; i < items.length; i++) {
            final label = (items[i]['label'] ?? '').toString();
            final value = (items[i]['value'] ?? '').toString();
            final w = ((vals[i] / maxV) * barAreaW).toInt().clamp(200000, barAreaW);
            final y = y0 + i * (rowH + gap);
            buffer.write(_textBox(spId++, label, margin, y, barAreaX - margin - 200000, rowH, fontSize: 2200));
            buffer.write(_solidRect(spId++, 'D97757', barAreaX, y + 80000, w, rowH - 160000));
            buffer.write(_textBox(spId++, value, barAreaX + w + 200000, y, cxW - margin - barAreaX - w - 200000, rowH, fontSize: 2200, bold: true, color: "D97757"));
          }
        } else {
          // Donut/line or non-numeric: structured labeled list
          buffer.write(_textBox(spId++, '[$type chart]', margin, 1500000, cxW - margin*2, 500000, fontSize: 2000, align: "ctr", color: "8E8B85"));
          int idx = 0;
          for (final item in items) {
            final label = (item['label'] ?? '').toString();
            final value = (item['value'] ?? '').toString();
            buffer.write(_textBox(spId++, '$label: $value', margin, 2200000 + idx * 600000, cxW - margin*2, 500000, fontSize: 2600, align: "ctr"));
            idx++;
          }
        }
      }
      break;

    default:
      // Fallback
      buffer.write(_textBox(spId++, slide.title, margin, margin, cxW - margin*2, 1000000, fontSize: 4400, bold: true, color: "D97757"));
      buffer.write(_bulletList(spId++, slide.points, margin, margin + 1200000, cxW - margin*2, cyH - margin*2 - 1200000, fontSize: 2800));
  }

  buffer.write('''
    </p:spTree>
  </p:cSld>
</p:sld>''');
  return _utf8(buffer.toString());
}

List<int> _buildSlideRels({required bool hasNotes, required int? imageId, required int slideId}) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('Relationships', namespaces: {'http://schemas.openxmlformats.org/package/2006/relationships': ''}, nest: () {
    builder.element('Relationship', attributes: {'Id': 'rId1', 'Type': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout', 'Target': '../slideLayouts/slideLayout1.xml'});
    int nextId = 2;
    if (imageId != null) {
      builder.element('Relationship', attributes: {
        'Id': 'rId$nextId', 
        'Type': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image', 
        'Target': '../media/image$imageId.png'
      });
      nextId++;
    }
    if (hasNotes) {
      builder.element('Relationship', attributes: {
        'Id': 'rId$nextId', 
        'Type': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide', 
        'Target': '../notesSlides/notesSlide$slideId.xml'
      });
    }
  });
  return _utf8(builder.buildDocument().toXmlString(pretty: false));
}

List<int> _buildNotesSlide(Slide slide) {
  const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr/>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
        <p:spPr><a:xfrm><a:off x="685800" y="4572000"/><a:ext cx="5486400" cy="4114800"/></a:xfrm></p:spPr>
        <p:txBody>
          <a:bodyPr/>
          <a:lstStyle/>
          <a:p><a:r><a:rPr sz="1200"/><a:t>__NOTES__</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:notes>''';
  return _utf8(xml.replaceFirst('__NOTES__', _escapeXml(slide.notes)));
}

List<int> _buildNotesRels(int slideId) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('Relationships', namespaces: {'http://schemas.openxmlformats.org/package/2006/relationships': ''}, nest: () {
    builder.element('Relationship', attributes: {'Id': 'rId1', 'Type': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide', 'Target': '../slides/slide$slideId.xml'});
  });
  return _utf8(builder.buildDocument().toXmlString(pretty: false));
}
