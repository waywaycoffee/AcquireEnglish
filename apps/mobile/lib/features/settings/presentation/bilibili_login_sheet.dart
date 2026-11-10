import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../import_course/data/bilibili_auth_service.dart';
import '../../player/presentation/widgets/study_shell_tokens.dart';
import 'settings_provider.dart';

/// Encodes a scannable Bilibili login QR as PNG (white background + quiet zone).
Future<Uint8List> encodeBilibiliLoginQrPng(
  String qrContent, {
  int size = 768,
  int quietZone = 72,
}) async {
  final String data = qrContent.trim();
  if (data.isEmpty) {
    throw ArgumentError('qrContent is empty');
  }
  if (quietZone * 2 >= size) {
    throw ArgumentError('quietZone leaves no room for the QR');
  }

  final QrPainter painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    // Deprecated but still required so light modules are opaque white.
    // ignore: deprecated_member_use
    emptyColor: const Color(0xFFFFFFFF),
    eyeStyle: const QrEyeStyle(
      color: Color(0xFF000000),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      color: Color(0xFF000000),
    ),
  );

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final double out = size.toDouble();
  final double pad = quietZone.toDouble();
  canvas
    ..drawRect(
      Rect.fromLTWH(0, 0, out, out),
      Paint()..color = const Color(0xFFFFFFFF),
    )
    ..save()
    ..translate(pad, pad);
  painter.paint(canvas, Size(out - pad * 2, out - pad * 2));
  canvas.restore();

  final ui.Image image = await recorder.endRecording().toImage(size, size);
  final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('二维码编码失败');
  }
  return bytes.buffer.asUint8List();
}

Future<bool> showBilibiliLoginSheet(
  BuildContext context,
  WidgetRef ref, {
  bool requiredLogin = false,
}) async {
  final bool? ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !requiredLogin,
    enableDrag: !requiredLogin,
    backgroundColor: StudyShellTokens.surface,
    builder: (BuildContext context) {
      return PopScope(
        canPop: !requiredLogin,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: BilibiliLoginPanel(
            requiredLogin: requiredLogin,
            onLoggedIn: () => Navigator.of(context).pop(true),
            onCancel: requiredLogin
                ? null
                : () => Navigator.of(context).pop(false),
          ),
        ),
      );
    },
  );
  return ok ?? false;
}

/// Blocks the whole app until a Bilibili login Cookie is available.
class BilibiliLoginGate extends ConsumerWidget {
  const BilibiliLoginGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LearningSettingsState settings = ref.watch(learningSettingsProvider);
    if (settings.hasBilibiliCookie) {
      return child;
    }
    return const _BilibiliRequiredLoginPage();
  }
}

class _BilibiliRequiredLoginPage extends StatelessWidget {
  const _BilibiliRequiredLoginPage();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StudyShellTokens.surface,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: const SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: BilibiliLoginPanel(
                requiredLogin: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BilibiliLoginPanel extends ConsumerStatefulWidget {
  const BilibiliLoginPanel({
    this.requiredLogin = false,
    this.onLoggedIn,
    this.onCancel,
    super.key,
  });

  final bool requiredLogin;
  final VoidCallback? onLoggedIn;
  final VoidCallback? onCancel;

  @override
  ConsumerState<BilibiliLoginPanel> createState() => _BilibiliLoginPanelState();
}

class _BilibiliLoginPanelState extends ConsumerState<BilibiliLoginPanel> {
  final BilibiliAuthService _auth = BilibiliAuthService();
  final TextEditingController _manualCookie = TextEditingController();
  final GlobalKey _qrBoundaryKey = GlobalKey(debugLabel: 'bilibili_login_qr');
  Timer? _pollTimer;
  String? _qrcodeKey;
  String? _qrContent;
  String _status = '正在生成二维码…';
  bool _busy = true;
  bool _showManual = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_startSession());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _manualCookie.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在生成二维码…';
      _qrcodeKey = null;
      _qrContent = null;
    });
    try {
      final BilibiliQrSession session = await _auth.createQrSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _qrcodeKey = session.qrcodeKey;
        _qrContent = session.qrContent;
        _busy = false;
        _status = '请使用哔哩哔哩 App 扫码登录';
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_pollOnce());
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = e;
        _status = '二维码生成失败';
      });
    }
  }

  Future<void> _pollOnce() async {
    final String? key = _qrcodeKey;
    if (key == null || key.isEmpty) {
      return;
    }
    try {
      final BilibiliQrPollResult result = await _auth.pollQrSession(key);
      if (!mounted) {
        return;
      }
      switch (result.status) {
        case BilibiliQrPollStatus.pending:
        case BilibiliQrPollStatus.scanned:
          setState(() => _status = result.message);
          return;
        case BilibiliQrPollStatus.expired:
          _pollTimer?.cancel();
          setState(() {
            _status = result.message;
            _error = 'expired';
          });
          return;
        case BilibiliQrPollStatus.failed:
          setState(() {
            _status = result.message;
            _error = result.message;
          });
          return;
        case BilibiliQrPollStatus.confirmed:
          _pollTimer?.cancel();
          final BilibiliLoginSession? session = result.session;
          if (session == null) {
            setState(() {
              _status = '登录成功但 Cookie 为空';
              _error = 'empty-session';
            });
            return;
          }
          _applyLogin(
            cookie: session.cookieHeader,
            userId: session.dedeUserId,
          );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '轮询失败：$e';
        _error = e;
      });
    }
  }

  void _applyLogin({required String cookie, String userId = ''}) {
    ref.read(learningSettingsProvider.notifier).setBilibiliLogin(
          cookieOrSessdata: cookie,
          userId: userId,
        );
    widget.onLoggedIn?.call();
  }

  void _submitManualCookie() {
    final String value = _manualCookie.text.trim();
    if (value.isEmpty) {
      setState(() {
        _error = 'empty';
        _status = '请粘贴 SESSDATA 或整段 Cookie';
      });
      return;
    }
    _pollTimer?.cancel();
    _applyLogin(cookie: value);
  }

  Future<Uint8List> _captureDisplayedQrPng() async {
    final BuildContext? qrContext = _qrBoundaryKey.currentContext;
    final RenderObject? renderObject = qrContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('二维码尚未准备好');
    }
    // Match a normal screenshot of the on-screen QR (white card + quiet zone).
    final double pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(
      2.0,
      4.0,
    );
    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    if (bytes == null) {
      throw StateError('二维码截取失败');
    }
    return bytes.buffer.asUint8List();
  }

  Future<void> _saveQrToAlbum() async {
    final String? qr = _qrContent;
    if (qr == null || qr.isEmpty) {
      return;
    }
    try {
      final bool hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final bool granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要相册权限才能保存二维码')),
          );
          return;
        }
      }
      Uint8List pngBytes;
      try {
        pngBytes = await _captureDisplayedQrPng();
      } catch (_) {
        // Fallback if the widget boundary is unavailable mid-refresh.
        pngBytes = await encodeBilibiliLoginQrPng(qr);
      }
      await Gal.putImageBytes(
        pngBytes,
        name: 'bilibili_login_qr_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('二维码已保存到相册，可用另一台手机扫码')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? qr = _qrContent;
    final bool canSaveQr = !_busy && qr != null && qr.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.requiredLogin ? '登录后继续使用' : '登录哔哩哔哩',
          style: const TextStyle(
            color: StudyShellTokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.requiredLogin
              ? '本应用需要 B 站登录态以导入视频与官方字幕。请用手机哔哩哔哩 App 扫码确认；不会保存账号密码。'
              : '用手机哔哩哔哩 App 扫码，确认后即可拉取官方字幕与更高清晰度视频。 不会保存账号密码。',
          style: const TextStyle(color: StudyShellTokens.textSecondary),
        ),
        const SizedBox(height: 16),
        Center(
          child: RepaintBoundary(
            key: _qrBoundaryKey,
            child: Container(
              width: 220,
              height: 220,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _busy
                  ? const CircularProgressIndicator()
                  : (qr == null || qr.isEmpty)
                  ? Text(
                      _error == null ? '暂无二维码' : '生成失败',
                      style: const TextStyle(color: Colors.black54),
                    )
                  : QrImageView(
                      data: qr,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _status,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _error == null
                ? StudyShellTokens.textSecondary
                : Colors.redAccent,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _startSession,
                child: const Text('刷新二维码'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canSaveQr ? _saveQrToAlbum : null,
                icon: const Icon(Icons.save_alt_rounded, size: 18),
                label: const Text('保存到相册'),
              ),
            ),
          ],
        ),
        if (widget.onCancel != null) ...<Widget>[
          const SizedBox(height: 8),
          FilledButton(
            onPressed: widget.onCancel,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFB7299),
            ),
            child: const Text('关闭'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _showManual = !_showManual),
          child: Text(_showManual ? '收起手动填写' : '手动填写 Cookie / SESSDATA'),
        ),
        if (_showManual) ...<Widget>[
          TextField(
            controller: _manualCookie,
            obscureText: true,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(color: StudyShellTokens.textPrimary),
            decoration: const InputDecoration(
              hintText: '粘贴 SESSDATA 或整段 Cookie',
              hintStyle: TextStyle(color: StudyShellTokens.textMuted),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _submitManualCookie,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFB7299),
            ),
            child: const Text('保存并进入'),
          ),
        ],
      ],
    );
  }
}
