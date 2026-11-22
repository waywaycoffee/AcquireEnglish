import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/bottom_nav_scroll_hint.dart';
import 'navigation_destination.dart';

/// Horizontally swipeable bottom navigation.
///
/// Fixed viewport shows [AppNavDestination.bottomBarVisibleCount] tabs;
/// swipe left/right for the rest. Lives in [Scaffold.bottomNavigationBar],
/// so horizontal drags are hit-tested on this bar only and do not enter the
/// page body's gesture arena (PageView / TabBarView stay independent).
class FloatingBottomNav extends StatefulWidget {
  const FloatingBottomNav({
    required this.current,
    super.key,
    this.forceShowScrollHint,
    this.onScrollHintDismissed,
  });

  final AppNavDestination current;

  /// When non-null, overrides Hive-backed first-run hint visibility (tests).
  final bool? forceShowScrollHint;

  /// Optional hook after the one-time tip is dismissed (tests / analytics).
  final VoidCallback? onScrollHintDismissed;

  @override
  State<FloatingBottomNav> createState() => FloatingBottomNavState();
}

@visibleForTesting
class FloatingBottomNavState extends State<FloatingBottomNav> {
  final ScrollController _scrollController = ScrollController();
  bool _showHint = false;
  double _scrollProgress = 0;

  /// Destinations + trailing 「更多」 action index.
  static List<AppNavDestination> get barDestinations =>
      AppNavDestination.bottomBarDestinations;

  static int get _moreIndex => barDestinations.length;

  static int get itemCount => barDestinations.length + 1;

  @override
  void initState() {
    super.initState();
    _showHint =
        widget.forceShowScrollHint ?? !readBottomNavScrollHintSeen();
    _scrollController.addListener(_onScroll);
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
    if (oldWidget.forceShowScrollHint != widget.forceShowScrollHint &&
        widget.forceShowScrollHint != null) {
      _showHint = widget.forceShowScrollHint!;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double max = _scrollController.position.maxScrollExtent;
    final double next = max <= 0
        ? 0
        : (_scrollController.offset / max).clamp(0.0, 1.0);
    if ((next - _scrollProgress).abs() > 0.002) {
      setState(() => _scrollProgress = next);
    }
    // First intentional pan teaches discoverability — clear the tip.
    if (_showHint && _scrollController.offset > 8) {
      _dismissHint();
    }
  }

  int _selectedIndex() {
    final int index = barDestinations.indexOf(widget.current);
    if (index >= 0) return index;
    // Secondary pages (成长 / 设置 / …) highlight 「更多」.
    return _moreIndex;
  }

  double _itemWidth(double viewportWidth) =>
      viewportWidth / AppNavDestination.bottomBarVisibleCount;

  void _centerCurrent({required bool animated}) {
    if (!_scrollController.hasClients) return;
    final double viewport = _scrollController.position.viewportDimension;
    if (viewport <= 0) return;
    final double itemWidth = _itemWidth(viewport);
    final int index = _selectedIndex();
    final double target =
        (index * itemWidth) -
        (viewport - itemWidth) / 2;
    final double clamped = target.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if (animated) {
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  Future<void> _dismissHint() async {
    if (!_showHint) return;
    setState(() => _showHint = false);
    await markBottomNavScrollHintSeen();
    widget.onScrollHintDismissed?.call();
  }

  @visibleForTesting
  Future<void> centerCurrentForTest({bool animated = false}) async {
    _centerCurrent(animated: animated);
    if (animated) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  @visibleForTesting
  double get scrollOffsetForTest =>
      _scrollController.hasClients ? _scrollController.offset : 0;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double width = size.width;
    final bool compact = width < 768;
    final List<AppNavDestination> moreDestinations =
        AppNavDestination.moreMenuDestinations;
    final bool moreSelected = !barDestinations.contains(widget.current);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 16,
        compact ? 4 : 8,
        compact ? 10 : 16,
        compact ? 6 : 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_showHint) _ScrollHintBanner(onDismiss: _dismissHint),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 2 : 6,
                        vertical: compact ? 4 : 6,
                      ),
                      child: LayoutBuilder(
                        builder:
                            (BuildContext context, BoxConstraints constraints) {
                          final double viewportWidth = constraints.maxWidth;
                          final double itemWidth = _itemWidth(viewportWidth);
                          return SizedBox(
                            height: compact ? 56 : 62,
                            child: NotificationListener<ScrollNotification>(
                              // Absorb horizontal scroll metrics so ancestors
                              // (nested scrollables) do not react to bar pans.
                              onNotification: (ScrollNotification notification) {
                                return notification.metrics.axis ==
                                    Axis.horizontal;
                              },
                              child: ListView.builder(
                                key: const Key('bottom-nav-scroll'),
                                controller: _scrollController,
                                scrollDirection: Axis.horizontal,
                                primary: false,
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                itemCount: itemCount,
                                itemBuilder: (BuildContext context, int index) {
                                  if (index == _moreIndex) {
                                    return SizedBox(
                                      width: itemWidth,
                                      child: _MoreNavItem(
                                        selected: moreSelected,
                                        destinations: moreDestinations,
                                        onOpened: _dismissHint,
                                      ),
                                    );
                                  }
                                  final AppNavDestination destination =
                                      barDestinations[index];
                                  return SizedBox(
                                    width: itemWidth,
                                    child: _NavItem(
                                      destination: destination,
                                      selected:
                                          destination == widget.current,
                                      onTap: () {
                                        _dismissHint();
                                        context.go(destination.route);
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _ScrollTrack(
                      progress: _scrollProgress,
                      compact: compact,
                    ),
                  ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        key: const Key('bottom-nav-scroll-hint'),
        color: AppDesignTokens.skyLight.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onDismiss,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.swipe_rounded,
                  size: 16,
                  color: AppDesignTokens.primaryBlueDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '左右滑动，查看更多功能',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppDesignTokens.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollTrack extends StatelessWidget {
  const _ScrollTrack({required this.progress, required this.compact});

  final double progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 24,
        0,
        compact ? 18 : 24,
        compact ? 6 : 8,
      ),
      child: SizedBox(
        key: const Key('bottom-nav-scroll-indicator'),
        height: 3,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double trackWidth = constraints.maxWidth;
            final double thumbWidth = (trackWidth /
                    (itemCount /
                        AppNavDestination.bottomBarVisibleCount))
                .clamp(18.0, trackWidth * 0.55);
            final double maxOffset = (trackWidth - thumbWidth).clamp(
              0.0,
              trackWidth,
            );
            return Stack(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppDesignTokens.borderGray.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const SizedBox.expand(),
                ),
                Positioned(
                  left: maxOffset * progress,
                  width: thumbWidth,
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
            );
          },
        ),
      ),
    );
  }

  int get itemCount => FloatingBottomNavState.itemCount;
}

class _MoreNavItem extends StatelessWidget {
  const _MoreNavItem({
    required this.selected,
    required this.destinations,
    required this.onOpened,
  });

  final bool selected;
  final List<AppNavDestination> destinations;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 768;
    return InkWell(
      key: const Key('bottom-nav-more'),
      borderRadius: BorderRadius.circular(compact ? 16 : 20),
      onTap: () {
        onOpened();
        _showMoreMenu(context);
      },
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: compact ? 24 : 32,
                height: compact ? 24 : 32,
                child: selected
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppDesignTokens.onAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.grid_view_rounded,
                          size: compact ? 15 : 19,
                          color: AppDesignTokens.brandGreenDark,
                        ),
                      )
                    : Icon(
                        Icons.grid_view_outlined,
                        size: compact ? 15 : 19,
                        color: AppDesignTokens.textSecondary,
                      ),
              ),
              SizedBox(height: compact ? 1 : 3),
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
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 768;

    return InkWell(
      key: Key('bottom-nav-item-${destination.name}'),
      borderRadius: BorderRadius.circular(compact ? 16 : 20),
      onTap: onTap,
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: compact ? 24 : 32,
                height: compact ? 24 : 32,
                child: selected
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppDesignTokens.onAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          destination.activeIcon,
                          size: compact ? 15 : 19,
                          color: AppDesignTokens.brandGreenDark,
                        ),
                      )
                    : Icon(
                        destination.icon,
                        size: compact ? 15 : 19,
                        color: AppDesignTokens.textSecondary,
                      ),
              ),
              SizedBox(height: compact ? 1 : 3),
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
      ),
    );
  }
}
