import 'package:flutter/material.dart';

/// Lightweight paper-doll preview using colored layers (no external art required).
class AvatarPreview extends StatelessWidget {
  const AvatarPreview({super.key, required this.loadout, this.height = 180});

  final Map<String, String> loadout;
  final double height;

  Color _colorFor(String? sku, Color fallback) {
    if (sku == null || sku.isEmpty) return fallback;
    final int hash = sku.codeUnits.fold<int>(0, (int a, int b) => a + b * 17);
    final List<Color> palette = <Color>[
      const Color(0xFF5B8C5A),
      const Color(0xFF3D7EA6),
      const Color(0xFFC47B3A),
      const Color(0xFF8E5AA8),
      const Color(0xFFD4A017),
      const Color(0xFF4A6FA5),
      const Color(0xFFB85C38),
      const Color(0xFF2F6F5E),
    ];
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final String? base = loadout['body'] ?? 'body.cartoon1';
    if (base != null && RegExp(r'^body\.cartoon[1-6]$').hasMatch(base)) {
      return SizedBox(
        height: height,
        width: height * .72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/img/avatar_cartoon_${base.substring(base.length - 1)}.png',
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    final String? bg = loadout['bg'];
    final String? hair = loadout['hair'];
    final String? top = loadout['top'];
    final String? bottom = loadout['bottom'];
    final String? accessory = loadout['accessory'];

    return SizedBox(
      height: height,
      width: height * 0.72,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    _colorFor(bg, const Color(0xFFE8F0E6)),
                    Colors.white,
                  ],
                ),
              ),
            ),
          ),
          // Legs / bottom
          Positioned(
            bottom: height * 0.08,
            child: Container(
              width: height * 0.28,
              height: height * 0.28,
              decoration: BoxDecoration(
                color: _colorFor(bottom, const Color(0xFF4A5568)),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          // Torso / top
          Positioned(
            bottom: height * 0.28,
            child: Container(
              width: height * 0.34,
              height: height * 0.28,
              decoration: BoxDecoration(
                color: _colorFor(top, const Color(0xFF3D7EA6)),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Head / body base
          Positioned(
            bottom: height * 0.48,
            child: Container(
              width: height * 0.26,
              height: height * 0.26,
              decoration: BoxDecoration(
                color: const Color(0xFFF2C9A0),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
              ),
            ),
          ),
          // Hair
          if (hair != null)
            Positioned(
              bottom: height * 0.62,
              child: Container(
                width: height * 0.30,
                height: height * 0.14,
                decoration: BoxDecoration(
                  color: _colorFor(hair, const Color(0xFF3B2F2F)),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(40),
                    bottom: Radius.circular(8),
                  ),
                ),
              ),
            ),
          // Accessory badge
          if (accessory != null)
            Positioned(
              right: 8,
              bottom: height * 0.42,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: _colorFor(accessory, const Color(0xFFD4A017)),
                child: const Icon(Icons.star, size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
