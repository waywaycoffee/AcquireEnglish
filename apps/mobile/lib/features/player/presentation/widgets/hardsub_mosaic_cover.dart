import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Normalized vertical band used to cover burned-in hardsubs.
class HardsubMosaicBand {
  const HardsubMosaicBand({
    this.bottomFraction = 0.0,
    this.heightFraction = 0.22,
  });

  /// Distance from the bottom of the video, as a fraction of height (0–0.7).
  final double bottomFraction;

  /// Band height as a fraction of video height (0.08–0.55).
  final double heightFraction;

  HardsubMosaicBand copyWith({
    double? bottomFraction,
    double? heightFraction,
  }) =>
      HardsubMosaicBand(
        bottomFraction: bottomFraction ?? this.bottomFraction,
        heightFraction: heightFraction ?? this.heightFraction,
      );

  HardsubMosaicBand clamped() {
    final double height = heightFraction.clamp(0.08, 0.55);
    final double bottom = bottomFraction.clamp(0.0, 0.70);
    final double maxBottom = math.max(0.0, 1.0 - height);
    return HardsubMosaicBand(
      bottomFraction: bottom.clamp(0.0, maxBottom),
      heightFraction: height,
    );
  }
}

/// Draggable / resizable mosaic strip that covers hardsubs on the video surface.
class HardsubMosaicCover extends StatefulWidget {
  const HardsubMosaicCover({
    required this.enabled,
    this.band = const HardsubMosaicBand(),
    this.onBandChanged,
    this.onDismiss,
    super.key,
  });

  final bool enabled;
  final HardsubMosaicBand band;
  final ValueChanged<HardsubMosaicBand>? onBandChanged;
  final VoidCallback? onDismiss;

  @override
  State<HardsubMosaicCover> createState() => _HardsubMosaicCoverState();
}

class _HardsubMosaicCoverState extends State<HardsubMosaicCover> {
  HardsubMosaicBand _band = const HardsubMosaicBand();
  double? _dragStartY;
  double? _dragStartBottom;
  double? _resizeStartY;
  double? _resizeStartHeight;
  double? _resizeStartBottom;

  @override
  void initState() {
    super.initState();
    _band = widget.band.clamped();
  }

  @override
  void didUpdateWidget(covariant HardsubMosaicCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.band.bottomFraction != widget.band.bottomFraction ||
        oldWidget.band.heightFraction != widget.band.heightFraction) {
      _band = widget.band.clamped();
    }
  }

  void _emit(HardsubMosaicBand next) {
    final HardsubMosaicBand clamped = next.clamped();
    setState(() => _band = clamped);
    widget.onBandChanged?.call(clamped);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double height = constraints.maxHeight;
        final double width = constraints.maxWidth;
        if (height <= 0 || width <= 0) {
          return const SizedBox.shrink();
        }
        final double bandHeight = height * _band.heightFraction;
        final double bottom = height * _band.bottomFraction;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom,
              height: bandHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (DragStartDetails details) {
                  _dragStartY = details.globalPosition.dy;
                  _dragStartBottom = _band.bottomFraction;
                },
                onVerticalDragUpdate: (DragUpdateDetails details) {
                  if (_dragStartY == null || _dragStartBottom == null) {
                    return;
                  }
                  final double deltaY = details.globalPosition.dy - _dragStartY!;
                  // Drag down → move cover toward bottom (larger bottom inset).
                  final double nextBottom =
                      _dragStartBottom! + (deltaY / height);
                  _emit(_band.copyWith(bottomFraction: nextBottom));
                },
                onVerticalDragEnd: (_) {
                  _dragStartY = null;
                  _dragStartBottom = null;
                },
                onVerticalDragCancel: () {
                  _dragStartY = null;
                  _dragStartBottom = null;
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const CustomPaint(
                      painter: _MosaicPainter(),
                      child: SizedBox.expand(),
                    ),
                    // Top resize handle — pull up/down to change cover height.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 28,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (DragStartDetails details) {
                          _resizeStartY = details.globalPosition.dy;
                          _resizeStartHeight = _band.heightFraction;
                          _resizeStartBottom = _band.bottomFraction;
                        },
                        onVerticalDragUpdate: (DragUpdateDetails details) {
                          if (_resizeStartY == null ||
                              _resizeStartHeight == null ||
                              _resizeStartBottom == null) {
                            return;
                          }
                          final double deltaY =
                              details.globalPosition.dy - _resizeStartY!;
                          // Drag handle up → taller cover (top grows upward).
                          final double nextHeight =
                              _resizeStartHeight! - (deltaY / height);
                          _emit(
                            HardsubMosaicBand(
                              bottomFraction: _resizeStartBottom!,
                              heightFraction: nextHeight,
                            ),
                          );
                        },
                        onVerticalDragEnd: (_) {
                          _resizeStartY = null;
                          _resizeStartHeight = null;
                          _resizeStartBottom = null;
                        },
                        onVerticalDragCancel: () {
                          _resizeStartY = null;
                          _resizeStartHeight = null;
                          _resizeStartBottom = null;
                        },
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 52,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.onDismiss != null)
                      Positioned(
                        top: 2,
                        right: 4,
                        child: IconButton(
                          tooltip: '收起遮挡',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: widget.onDismiss,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      bottom: 6,
                      child: Text(
                        '拖动手柄调整遮挡 · 上下拖动移动',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          shadows: const <Shadow>[
                            Shadow(color: Color(0xAA000000), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MosaicPainter extends CustomPainter {
  const _MosaicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 10;
    final int cols = (size.width / cell).ceil() + 1;
    final int rows = (size.height / cell).ceil() + 1;
    final Paint paint = Paint()..style = PaintingStyle.fill;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final int hash = (row * 73856093) ^ (col * 19349663);
        final int shade = 18 + (hash.abs() % 42);
        paint.color = Color.fromARGB(255, shade, shade + 2, shade + 6);
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell + 0.6, cell + 0.6),
          paint,
        );
      }
    }
    // Soft vignette so the mosaic reads as a cover, not a screenshot tile.
    final Paint fog = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        <Color>[
          const Color(0x33000000),
          const Color(0x66000000),
          const Color(0x99000000),
        ],
        const <double>[0, 0.45, 1],
      );
    canvas.drawRect(Offset.zero & size, fog);
  }

  @override
  bool shouldRepaint(covariant _MosaicPainter oldDelegate) => false;
}
