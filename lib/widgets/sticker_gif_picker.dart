// Tabbed bottom sheet: Stickers | GIFs
//
// Usage:
//   final result = await StickerGifPicker.show(context);
//   if (result == null) return;
//   if (result is ChatSticker) { _sendSticker(result); }
//   if (result is GiphyGif) { _sendGif(result); }

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/utils/ui_scale.dart';
import '../models/chat_sticker.dart';
import '../services/giphy_service.dart';

class StickerGifPicker extends StatefulWidget {
  const StickerGifPicker({super.key});

  /// Shows the picker and returns either a [ChatSticker], a [GiphyGif], or null.
  static Future<Object?> show(BuildContext context) {
    return showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const StickerGifPicker(),
    );
  }

  @override
  State<StickerGifPicker> createState() => _StickerGifPickerState();
}

class _StickerGifPickerState extends State<StickerGifPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final TextEditingController _searchCtrl = TextEditingController();
  final GiphyService _giphy = GiphyService();

  List<GiphyGif> _gifs = [];
  bool _gifLoading = false;
  String _lastQuery = '';
  Timer? _debounce;
  int _gifLimit = 18;
  bool _didStartInitialLoad = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didStartInitialLoad) return;
    final ui = context.uiScaleData;
    _gifLimit = ui.isCompactPhone ? 12 : 18;
    _didStartInitialLoad = true;
    _searchGifs('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () {
      if (value != _lastQuery) _searchGifs(value);
    });
  }

  Future<void> _searchGifs(String query) async {
    if (_gifLoading) return;
    _lastQuery = query;
    setState(() => _gifLoading = true);
    final results = await _giphy.search(
      query.trim().isEmpty ? 'trending' : query.trim(),
      limit: _gifLimit,
    );
    if (mounted) {
      setState(() {
        _gifs = results;
        _gifLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ui = context.uiScaleData;
    final screenH = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenH * (ui.isCompactPhone ? 0.68 : 0.62),
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            dividerColor: cs.outlineVariant.withValues(alpha: 0.4),
            tabs: const [
              Tab(text: 'Stickers'),
              Tab(text: 'GIFs'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildStickerGrid(cs), _buildGifTab(cs)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerGrid(ColorScheme cs) {
    final ui = context.uiScaleData;
    final crossAxisCount = ui.columns(compactPhone: 3, phone: 4, tablet: 5);
    final spacing = ui.scale(10, min: 8, max: 14);
    final padding = ui.scale(12, min: 10, max: 16);
    final thumbnailSize = ui.scale(60, min: 52, max: 74);

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(padding, spacing, padding, padding),
      itemCount: kDefaultChatStickers.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, i) {
        final sticker = kDefaultChatStickers[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(sticker),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(
                ui.scale(14, min: 12, max: 18),
              ),
            ),
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                ui.scale(12, min: 10, max: 16),
              ),
              child: CachedNetworkImage(
                imageUrl: sticker.imageUrl,
                width: thumbnailSize,
                height: thumbnailSize,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Text(
                  sticker.fallback,
                  style: TextStyle(fontSize: ui.scale(34, min: 28, max: 40)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGifTab(ColorScheme cs) {
    final ui = context.uiScaleData;
    final horizontalPadding = ui.scale(12, min: 10, max: 16);
    final verticalPadding = ui.scale(10, min: 8, max: 14);
    final gifColumns = ui.columns(compactPhone: 2, phone: 2, tablet: 3);
    final gridSpacing = ui.scale(8, min: 6, max: 10);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            verticalPadding,
            horizontalPadding,
            gridSpacing,
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: _searchGifs,
            decoration: InputDecoration(
              hintText: 'Search GIFs...',
              prefixIcon: Icon(
                Icons.search,
                size: ui.scale(20, min: 18, max: 22),
              ),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        size: ui.scale(18, min: 16, max: 20),
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        _searchGifs('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: cs.surfaceContainerHigh,
              contentPadding: EdgeInsets.symmetric(
                horizontal: ui.scale(14, min: 12, max: 18),
                vertical: ui.scale(10, min: 8, max: 12),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  ui.scale(24, min: 20, max: 28),
                ),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _gifLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _gifs.isEmpty
              ? Center(
                  child: Text(
                    _lastQuery.isEmpty
                        ? 'GIF key not configured.\nSee giphy_service.dart.'
                        : 'No GIFs found.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: ui.scale(13, min: 12, max: 15),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    horizontalPadding,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gifColumns,
                    mainAxisSpacing: gridSpacing,
                    crossAxisSpacing: gridSpacing,
                    childAspectRatio: ui.isCompactPhone ? 0.9 : 0.96,
                  ),
                  itemCount: _gifs.length,
                  itemBuilder: (context, i) {
                    final gif = _gifs[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(
                        ui.scale(12, min: 10, max: 16),
                      ),
                      onTap: () => Navigator.of(context).pop(gif),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          ui.scale(12, min: 10, max: 16),
                        ),
                        child: Image.network(
                          gif.previewUrl,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: cs.surfaceContainerHigh,
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: cs.surfaceContainerHigh,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: cs.onSurfaceVariant,
                                  size: 20,
                                ),
                              ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: ui.scale(6, min: 4, max: 8)),
          child: Text(
            'Powered by GIPHY',
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: ui.scale(11, min: 10, max: 13),
            ),
          ),
        ),
      ],
    );
  }
}
