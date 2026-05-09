import 'package:flutter/material.dart';

/// SECURELY brand mark — circular, like a standard app icon (not a wide rectangle).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 40,
    this.fit = BoxFit.cover,
  });

  final double size;
  final BoxFit fit;

  static const String assetPath = 'assets/images/app_icon.png';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: fit,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.shield_outlined, size: size * 0.85),
        ),
      ),
    );
  }
}
