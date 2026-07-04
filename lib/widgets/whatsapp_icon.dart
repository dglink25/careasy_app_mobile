import 'package:flutter/material.dart';

/// Affiche le logo WhatsApp en couleur via CDN avec fallback icône Material.
/// Usage : WhatsAppIcon(size: 24)
class WhatsAppIcon extends StatelessWidget {
  final double size;

  const WhatsAppIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6b/WhatsApp.svg/120px-WhatsApp.svg.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.chat_rounded,
        color: const Color(0xFF25D366),
        size: size,
      ),
    );
  }
}
