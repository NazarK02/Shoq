import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/link_preview_service.dart';

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

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
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
      // Ignore open failures in message bubbles.
    }
  }

  List<InlineSpan> _buildLinkifiedSpans(String text) {
    _disposeRecognizers();
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'((?:https?:\/\/|www\.)[^\s<>()]+)',
      caseSensitive: false,
    );
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final matched = _sanitizeMatchedUrl(match.group(0)?.trim() ?? '');
      final normalized = _previewService.normalizeUri(matched);
      if (normalized == null) {
        spans.add(TextSpan(text: matched));
      } else {
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            _openLink(normalized.toString());
          };
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: matched,
            style:
                widget.linkStyle ??
                widget.style.copyWith(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w600,
                ),
            recognizer: recognizer,
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text));
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
    final links = _previewService.extractLinks(widget.text, maxCount: 4);
    final previewLinks = widget.showPreviews
        ? links.take(widget.maxPreviewCards).toList()
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: widget.style,
            children: _buildLinkifiedSpans(widget.text),
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
                                  errorWidget: (_, __, ___) => _imageFallback(),
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
