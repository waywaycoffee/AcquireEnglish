import 'dart:convert';
import 'dart:io';

/// Result from [tools/subtitle/fill_missing.py] (auto-subs / whisper-subtitle-generator).
class ExternalSubtitleFillResult {
  const ExternalSubtitleFillResult({
    required this.enPath,
    required this.zhPath,
    required this.engine,
    required this.needChineseStill,
  });

  final String? enPath;
  final String? zhPath;
  final String? engine;
  final bool needChineseStill;
}

/// Desktop sidecar that shells out to vendored auto-subs /
/// whisper-subtitle-generator. Returns null when the tool is unavailable
/// (typical on Android APK builds).
class ExternalSubtitleFill {
  const ExternalSubtitleFill();

  /// True when Python fill CLI + venv look usable on this machine.
  Future<bool> isAvailable() async {
    final _ResolvedTools? tools = await _resolveTools();
    return tools != null;
  }

  /// Run fill for missing sides. Caller still runs App EN→ZH when
  /// [ExternalSubtitleFillResult.needChineseStill] is true.
  Future<ExternalSubtitleFillResult?> fillMissing({
    required String videoPath,
    required String outDir,
    required bool needEnglish,
    required bool needChinese,
    String? enInPath,
    String model = 'base.en',
    String engine = 'auto',
    void Function(String label)? onProgress,
  }) async {
    if (!needEnglish && !needChinese) {
      return null;
    }
    final _ResolvedTools? tools = await _resolveTools();
    if (tools == null) {
      return null;
    }
    if (!File(videoPath).existsSync()) {
      return null;
    }

    await Directory(outDir).create(recursive: true);
    onProgress?.call(
      needEnglish
          ? '正在用 auto-subs / Whisper 生成英文字幕…'
          : '正在准备中文字幕补全…',
    );

    final List<String> args = <String>[
      tools.scriptPath,
      '--video',
      videoPath,
      '--out-dir',
      outDir,
      '--model',
      model,
      '--engine',
      engine,
      if (needEnglish) '--need-english',
      if (needChinese) '--need-chinese',
      if ((enInPath ?? '').trim().isNotEmpty) ...<String>[
        '--en-in',
        enInPath!.trim(),
      ],
    ];

    final String sep = Platform.isWindows ? ';' : ':';
    final String pythonPathExtra = <String>[
      _join(tools.rootPath, <String>['vendor', 'auto-subs', 'src']),
      _join(tools.rootPath, <String>[
        'vendor',
        'whisper-subtitle-generator',
      ]),
      if ((Platform.environment['PYTHONPATH'] ?? '').isNotEmpty)
        Platform.environment['PYTHONPATH']!,
    ].join(sep);

    final ProcessResult result = await Process.run(
      tools.pythonPath,
      args,
      workingDirectory: tools.rootPath,
      environment: <String, String>{
        ...Platform.environment,
        'PYTHONPATH': pythonPathExtra,
      },
    );

    final String stdout = '${result.stdout}'.trim();
    final String stderr = '${result.stderr}'.trim();
    if (result.exitCode != 0) {
      throw StateError(
        '外部字幕补全失败 (exit ${result.exitCode}): '
        '${stdout.isNotEmpty ? stdout : stderr}',
      );
    }

    final String jsonLine = stdout
        .split('\n')
        .map((String line) => line.trim())
        .lastWhere(
          (String line) => line.startsWith('{'),
          orElse: () => '',
        );
    if (jsonLine.isEmpty) {
      throw StateError('外部字幕补全无输出：$stderr');
    }
    final Object? decoded = jsonDecode(jsonLine);
    if (decoded is! Map) {
      throw StateError('外部字幕补全输出无法解析');
    }
    if (decoded['ok'] != true) {
      throw StateError('${decoded['error'] ?? '外部字幕补全失败'}');
    }

    final String? enPath = _optionalPath(decoded['enPath']);
    final String? zhPath = _optionalPath(decoded['zhPath']);
    if (needEnglish && (enPath == null || !File(enPath).existsSync())) {
      throw StateError('外部引擎未写出英文字幕');
    }

    return ExternalSubtitleFillResult(
      enPath: enPath,
      zhPath: zhPath,
      engine: decoded['engine']?.toString(),
      needChineseStill: decoded['needChineseStill'] == true || needChinese,
    );
  }

  static String? _optionalPath(Object? value) {
    final String text = '$value'.trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  static String _join(String root, List<String> parts) {
    return <String>[root, ...parts].join(Platform.pathSeparator);
  }

  Future<_ResolvedTools?> _resolveTools() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Phone builds ship whisper.cpp instead of the Python stack.
      return null;
    }

    final String? fromEnv = Platform.environment['ACQUIRE_SUBTITLE_TOOLS']
        ?.trim();
    final List<String> candidates = <String>[
      if (fromEnv != null && fromEnv.isNotEmpty) fromEnv,
      _join(Directory.current.path, <String>['tools', 'subtitle']),
      _join(Directory.current.path, <String>['..', 'tools', 'subtitle']),
      _join(Directory.current.path, <String>[
        '..',
        '..',
        'tools',
        'subtitle',
      ]),
    ];

    Directory cursor = Directory.current;
    for (int i = 0; i < 6; i++) {
      candidates.add(_join(cursor.path, <String>['tools', 'subtitle']));
      final Directory parent = cursor.parent;
      if (parent.path == cursor.path) {
        break;
      }
      cursor = parent;
    }

    for (final String raw in candidates) {
      final String root = File(raw).absolute.path;
      final String script = _join(root, <String>['fill_missing.py']);
      if (!File(script).existsSync()) {
        continue;
      }
      final String venvPython = Platform.isWindows
          ? _join(root, <String>['.venv', 'Scripts', 'python.exe'])
          : _join(root, <String>['.venv', 'bin', 'python']);
      final String python = File(venvPython).existsSync()
          ? venvPython
          : (Platform.isWindows ? 'python' : 'python3');
      return _ResolvedTools(
        rootPath: root,
        scriptPath: script,
        pythonPath: python,
      );
    }
    return null;
  }
}

class _ResolvedTools {
  const _ResolvedTools({
    required this.rootPath,
    required this.scriptPath,
    required this.pythonPath,
  });

  final String rootPath;
  final String scriptPath;
  final String pythonPath;
}
