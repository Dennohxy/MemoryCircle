import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Displays an image that requires an Authorization header by fetching the
/// bytes through the API client and rendering with `Image.memory`.
class AuthedImage extends StatefulWidget {
  const AuthedImage({
    super.key,
    required this.api,
    required this.path,
    this.fit = BoxFit.cover,
  });

  final ApiClient api;
  final String path;
  final BoxFit fit;

  @override
  State<AuthedImage> createState() => _AuthedImageState();
}

class _AuthedImageState extends State<AuthedImage> {
  late Future<Uint8List> _future = widget.api.imageBytes(widget.path);

  @override
  void didUpdateWidget(AuthedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _future = widget.api.imageBytes(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path.isEmpty) return const _ImageFallback();
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _ImageFallback();
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0xFFEFE7D7),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          gaplessPlayback: true,
        );
      },
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFEFE7D7),
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Color(0xFF6E6857),
        ),
      ),
    );
  }
}
