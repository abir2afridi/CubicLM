class AiModel {
  static const runtimeLlama = 'llama';
  static const runtimeLiteRt = 'litert';
  static const runtimeSd = 'sd';

  static bool hasVisionMarker(String value) {
    final lower = value.toLowerCase();
    return lower.contains('vl-') ||
        lower.contains('-vl') ||
        lower.contains('llava') ||
        lower.contains('vision');
  }

  final String name;
  final String filename;
  final String url;
  final String size;
  final String description;
  final String template;
  final String runtime;
  final bool isVision;
  final bool isImported;
  final bool isCustom;

  /// Alternate quant downloads from the catalog (`variants:` list).
  /// Empty for imported/custom models and entries without variants.
  final List<ModelVariant> variants;

  AiModel({
    required this.name,
    required this.filename,
    required this.url,
    required this.size,
    required this.description,
    required this.template,
    String? runtime,
    this.isVision = false,
    this.isImported = false,
    this.isCustom = false,
    List<ModelVariant>? variants,
  })  : runtime = runtime ?? runtimeFromFilename(filename, template: template),
        variants = variants ?? const [];

  factory AiModel.fromMap(Map<String, String> map) => AiModel(
        name: map['name'] ?? '',
        filename: map['filename'] ?? '',
        url: map['url'] ?? '',
        size: map['size'] ?? '',
        description: map['description'] ?? '',
        template: map['template'] ?? 'chatml',
        runtime: map['runtime'],
        isVision: map['vision'] == 'true',
        isImported: map['imported'] == 'true',
        isCustom: map['custom'] == 'true',
      );

  /// Dynamic parse for catalog JSON (may carry a `variants:` list of
  /// {quant, filename, url, size} maps). Never throws on bad shapes.
  factory AiModel.fromDynamic(Map map) {
    String str(String k) => map[k]?.toString() ?? '';
    final variants = <ModelVariant>[];
    try {
      final raw = map['variants'];
      if (raw is List) {
        for (final v in raw.whereType<Map>()) {
          final q = v['quant']?.toString() ?? '';
          final f = v['filename']?.toString() ?? '';
          final u = v['url']?.toString() ?? '';
          if (q.isEmpty || f.isEmpty || u.isEmpty) continue;
          if (!u.toLowerCase().startsWith('https://')) continue;
          if (!f.toLowerCase().endsWith('.gguf') &&
              !f.toLowerCase().endsWith('.litertlm') &&
              !f.toLowerCase().endsWith('.safetensors')) {
            continue;
          }
          variants.add(ModelVariant(
            quant: q,
            filename: f,
            url: u,
            size: v['size']?.toString() ?? '',
          ));
        }
      }
    } catch (_) {}
    return AiModel(
      name: str('name'),
      filename: str('filename'),
      url: str('url'),
      size: str('size'),
      description: str('description'),
      template: str('template').isEmpty ? 'chatml' : str('template'),
      runtime: map['runtime']?.toString(),
      isVision: map['vision'] == 'true' || map['vision'] == true,
      isImported: map['imported'] == 'true' || map['imported'] == true,
      isCustom: map['custom'] == 'true' || map['custom'] == true,
      variants: variants,
    );
  }

  /// Download choices: default entry + one per variant (as full models so
  /// the filename-keyed download/load/delete flow works unchanged).
  List<AiModel> variantOptions() {
    if (variants.isEmpty) return [this];
    return [
      this,
      for (final v in variants)
        copyWith(
          name: '$name (${v.quant})',
          filename: v.filename,
          url: v.url,
          size: v.size.isEmpty ? size : v.size,
        ),
    ];
  }

  Map<String, String> toMap() => {
        'name': name,
        'filename': filename,
        'url': url,
        'size': size,
        'description': description,
        'template': template,
        'runtime': runtime,
        if (isVision) 'vision': 'true',
        if (isImported) 'imported': 'true',
        if (isCustom) 'custom': 'true',
      };

  static String runtimeFromFilename(String filename, {String? template}) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.litertlm')) return runtimeLiteRt;
    if (lower.endsWith('.safetensors') || template == runtimeSd) {
      return runtimeSd;
    }
    return runtimeLlama;
  }

  AiModel copyWith({
    String? name,
    String? filename,
    String? url,
    String? size,
    String? description,
    String? template,
    String? runtime,
    bool? isVision,
    bool? isImported,
    bool? isCustom,
    List<ModelVariant>? variants,
  }) {
    return AiModel(
      name: name ?? this.name,
      filename: filename ?? this.filename,
      url: url ?? this.url,
      size: size ?? this.size,
      description: description ?? this.description,
      template: template ?? this.template,
      runtime: runtime ?? this.runtime,
      isVision: isVision ?? this.isVision,
      isImported: isImported ?? this.isImported,
      isCustom: isCustom ?? this.isCustom,
      variants: variants ?? this.variants,
    );
  }
}

/// One alternate quant download for a catalog model.
class ModelVariant {
  final String quant;
  final String filename;
  final String url;
  final String size;

  const ModelVariant({
    required this.quant,
    required this.filename,
    required this.url,
    this.size = '',
  });
}
