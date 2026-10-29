import 'dart:convert';

/// One file of a pinned model snapshot.
class ModelFileSpec {
  const ModelFileSpec({
    required this.path,
    required this.size,
    required this.sha256,
  });

  /// Relative path with forward slashes, e.g. `onnx/model_quantized.onnx`.
  final String path;
  final int size;
  final String sha256;

  factory ModelFileSpec.fromJson(Map<String, dynamic> json) => ModelFileSpec(
    path: json['path'] as String,
    size: json['size'] as int,
    sha256: (json['sha256'] as String).toLowerCase(),
  );
}

/// A pinned upstream revision and the exact files expected from it.
class ModelManifest {
  const ModelManifest({
    required this.id,
    required this.repo,
    required this.commit,
    required this.files,
  });

  final String id;

  /// Hugging Face repo, e.g. `onnx-community/embeddinggemma-2-ONNX`.
  final String repo;
  final String commit;
  final List<ModelFileSpec> files;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  /// Download URL on [mirror] (`https://hf-mirror.com`, `https://huggingface.co`).
  Uri urlFor(String mirror, ModelFileSpec file) {
    final base = mirror.endsWith('/')
        ? mirror.substring(0, mirror.length - 1)
        : mirror;
    return Uri.parse('$base/$repo/resolve/$commit/${file.path}');
  }

  /// Parses the JSON format of `models/*_manifest.json`.
  factory ModelManifest.fromJson(Map<String, dynamic> json, {String? repo}) {
    return ModelManifest(
      id: json['model_id'] as String? ?? 'unknown',
      repo: repo ?? json['repo'] as String? ?? '',
      commit: json['commit'] as String,
      files: [
        for (final f in json['files'] as List<dynamic>)
          ModelFileSpec.fromJson(f as Map<String, dynamic>),
      ],
    );
  }

  factory ModelManifest.parse(String source, {String? repo}) =>
      ModelManifest.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
        repo: repo,
      );
}

/// EmbeddingGemma 2 ONNX export. Mirrors
/// `models/embeddinggemma2_onnx_manifest.json` (a test guards against drift)
/// so verification and download work in a Release build, where the repo's
/// `models/` and `scripts/` folders are not shipped.
const ModelManifest embeddingGemmaManifest = ModelManifest(
  id: 'embeddinggemma2-st140',
  repo: 'onnx-community/embeddinggemma-2-ONNX',
  commit: 'daa72c51243991dfcaf9f9137d2c573d8f7790c0',
  files: [
    ModelFileSpec(
      path: 'config.json',
      size: 5031,
      sha256: '8d011bfe08b5e345bbe0b81e5c6fd02c381920b345b986047bc2a33ce7b90d1d',
    ),
    ModelFileSpec(
      path: 'config_sentence_transformers.json',
      size: 1565,
      sha256: '031e56a498d33c349ab489a21885bcfe25b4fcba841149dc99e1e90d4a7c28f5',
    ),
    ModelFileSpec(
      path: 'preprocessor_config.json',
      size: 560,
      sha256: '9344893f8d0573a46ebb2ca54c03f56d044cea194c8dcfb1f4d652240ac21daa',
    ),
    ModelFileSpec(
      path: 'processor_config.json',
      size: 1788,
      sha256: '168f6a08522f3ce5dea596d94d003af2fd691742d4f41fe1f9d8cce76bfbf69c',
    ),
    ModelFileSpec(
      path: 'tokenizer_config.json',
      size: 1599,
      sha256: '17bd5d6e9364ca49a534e1502076593317c298d4a663623091ed45388f004874',
    ),
    ModelFileSpec(
      path: 'tokenizer.json',
      size: 32170510,
      sha256: '4d777ef5bdc1aa36227abdfb77c3e49e7b9c892d16e1b6bda41c393504828be4',
    ),
    ModelFileSpec(
      path: 'onnx/model_quantized.onnx',
      size: 495165,
      sha256: 'd06edd601f851c633a2519304cbeb8dc6170d7ceb61b436625c17fb9b6e74953',
    ),
    ModelFileSpec(
      path: 'onnx/model_quantized.onnx_data',
      size: 313724928,
      sha256: '278a7ff1248c3618e4bd11a607fc54f7bdc7778854230f3956d3f86bd9db4f3b',
    ),
    ModelFileSpec(
      path: 'onnx/vision_encoder_quantized.onnx',
      size: 162495,
      sha256: 'bb0de2df53a2448a32dc7908a187c168c8afd514d4d6f674f7f46024875fa4e3',
    ),
    ModelFileSpec(
      path: 'onnx/vision_encoder_quantized.onnx_data',
      size: 195228672,
      sha256: '3dabd69c0a36e9a8771ad82030dde74daa5a0e02b7047a5d3f3382b1137bab89',
    ),
  ],
);
