/// QR code payload format: shoq://user/{uid}
///
/// The payload intentionally contains only the UID so that Firestore
/// profile data (display name, avatar) can be fetched separately.
/// No keys, no tokens, no session data are encoded here.
library qr_utils;

class QrUtils {
  static const _scheme = 'shoq://user/';

  /// Encodes a Firebase UID into a Shoq friend QR payload.
  static String encodeUser(String uid) => '$_scheme$uid';

  /// Decodes a scanned QR string. Returns the UID or null if the
  /// payload is not a valid Shoq user link.
  static String? decodeUser(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(_scheme)) return null;
    final uid = trimmed.substring(_scheme.length);
    if (uid.isEmpty) return null;
    return uid;
  }
}
