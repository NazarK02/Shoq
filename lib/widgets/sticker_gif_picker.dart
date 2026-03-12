// Tabbed bottom sheet: Stickers | GIFs
//
// Usage:
//   final result = await StickerGifPicker.show(context);
//   if (result == null) return;
//   if (result is ChatSticker) { _sendSticker(result); }
//   if (result is TenorGif) { _sendGif(result); }

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/chat_sticker.dart';
import '../services/tenor_service.dart';

class StickerGifPicker extends StatefulWidget {
  const StickerGifPicker({super.key});

  /// Shows the picker and returns either a [ChatSticker], a [TenorGif], or null.
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
  final TenorService _tenor = TenorService();

  List<TenorGif> _gifs = [];
  bool _gifLoading = false;
  String _lastQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Pre-load trending GIFs when the sheet opens.
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
    final results = await _tenor.search(
      query.trim().isEmpty ? 'trending' : query.trim(),
      limit: 24,
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
    final screenH = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenH * 0.58,
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
              children: [
                _buildStickerGrid(cs),
                _buildGifTab(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerGrid(ColorScheme cs) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: kDefaultChatStickers.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
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
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: sticker.imageUrl,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Text(
                  sticker.fallback,
                  style: const TextStyle(fontSize: 30),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGifTab(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: _searchGifs,
            decoration: InputDecoration(
              hintText: 'Search GIFs...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _searchGifs('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: cs.surfaceContainerHigh,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
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
                            ? 'GIF key not configured.\nSee tenor_service.dart.'
                            : 'No GIFs found.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 1,
                      ),
                      itemCount: _gifs.length,
                      itemBuilder: (context, i) {
                        final gif = _gifs[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.of(context).pop(gif),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              gif.previewUrl,
                              fit: BoxFit.cover,
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
                              errorBuilder: (_, __, ___) => Container(
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
      ],
    );
  }
}
