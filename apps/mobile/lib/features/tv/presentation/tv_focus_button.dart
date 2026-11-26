import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';

/// Remote-friendly button: large hit target + visible focus ring for D-pad.
class TvFocusButton extends StatefulWidget {
  const TvFocusButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.autofocus = false,
    this.primary = false,
    this.icon,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool autofocus;
  final bool primary;
  final IconData? icon;
  final FocusNode? focusNode;

  @override
  State<TvFocusButton> createState() => _TvFocusButtonState();
}

class _TvFocusButtonState extends State<TvFocusButton> {
  late final FocusNode _node = widget.focusNode ?? FocusNode(debugLabel: widget.label);
  bool _ownedNode = false;

  @override
  void initState() {
    super.initState();
    _ownedNode = widget.focusNode == null;
    _node.addListener(_onFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    if (_ownedNode) {
      _node.dispose();
    }
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onPressed == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      widget.onPressed!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = _node.hasFocus;
    final bool enabled = widget.onPressed != null;
    final Color fill = widget.primary
        ? AppDesignTokens.brandGreen
        : (focused
            ? AppDesignTokens.brandGreen.withValues(alpha: 0.28)
            : const Color(0xFF1E323B));
    final Color fg = widget.primary
        ? AppDesignTokens.onAccent
        : (focused ? AppDesignTokens.brandGreen : const Color(0xFFECF0F0));

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: focused
            ? Matrix4.diagonal3Values(1.04, 1.04, 1)
            : Matrix4.identity(),
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onPressed,
            onFocusChange: (_) => setState(() {}),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: focused
                      ? AppDesignTokens.brandGreen
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.icon != null) ...<Widget>[
                    Icon(widget.icon, color: fg, size: 22),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: enabled ? fg : fg.withValues(alpha: 0.45),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TvFocusCard extends StatefulWidget {
  const TvFocusCard({
    required this.child,
    required this.onPressed,
    super.key,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  State<TvFocusCard> createState() => _TvFocusCardState();
}

class _TvFocusCardState extends State<TvFocusCard> {
  final FocusNode _node = FocusNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = _node.hasFocus;
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: AnimatedScale(
        scale: focused ? 1.03 : 1,
        duration: const Duration(milliseconds: 160),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: focused
                      ? AppDesignTokens.brandGreen
                      : const Color(0xFF243044),
                  width: focused ? 3 : 1,
                ),
                boxShadow: focused
                    ? <BoxShadow>[
                        BoxShadow(
                          color: AppDesignTokens.brandGreen.withValues(
                            alpha: 0.35,
                          ),
                          blurRadius: 18,
                        ),
                      ]
                    : null,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
