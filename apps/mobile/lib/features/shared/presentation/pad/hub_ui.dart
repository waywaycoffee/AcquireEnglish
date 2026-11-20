import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

/// Soft elevated surface used by Review Hub / Community redesign.
class HubSurface extends StatelessWidget {
  const HubSurface({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppDesignTokens.toyCardShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: body,
      ),
    );
  }
}

class HubPill extends StatelessWidget {
  const HubPill({
    required this.label,
    super.key,
    this.onTap,
    this.selected = false,
    this.background,
    this.foreground,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final Color bg = background ??
        (selected
            ? AppDesignTokens.brandGreen
            : AppDesignTokens.skyLight);
    final Color fg = foreground ??
        (selected
            ? AppDesignTokens.onAccent
            : AppDesignTokens.primaryBlueDark);
    final Widget child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: child,
    );
  }
}

class HubMetricTile extends StatelessWidget {
  const HubMetricTile({
    required this.value,
    required this.label,
    required this.background,
    required this.foreground,
    super.key,
  });

  final String value;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HubPrimaryButton extends StatelessWidget {
  const HubPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon = Icons.play_arrow_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: onPressed == null
              ? const <BoxShadow>[]
              : AppDesignTokens.toyButtonShadow,
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppDesignTokens.brandGreen,
            foregroundColor: AppDesignTokens.onAccent,
            disabledBackgroundColor: AppDesignTokens.softGray,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: Icon(icon),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class HubSectionTitle extends StatelessWidget {
  const HubSectionTitle(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppDesignTokens.primaryBlueDark,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              action!,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}
