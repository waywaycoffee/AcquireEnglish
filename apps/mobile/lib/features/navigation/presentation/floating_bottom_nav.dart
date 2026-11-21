import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import 'navigation_destination.dart';

const String kBottomNavScrollHintKey = 'bottom_nav_scroll_hint_v1';

/// Horizontally scrollable bottom tabs: 5 visible, swipe for the rest + 更多.
class FloatingBottomNav extends StatefulWidget {
  const FloatingBottomNav({required this.current, super.key});

  final AppNavDestination current;

  static const int visibleCount = 5;

  @override
  State<FloatingBottomNav> createState() => _FloatingBottomNavState();
}

class _FloatingBottomNavState extends State<FloatingBottomNav> {
  final ScrollController _controller = ScrollController();
  double _scrollProgress = 0;
  bool _showHint = false;
  bool _hintLoaded = false;

  List<AppNavDestination> get _strip => AppNavDestination.bottomStrip;

  List<AppNavDestination> get _moreDestinations => AppNavDestination.values
      .where(
        (AppNavDestination d) =>
            d.showInNav && !_strip.contains(d) && d != AppNavDestination.importCourse,
      )
      .toList(growable: false);

  bool get _moreSelected => _moreDestinations.contains(widget.current);

  int get _slotCount => _strip.length + 1; // + 更多

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    unawaited(_loadHint());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerCurrent(animated: false);
    });
  }

  @override
  void didUpdateWidget(covariant FloatingBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerCurrent(animated: true);
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHint() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool seen = prefs.getBool(kBottomNavScrollHintKey) ?? false;
    if (!mounted) {
      return;
    }
    setState(() {
      _showHint = !seen;
      _hintLoaded = true;
    });
  }

  Future<void> _dismissHint() async {
    if (!_showHint) {
      return;
    }
    setState(() => _showHint = false);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBottomNavScrollHintKey, true);
  }

  void _onScroll() {
    if (!_controller.hasClients) {
      return;
    }
    final double max = _controller.position.maxScrollExtent;
    final double next = max <= 0 ? 0 : (_controller.offset / max).clamp(0.0, 1.0);
    if ((next - _scrollProgress).abs() > 0.002) {
      setState(() => _scrollProgress = next);
    }
    if (_showHint && _controller.offset > 8) {
      unawaited(_dismissHint());
    }
  }

  void _centerCurrent({required bool animated}) {
    if (!_controller.hasClients) {
      return;
    }
    final double viewport = _controller.position.viewportDimension;
    if (viewport <= 0) {
      return;
    }
    final double itemWidth = viewport / FloatingBottomNav.visibleCount;
    final int index = _moreSelected
        ? _strip.length
        : _strip.indexOf(widget.current).clamp(0, _strip.length - 1);
    final double target =
        (index * itemWidth) - (viewport - itemWidth) / 2;
    final double clamped = target.clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    if (animated) {
      _controller.animateTo(
        clamped,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpTo(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool compact = size.width < 768;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        compact ? 6 : 10,
        compact ? 10 : 16,
        compact ? 8 : 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_hintLoaded && _showHint) ...<Widget>[
            _ScrollHintBanner(onDismiss: _dismissHint),
            const SizedBox(height: 6),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 22 : 28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppDesignTokens.appWhite.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(compact ? 22 : 28),
                  boxShadow: AppDesignTokens.toyCardShadow,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 2 : 6,
                    compact ? 4 : 6,
                    compact ? 2 : 6,
                    compact ? 2 : 4,
                  ),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final double itemWidth =
                          constraints.maxWidth / FloatingBottomNav.visibleCount;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox(
                            height: compact ? 58 : 64,
                            child: NotificationListener<ScrollNotification>(
                              // Keep horizontal drags on the strip; don't bubble
                              // into page-level PageViews / horizontal lists.
                              onNotification: (ScrollNotification notification) {
                                return notification.depth == 0;
                              },
                              child: ListView.builder(
                                key: const Key('bottom-nav-scroll'),
                                controller: _controller,
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                itemCount: _slotCount,
                                itemBuilder: (BuildContext context, int index) {
                                  if (index == _strip.length) {
                                    return SizedBox(
                                      width: itemWidth,
                                      child: _MoreNavItem(
                                        selected: _moreSelected,
                                        destinations: _moreDestinations,
                                      ),
                                    );
                                  }
                                  final AppNavDestination destination =
                                      _strip[index];
                                  return SizedBox(
                                    width: itemWidth,
                                    child: _NavItem(
                                      destination: destination,
                                      selected: destination == widget.current,
                                      onSelected: () {
                                        unawaited(_dismissHint());
                                        context.go(destination.route);
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          _ScrollProgressIndicator(
                            progress: _scrollProgress,
                            compact: compact,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollHintBanner extends StatelessWidget {
  const _ScrollHintBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('bottom-nav-hint'),
        onTap: onDismiss,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: AppDesignTokens.brandGreen.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppDesignTokens.brandGreen.withValues(alpha: 0.35),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.swipe_rounded,
                  size: 18,
                  color: AppDesignTokens.brandGreenDark,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '左右滑动底栏，可看社区、对战、备考等',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.brandGreenDark,
                    ),
                  ),
                ),
                Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppDesignTokens.brandGreenDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollProgressIndicator extends StatelessWidget {
  const _ScrollProgressIndicator({
    required this.progress,
    required this.compact,
  });

  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: compact ? 18 : 28,
        right: compact ? 18 : 28,
        top: compact ? 2 : 4,
        bottom: compact ? 2 : 4,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double track = constraints.maxWidth;
          final double thumb = (track / FloatingBottomNav.visibleCount)
              .clamp(18.0, track * 0.45);
          final double maxLeft = (track - thumb).clamp(0.0, track);
          final double left = maxLeft * progress;
          return SizedBox(
            key: const Key('bottom-nav-indicator'),
            height: 3,
            child: Stack(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppDesignTokens.borderGray.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const SizedBox.expand(),
                ),
                Positioned(
                  left: left,
                  width: thumb,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppDesignTokens.brandGreen.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MoreNavItem extends StatelessWidget {
  const _MoreNavItem({required this.selected, required this.destinations});

  final bool selected;
  final List<AppNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 768;
    return InkWell(
      key: const Key('bottom-nav-more'),
      borderRadius: BorderRadius.circular(compact ? 16 : 20),
      onTap: () => _showMoreMenu(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.brandGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          boxShadow: selected ? AppDesignTokens.toyButtonShadow : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: compact ? 28 : 32,
              height: compact ? 28 : 32,
              child: selected
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppDesignTokens.onAccent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.grid_view_rounded,
                        size: compact ? 17 : 19,
                        color: AppDesignTokens.brandGreenDark,
                      ),
                    )
                  : Icon(
                      Icons.grid_view_outlined,
                      size: compact ? 17 : 19,
                      color: AppDesignTokens.textSecondary,
                    ),
            ),
            SizedBox(height: compact ? 2 : 3),
            Text(
              '更多',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? AppDesignTokens.onAccent
                    : AppDesignTokens.textSecondary,
                fontSize: compact ? 10 : 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '更多功能',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              ...destinations.map(
                (AppNavDestination destination) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(destination.icon),
                  title: Text(destination.label),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go(destination.route);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onSelected,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 768;

    return InkWell(
      key: Key('bottom-nav-${destination.name}'),
      borderRadius: BorderRadius.circular(compact ? 16 : 20),
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.brandGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(compact ? 16 : 20),
          boxShadow: selected ? AppDesignTokens.toyButtonShadow : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: compact ? 28 : 32,
              height: compact ? 28 : 32,
              child: selected
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppDesignTokens.onAccent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        destination.activeIcon,
                        size: compact ? 17 : 19,
                        color: AppDesignTokens.brandGreenDark,
                      ),
                    )
                  : Icon(
                      destination.icon,
                      size: compact ? 17 : 19,
                      color: AppDesignTokens.textSecondary,
                    ),
            ),
            SizedBox(height: compact ? 2 : 3),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? AppDesignTokens.onAccent
                    : AppDesignTokens.textSecondary,
                fontSize: compact ? 10 : 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
