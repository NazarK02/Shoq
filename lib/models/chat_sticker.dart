class ChatSticker {
  final String id;
  final String pack;
  final String label;
  final String fallback;
  final String imageUrl;

  const ChatSticker({
    required this.id,
    required this.pack,
    required this.label,
    required this.fallback,
    required this.imageUrl,
  });
}

const List<ChatSticker> kDefaultChatStickers = [
  ChatSticker(
    id: 'wave',
    pack: 'Default',
    label: 'Wave',
    fallback: '\u{1F44B}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f44b.png',
  ),
  ChatSticker(
    id: 'cool',
    pack: 'Default',
    label: 'Cool',
    fallback: '\u{1F60E}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f60e.png',
  ),
  ChatSticker(
    id: 'party',
    pack: 'Default',
    label: 'Party',
    fallback: '\u{1F389}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f389.png',
  ),
  ChatSticker(
    id: 'fire',
    pack: 'Default',
    label: 'Fire',
    fallback: '\u{1F525}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f525.png',
  ),
  ChatSticker(
    id: 'love',
    pack: 'Default',
    label: 'Love',
    fallback: '\u{1F970}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f970.png',
  ),
  ChatSticker(
    id: 'laugh',
    pack: 'Default',
    label: 'Laugh',
    fallback: '\u{1F602}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f602.png',
  ),
  ChatSticker(
    id: 'rofl',
    pack: 'Default',
    label: 'ROFL',
    fallback: '\u{1F923}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f923.png',
  ),
  ChatSticker(
    id: 'sad',
    pack: 'Default',
    label: 'Sad',
    fallback: '\u{1F62D}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f62d.png',
  ),
  ChatSticker(
    id: 'hearteyes',
    pack: 'Default',
    label: 'Heart Eyes',
    fallback: '\u{1F60D}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f60d.png',
  ),
  ChatSticker(
    id: 'thumbsup',
    pack: 'Default',
    label: 'Thumbs Up',
    fallback: '\u{1F44D}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f44d.png',
  ),
  ChatSticker(
    id: 'hundred',
    pack: 'Default',
    label: '100',
    fallback: '\u{1F4AF}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4af.png',
  ),
  ChatSticker(
    id: 'rocket',
    pack: 'Default',
    label: 'Rocket',
    fallback: '\u{1F680}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f680.png',
  ),
  ChatSticker(
    id: 'star',
    pack: 'Default',
    label: 'Star',
    fallback: '\u{1F31F}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f31f.png',
  ),
  ChatSticker(
    id: 'unicorn',
    pack: 'Default',
    label: 'Unicorn',
    fallback: '\u{1F984}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f984.png',
  ),
  ChatSticker(
    id: 'cat',
    pack: 'Default',
    label: 'Cat',
    fallback: '\u{1F431}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f431.png',
  ),
  ChatSticker(
    id: 'dog',
    pack: 'Default',
    label: 'Dog',
    fallback: '\u{1F436}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f436.png',
  ),
  ChatSticker(
    id: 'pizza',
    pack: 'Default',
    label: 'Pizza',
    fallback: '\u{1F355}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f355.png',
  ),
  ChatSticker(
    id: 'coffee',
    pack: 'Default',
    label: 'Coffee',
    fallback: '\u{2615}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2615.png',
  ),
  ChatSticker(
    id: 'soccer',
    pack: 'Default',
    label: 'Soccer',
    fallback: '\u{26BD}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/26bd.png',
  ),
  ChatSticker(
    id: 'game',
    pack: 'Default',
    label: 'Game',
    fallback: '\u{1F3AE}',
    imageUrl:
        'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3ae.png',
  ),
];

ChatSticker? chatStickerById(String id) {
  final normalized = id.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final sticker in kDefaultChatStickers) {
    if (sticker.id == normalized) {
      return sticker;
    }
  }
  return null;
}
