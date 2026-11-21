import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../domain/module_access.dart';

/// Wraps a learning entry; shows a graceful paywall when the module is locked.
///
/// - [softBrowse]: always show [child] so catalogs stay browsable; gate items
///   with [resolveModuleContentAccess] / free-preview helpers.
/// - [freePreviewAllowed]: unlock this specific content without a purchase.
class ModuleGate extends ConsumerStatefulWidget {
  const ModuleGate({
    super.key,
    required this.moduleCode,
    required this.child,
    this.title,
    this.softBrowse = false,
    this.freePreviewAllowed = false,
  });

  final String moduleCode;
  final Widget child;
  final String? title;
  final bool softBrowse;
  final bool freePreviewAllowed;

  @override
  ConsumerState<ModuleGate> createState() => _ModuleGateState();
}

class _ModuleGateState extends ConsumerState<ModuleGate> {
  bool _loading = true;
  bool _allowed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_check);
  }

  @override
  void didUpdateWidget(covariant ModuleGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moduleCode != widget.moduleCode ||
        oldWidget.softBrowse != widget.softBrowse ||
        oldWidget.freePreviewAllowed != widget.freePreviewAllowed) {
      Future.microtask(_check);
    }
  }

  Future<void> _check() async {
    if (widget.softBrowse || widget.freePreviewAllowed) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _allowed = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final bool allowed = await resolveModuleContentAccess(
      ref,
      moduleCode: widget.moduleCode,
      freePreviewAllowed: widget.freePreviewAllowed,
    );
    if (!mounted) return;
    if (!ref.read(authSessionProvider).isLoggedIn && !allowed) {
      setState(() {
        _loading = false;
        _allowed = false;
        _error = 'login';
      });
      return;
    }
    setState(() {
      _allowed = allowed;
      _loading = false;
      _error = allowed ? null : 'paywall';
    });
    if (!allowed) {
      await showModulePaywall(context, moduleCode: widget.moduleCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_allowed) return widget.child;
    final String title =
        widget.title ?? kModuleTitlesZh[widget.moduleCode] ?? widget.moduleCode;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                _error == 'login'
                    ? '登录后可查看模块权益'
                    : '免费体验已用完',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error == 'login'
                    ? '登录后可永久免费体验约 $kModuleFreePreviewCount 份入门内容，或开通月卡 / 年卡。'
                    : '「$title」始终保留约 $kModuleFreePreviewCount 份永久免费入门内容；'
                        '继续学习请开通月卡或年卡。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    showModulePaywall(context, moduleCode: widget.moduleCode),
                child: const Text('开通月卡 / 年卡'),
              ),
              TextButton(onPressed: _check, child: const Text('刷新权益')),
            ],
          ),
        ),
      ),
    );
  }
}
