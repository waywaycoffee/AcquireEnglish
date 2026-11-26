import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/presentation/media/cover_image.dart';
import '../data/reading_cover_cache.dart';

/// Stable title-based cover for built-in and imported books.
/// When [coverUrl] is set (ECS Open Library cache), download once then paint
/// from Documents/reading_covers; fall back to cloth if the image fails.
class ReadingBookCover extends StatelessWidget {
  const ReadingBookCover({
    required this.title,
    this.level = '',
    this.subtitle = '',
    this.standing = false,
    this.paletteIndex,
    this.coverUrl = '',
    super.key,
  });

  final String title;
  final String level;

  /// Shelf position; cycles [palette] so neighbours differ. Falls back to a
  /// title hash.
  final int? paletteIndex;

  /// Small line under the title on shelf hardcovers.
  final String subtitle;

  /// When true, render the cloth hardcover standing on a shelf.
  final bool standing;

  /// Optional ECS-hosted classic cover (`/media/reading/covers/...`).
  final String coverUrl;

  /// Cloth colors from the reference shelf (green, rust, navy, mustard,
  /// burgundy, plum, then extras).
  static const List<Color> palette = <Color>[
    Color(0xFF2E4634),
    Color(0xFFA4553A),
    Color(0xFF1F3557),
    Color(0xFFCFA03C),
    Color(0xFF5E2430),
    Color(0xFF4E2228),
    Color(0xFF1F4F55),
    Color(0xFF55602E),
    Color(0xFF3A4A63),
    Color(0xFF8A3B2C),
  ];

  static int seedOf(String title) =>
      title.runes.fold<int>(0, (int value, int rune) => value + rune);

  @override
  Widget build(BuildContext context) {
    final int seed = seedOf(title);
    final Color color = palette[(paletteIndex ?? seed) % palette.length];
    final String url = coverUrl.trim();

    if (standing) {
      final Widget cloth = _ClothHardcover(
        title: title,
        subtitle: subtitle,
        color: color,
        glyph: _glyphFor(title, seed),
      );
      if (url.isEmpty) return cloth;
      return _RemoteJacket(url: url, fallback: cloth);
    }

    final bool lightInk = color.computeLuminance() > 0.55;
    final Color ink = lightInk ? const Color(0xFF3A2A18) : Colors.white;
    final Color muted = lightInk
        ? const Color(0xFF3A2A18).withValues(alpha: 0.7)
        : Colors.white70;

    return AspectRatio(
      aspectRatio: 0.68,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 8,
              offset: Offset(3, 4),
            ),
          ],
          gradient: LinearGradient(
            colors: <Color>[
              Color.lerp(color, Colors.black, 0.18)!,
              color,
              Color.lerp(color, Colors.white, 0.06)!,
            ],
            stops: const <double>[0, 0.08, 1],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(6, 0, 0, 0),
          padding: const EdgeInsets.fromLTRB(10, 12, 8, 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                level.isEmpty ? 'ENGLISH' : level,
                style: TextStyle(color: muted, fontSize: 9, letterSpacing: 0.4),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontFamily: 'serif',
                      fontSize: 15,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Divider(color: muted.withValues(alpha: 0.5), height: 8),
              Text(
                'ACQUIRE ENGLISH',
                style: TextStyle(color: muted, fontSize: 7, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _glyphFor(String title, int seed) {
    final String t = title.toLowerCase();
    if (t.contains('key') || t.contains('detective') || t.contains('mystery')) {
      return Icons.vpn_key_outlined;
    }
    if (t.contains('garden') || t.contains('flower') || t.contains('rose')) {
      return Icons.local_florist_outlined;
    }
    if (t.contains('wizard') || t.contains('castle') || t.contains('city') ||
        t.contains('oz')) {
      return Icons.castle_outlined;
    }
    if (t.contains('fable') || t.contains('animal') || t.contains('cat') ||
        t.contains('dog') || t.contains('fox')) {
      return Icons.pets_outlined;
    }
    if (t.contains('stor') || t.contains('letter') || t.contains('poem') ||
        t.contains('essay')) {
      return Icons.history_edu_outlined;
    }
    if (t.contains('walk') || t.contains('morning') || t.contains('tree') ||
        t.contains('leaf') || t.contains('nature')) {
      return Icons.eco_outlined;
    }
    if (t.contains('night') || t.contains('moon') || t.contains('star')) {
      return Icons.nightlight_outlined;
    }
    if (t.contains('sea') || t.contains('lake') || t.contains('island') ||
        t.contains('ship')) {
      return Icons.sailing_outlined;
    }
    return _glyphs[seed % _glyphs.length];
  }
}

const List<IconData> _glyphs = <IconData>[
  Icons.eco_outlined,
  Icons.vpn_key_outlined,
  Icons.castle_outlined,
  Icons.local_florist_outlined,
  Icons.history_edu_outlined,
  Icons.pets_outlined,
];

/// Foil gradient for gold stamping on dark cloth.
const List<Color> _foil = <Color>[
  Color(0xFFF4DE98),
  Color(0xFFC99A45),
  Color(0xFFEDCF82),
  Color(0xFFB28636),
];

const Color _darkStamp = Color(0xFF3A2410);
const String _serif = 'serif';
const List<String> _serifFallback = <String>[
  'Noto Serif',
  'Georgia',
  'Noto Serif CJK SC',
  'Source Han Serif SC',
];

class _RemoteJacket extends StatefulWidget {
  const _RemoteJacket({required this.url, required this.fallback});

  final String url;
  final Widget fallback;

  @override
  State<_RemoteJacket> createState() => _RemoteJacketState();
}

class _RemoteJacketState extends State<_RemoteJacket> {
  static const BorderRadius _radius = BorderRadius.only(
    topLeft: Radius.circular(2),
    bottomLeft: Radius.circular(2),
    topRight: Radius.circular(4),
    bottomRight: Radius.circular(4),
  );

  String? _localPath;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _localPath = cachedReadingCoverPathSync(widget.url);
    if (_localPath == null) {
      unawaited(_cache());
    }
  }

  @override
  void didUpdateWidget(covariant _RemoteJacket oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _failed = false;
      _localPath = cachedReadingCoverPathSync(widget.url);
      if (_localPath == null) {
        unawaited(_cache());
      }
    }
  }

  Future<void> _cache() async {
    final String? path = await ensureReadingCoverCached(widget.url);
    if (!mounted) {
      return;
    }
    if (path != null && path.isNotEmpty) {
      setState(() => _localPath = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String paint = (_localPath != null && _localPath!.isNotEmpty)
        ? _localPath!
        : resolveReadingCoverRemoteUrl(widget.url);
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: _radius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 14,
            spreadRadius: -1,
            offset: Offset(9, -2),
          ),
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 3,
            offset: Offset(1.5, 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: _failed || paint.isEmpty
            ? widget.fallback
            : CoverImage(
                path: paint,
                fit: BoxFit.cover,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? st) {
                  if (!_failed) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _failed = true);
                      }
                    });
                  }
                  return widget.fallback;
                },
              ),
      ),
    );
  }
}

/// Front-facing cloth hardcover: hinge strip with vertical spine title on the
/// left, foil-stamped title / subtitle / emblem / imprint, and a deep cast
/// shadow onto the back panel.
class _ClothHardcover extends StatelessWidget {
  const _ClothHardcover({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.glyph,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData glyph;

  static const BorderRadius _radius = BorderRadius.only(
    topLeft: Radius.circular(2),
    bottomLeft: Radius.circular(2),
    topRight: Radius.circular(4),
    bottomRight: Radius.circular(4),
  );

  @override
  Widget build(BuildContext context) {
    final bool lightCloth = color.computeLuminance() > 0.3;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double w =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 100;
        final double h =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 142;
        final double hinge = (w * 0.115).clamp(8.0, 18.0);

        Widget stamp(Widget child) => lightCloth
            ? child
            : ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (Rect r) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _foil,
                  stops: <double>[0, 0.38, 0.62, 1],
                ).createShader(r),
                child: child,
              );
        final Color ink = lightCloth ? _darkStamp : Colors.white;

        return DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: _radius,
            boxShadow: <BoxShadow>[
              // Cast onto the back panel, falling to the right.
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 14,
                spreadRadius: -1,
                offset: Offset(9, -2),
              ),
              // Contact with the plank.
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 3,
                offset: Offset(1.5, 1.5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: _radius,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const _ClothWeave(),
                // Cloth color modulated by the weave texture.
                DecoratedBox(
                  decoration: BoxDecoration(
                    backgroundBlendMode: BlendMode.overlay,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color.lerp(color, Colors.white, 0.07)!,
                        color,
                        Color.lerp(color, Colors.black, 0.12)!,
                      ],
                    ),
                  ),
                ),
                // Hinge strip (spine wrap) — slightly raised and lighter.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: hinge,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          Color.lerp(color, Colors.black, 0.22)!,
                          Color.lerp(color, Colors.white, 0.08)!,
                          Color.lerp(color, Colors.white, 0.03)!,
                        ],
                        stops: const <double>[0, 0.35, 1],
                      ),
                    ),
                  ),
                ),
                // Hinge groove: dark crease + soft lit lip.
                Positioned(
                  left: hinge,
                  top: 0,
                  bottom: 0,
                  width: 1.2,
                  child: const ColoredBox(color: Color(0x73000000)),
                ),
                Positioned(
                  left: hinge + 1.2,
                  top: 0,
                  bottom: 0,
                  width: 1.6,
                  child: const ColoredBox(color: Color(0x1FFFFFFF)),
                ),
                // Spine bands.
                for (final double y in <double>[h * 0.055, h * 0.075, h * 0.925, h * 0.945])
                  Positioned(
                    left: hinge * 0.18,
                    width: hinge * 0.64,
                    top: y,
                    height: 0.9,
                    child: stamp(ColoredBox(color: ink.withValues(alpha: 0.85))),
                  ),
                // Spine title, reading top to bottom.
                Positioned(
                  left: 0,
                  width: hinge,
                  top: h * 0.11,
                  bottom: h * 0.11,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Center(
                      child: stamp(
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink.withValues(alpha: 0.9),
                            fontFamily: _serif,
                            fontFamilyFallback: _serifFallback,
                            fontSize: hinge * 0.52,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Lighting: top-left sheen, bottom-right falloff, board edges.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0x14FFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x00000000),
                        Color(0x2E000000),
                      ],
                      stops: <double>[0, 0.35, 0.6, 1],
                    ),
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 1,
                  child: ColoredBox(color: Color(0x24FFFFFF)),
                ),
                const Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[Color(0x00000000), Color(0x40000000)],
                      ),
                    ),
                  ),
                ),
                // Front board stamping.
                Positioned(
                  left: hinge + 4,
                  right: w * 0.05,
                  top: h * 0.09,
                  bottom: h * 0.06,
                  child: Column(
                    children: <Widget>[
                      stamp(
                        Text(
                          title,
                          maxLines: 3,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontFamily: _serif,
                            fontFamilyFallback: _serifFallback,
                            fontSize: w * 0.118,
                            height: 1.12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...<Widget>[
                        SizedBox(height: h * 0.025),
                        stamp(
                          Text(
                            subtitle,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink.withValues(alpha: 0.92),
                              fontFamily: _serif,
                              fontFamilyFallback: _serifFallback,
                              fontSize: w * 0.068,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                      Expanded(
                        child: Center(
                          child: stamp(
                            Icon(
                              glyph,
                              size: w * 0.34,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                      stamp(
                        Text(
                          'ACQUIRE ENGLISH',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: ink.withValues(alpha: 0.95),
                            fontSize: w * 0.056,
                            letterSpacing: w * 0.004,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClothWeave extends StatelessWidget {
  const _ClothWeave();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/img/bookshelf/bookcloth.png',
      repeat: ImageRepeat.repeat,
      scale: 2,
      fit: BoxFit.none,
      alignment: Alignment.topLeft,
      errorBuilder: (BuildContext context, Object error, StackTrace? st) =>
          const ColoredBox(color: Color(0xFF808080)),
    );
  }
}
