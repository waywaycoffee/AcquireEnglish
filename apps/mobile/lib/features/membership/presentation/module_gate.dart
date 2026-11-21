import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/module_access.dart';

/// Wraps a learning entry; shows a graceful paywall when the module is locked.
class ModuleGate extends ConsumerStatefulWidget {
  const ModuleGate({
    super.key,
    required this.moduleCode,
    required this.child,
    this.title,
  });

  final String moduleCode;
  final Widget child;
  final String? title;

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

  Future<void> _check() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _allowed = false;
        _error = 'login';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> assets =
          await ref.read(acquireApiClientProvider).getAssets();
      bool allowed = assetsUnlockModule(assets, widget.moduleCode);
      if (!allowed) {
        try {
          final Map<String, dynamic> access = await ref
              .read(acquireApiClientProvider)
              .commerceModuleAccess(widget.moduleCode);
          allowed = access['allowed'] == true;
        } catch (_) {
          // Assets snapshot is enough when access endpoint is older.
        }
      }
      if (!mounted) return;
      setState(() {
        _allowed = allowed;
        _loading = false;
      });
      if (!allowed) {
        await showModulePaywall(context, moduleCode: widget.moduleCode);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _allowed = false;
        _error = 'network';
      });
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
                    : '尚未开通「$title」',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                '体验期 / Pro 或单独购买本板块后即可进入。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    showModulePaywall(context, moduleCode: widget.moduleCode),
                child: const Text('查看开通方式'),
              ),
              TextButton(onPressed: _check, child: const Text('刷新权益')),
            ],
          ),
        ),
      ),
    );
  }
}
