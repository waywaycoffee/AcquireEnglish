import 'package:flutter/material.dart';

import '../../navigation/presentation/app_nav_rail.dart';
import '../../navigation/presentation/navigation_destination.dart';
import 'pad/app_design_tokens.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.body,
    super.key,
    this.header,
    this.currentDestination,
    this.backgroundColor,
    this.useSafeArea = true,
  });

  final Widget body;
  final Widget? header;
  final AppNavDestination? currentDestination;
  final Color? backgroundColor;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final Color canvas = backgroundColor ?? AppDesignTokens.softWhite;
    final Widget column = Column(
      children: <Widget>[
        if (header != null) header!,
        Expanded(child: body),
      ],
    );

    final Widget content = currentDestination == null
        ? Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: column,
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppNavRail(current: currentDestination!),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: column,
                  ),
                ),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: canvas,
      body: useSafeArea ? SafeArea(child: content) : content,
    );
  }
}
