import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/cache_service.dart';

class CachedImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;   // Widget affiché pendant le chargement
  final Widget? errorWidget;   // Widget affiché en cas d'erreur / URL vide
  final BorderRadius? borderRadius;

  const CachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = url == null || url!.trim().isEmpty;

    Widget content;

    if (isEmpty) {
      content = errorWidget ?? _defaultError();
    } else {
      content = CachedNetworkImage(
        imageUrl: url!,
        cacheManager: CacheService.imageCache,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) =>
            placeholder ??
            Container(
              color: Colors.grey[200],
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        errorWidget: (_, __, ___) => errorWidget ?? _defaultError(),
        // Garde les images en mémoire vive pour des transitions fluides
        memCacheWidth: width != null ? (width! * 2).toInt() : null,
        memCacheHeight: height != null ? (height! * 2).toInt() : null,
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }

  Widget _defaultError() => Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 28,
            color: Colors.grey[400],
          ),
        ),
      );
}

/// Variante avec SizedBox de dimensions fixes (pratique pour les listes)
class CachedImageBox extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const CachedImageBox({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CachedImage(
        url: url,
        width: width,
        height: height,
        fit: fit,
        errorWidget: errorWidget,
        borderRadius: borderRadius,
      ),
    );
  }
}