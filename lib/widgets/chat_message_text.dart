import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/image_viewer_screen.dart';
import '../services/link_preview_service.dart';

const List<String> _emojiFontFallback = <String>[
  'Segoe UI Emoji',
  'Noto Color Emoji',
  'Apple Color Emoji',
];

TextStyle _withEmojiFallback(TextStyle style) {
  final fallback = <String>{
    ...(style.fontFamilyFallback ?? const <String>[]),
    ..._emojiFontFallback,
  }.toList();
  return style.copyWith(fontFamilyFallback: fallback);
}

String _insertSoftWrapBreaks(String text, {int chunkSize = 24}) {
  if (text.isEmpty) return text;
  final pattern = RegExp(r'\S{32,}');
  return text.replaceAllMapped(pattern, (match) {
    final token = match.group(0) ?? '';
    if (token.length <= chunkSize) return token;
    final chunks = <String>[];
    for (var i = 0; i < token.length; i += chunkSize) {
      final end = (i + chunkSize < token.length)
          ? i + chunkSize
          : token.length;
      chunks.add(token.substring(i, end));
    }
    return chunks.join('\u200B');
  });
}

class ChatMessageText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;
  final bool showPreviews;
  final int maxPreviewCards;
  final Color previewBackgroundColor;
  final Color previewBorderColor;
  final Color previewTitleColor;
  final Color previewMetaColor;

  const ChatMessageText({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
    this.showPreviews = true,
    this.maxPreviewCards = 2,
    required this.previewBackgroundColor,
    required this.previewBorderColor,
    required this.previewTitleColor,
    required this.previewMetaColor,
  });

  @override
  State<ChatMessageText> createState() => _ChatMessageTextState();
}

class _ChatMessageTextState extends State<ChatMessageText> {
  final LinkPreviewService _previewService = LinkPreviewService();
  final List<TapGestureRecognizer> _recognizers = [];
  String _lastPrecacheSignature = '';

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMediaPrecache();
  }

  @override
  void didUpdateWidget(covariant ChatMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _scheduleMediaPrecache();
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _scheduleMediaPrecache() {
    final standaloneMediaLink = _resolveStandaloneMediaLink(
      _previewService.extractLinks(widget.text, maxCount: 4),
    );
    if (standaloneMediaLink == null) return;

    final signature = standaloneMediaLink;
    if (signature == _lastPrecacheSignature) return;
    _lastPrecacheSignature = signature;

    unawaited(_precacheMedia(standaloneMediaLink));
  }

  Future<void> _precacheMedia(String url) async {
    if (!mounted) return;
    final ImageProvider<Object> provider = _previewService.isLikelyGifUrl(url)
        ? NetworkImage(url) as ImageProvider<Object>
        : CachedNetworkImageProvider(url) as ImageProvider<Object>;
    try {
      await precacheImage(provider, context);
    } catch (_) {
      // Best-effort only. The preview still renders with a fixed frame.
    }
  }

  Future<void> _openLink(String rawUrl) async {
    final uri = _previewService.normalizeUri(rawUrl);
    if (uri == null) return;
    try {
      final openedInApp = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );
      if (!openedInApp) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        // Ignore open failures in message bubbles.
      }
    }
  }

  List<InlineSpan> _buildLinkifiedSpans(
    String text, {
    required TextStyle linkStyle,
  }) {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'((?:https?:\/\/|www\.)[^\s<>()]+)',
      caseSensitive: false,
    );
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: _insertSoftWrapBreaks(text.substring(cursor, match.start)),
          ),
        );
      }
      final matched = _sanitizeMatchedUrl(match.group(0)?.trim() ?? '');
      final normalized = _previewService.normalizeUri(matched);
      final displayMatched = _insertSoftWrapBreaks(matched);
      if (normalized == null) {
        spans.add(TextSpan(text: displayMatched));
      } else {
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            _openLink(normalized.toString());
          };
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: displayMatched,
            style: linkStyle,
            recognizer: recognizer,
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: _insertSoftWrapBreaks(text.substring(cursor))));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: _insertSoftWrapBreaks(text)));
    }
    return spans;
  }

  String _sanitizeMatchedUrl(String value) {
    var result = value.trim();
    while (result.endsWith('.') ||
        result.endsWith(',') ||
        result.endsWith(';') ||
        result.endsWith('!') ||
        result.endsWith('?') ||
        result.endsWith(')')) {
      result = result.substring(0, result.length - 1).trim();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = _withEmojiFallback(widget.style);
    final resolvedLinkStyle = _withEmojiFallback(
      widget.linkStyle ??
          widget.style.copyWith(
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
    );
    final links = _previewService.extractLinks(widget.text, maxCount: 4);
    final standaloneMediaLink = _resolveStandaloneMediaLink(links);
    final previewLinks = widget.showPreviews
        ? links.take(widget.maxPreviewCards).toList()
        : const <String>[];

    if (standaloneMediaLink != null) {
      return _StandaloneMediaLink(
        url: standaloneMediaLink,
        previewService: _previewService,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          softWrap: true,
          textWidthBasis: TextWidthBasis.parent,
          text: TextSpan(
            style: baseStyle,
            children: _buildLinkifiedSpans(
              widget.text,
              linkStyle: resolvedLinkStyle,
            ),
          ),
        ),
        for (final link in previewLinks)
          _LinkPreviewCard(
            rawUrl: link,
            previewService: _previewService,
            backgroundColor: widget.previewBackgroundColor,
            borderColor: widget.previewBorderColor,
            titleColor: widget.previewTitleColor,
            metaColor: widget.previewMetaColor,
            onOpenLink: _openLink,
          ),
      ],
    );
  }

  String? _resolveStandaloneMediaLink(List<String> links) {
    if (links.length != 1) return null;
    final raw = links.first.trim();
    if (raw.isEmpty) return null;
    final normalized = _previewService.normalizeUri(raw);
    if (normalized == null) return null;
    final normalizedText = normalized.toString();
    if (!_previewService.isLikelyImageUrl(normalizedText)) {
      return null;
    }
    final trimmedText = widget.text.trim();
    if (trimmedText == raw || trimmedText == normalizedText) {
      return normalizedText;
    }
    return null;
  }
}

class _StandaloneMediaLink extends StatelessWidget {
  final String url;
  final LinkPreviewService previewService;

  const _StandaloneMediaLink({required this.url, required this.previewService});

  @override
  Widget build(BuildContext context) {
    final isGif = previewService.isLikelyGifUrl(url);
    final fileName = _fileNameFromUrl(url, isGif: isGif);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ImageViewerScreen(imageUrl: url, fileName: fileName),
          ),
        );
      },
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(const SnackBar(content: Text('Media link copied')));
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: double.infinity,
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black12),
              Positioned.fill(
                child: isGif
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) =>
                            _imageError(),
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const SizedBox.shrink(),
                        errorWidget: (context, url, error) => _imageError(),
                      ),
              ),
              if (isGif)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'GIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fileNameFromUrl(String rawUrl, {required bool isGif}) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.pathSegments.isEmpty) {
      return isGif ? 'gif.gif' : 'image.jpg';
    }
    final tail = uri.pathSegments.last.trim();
    if (tail.isEmpty) {
      return isGif ? 'gif.gif' : 'image.jpg';
    }
    return tail;
  }

  Widget _imageError() {
    return Container(
      height: 140,
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image, color: Colors.white70),
    );
  }
}

class _LinkPreviewCard extends StatelessWidget {
  final String rawUrl;
  final LinkPreviewService previewService;
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color metaColor;
  final Future<void> Function(String rawUrl) onOpenLink;

  const _LinkPreviewCard({
    required this.rawUrl,
    required this.previewService,
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.metaColor,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LinkPreviewData?>(
      future: previewService.fetchPreview(rawUrl),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final uri = preview?.uri ?? previewService.normalizeUri(rawUrl);
        if (uri == null) return const SizedBox.shrink();

        final host = (preview?.siteName ?? uri.host).trim();
        final displayHost = host.startsWith('www.') ? host.substring(4) : host;
        final title = (preview?.title ?? displayHost).trim();
        final description = preview?.description?.trim() ?? '';
        final imageUrl = _resolveImageUrl(preview, uri);
        final isGif =
            imageUrl != null && previewService.isLikelyGifUrl(imageUrl);
        final isYouTube = preview?.isYouTube == true;

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onOpenLink(uri.toString()),
            child: Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imageUrl != null)
                    Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 140,
                          child: isGif
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => _imageFallback(),
                                )
                              : CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      _imageFallback(),
                                ),
                        ),
                        if (isYouTube)
                          const Positioned.fill(
                            child: Center(
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.black54,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? uri.toString() : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: metaColor, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          displayHost.isEmpty ? uri.toString() : displayHost,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: metaColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _resolveImageUrl(LinkPreviewData? preview, Uri uri) {
    final previewImage = preview?.imageUrl?.trim();
    if (previewImage != null && previewImage.isNotEmpty) {
      return previewImage;
    }
    if (previewService.isLikelyImageUrl(uri.toString())) {
      return uri.toString();
    }
    return null;
  }

  Widget _imageFallback() {
    return Container(
      color: Colors.black12,
      child: const Center(child: Icon(Icons.link, color: Colors.white70)),
    );
  }
}
