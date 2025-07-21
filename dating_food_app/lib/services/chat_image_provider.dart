import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// チャット画像を直接描画するためのImageProvider
class ChatImageProvider extends ImageProvider<ChatImageProvider> {
  final ui.Image image;
  
  const ChatImageProvider(this.image);

  @override
  Future<ChatImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<ChatImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(ChatImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(
        ImageInfo(
          image: image,
          scale: 1.0,
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is ChatImageProvider && other.image == image;
  }

  @override
  int get hashCode => image.hashCode;
} 