# QR Code Friend Adding Integration

This document summarizes the QR code functionality integrated into the Shoq messenger for friend discovery and connection.

## What Was Added

### New Files Created

1. **`lib/core/utils/qr_utils.dart`**
   - Utility class for QR payload encoding/decoding
   - Format: `shoq://user/{uid}`
   - No sensitive data in QR (UID only, public profile data fetched separately)

2. **`lib/widgets/add_friend_sheet.dart`**
   - Modal bottom sheet for adding friends
   - Two methods:
     - Search by UID or email
     - Scan QR code (mobile only)
   - Returns full user data on successful lookup
   - Validates user exists in Firestore

3. **`lib/widgets/my_qr_sheet.dart`**
   - Modal bottom sheet to display own QR code
   - User can share QR as PNG image via system share sheet
   - Shows display name and selectable UID
   - Renders QR at high DPI (3x) for quality sharing

4. **`lib/screens/qr_scanner_screen.dart`**
   - Full-screen camera scanner (mobile only)
   - Uses `mobile_scanner` package
   - Features:
     - Torch toggle
     - Square viewfinder overlay
     - Auto-stops on valid Shoq QR detection
     - Returns only valid payloads
     - Shows error feedback for invalid codes

5. **Updated `lib/screens/friends_list_screen.dart`**
   - Added search bar to filter friends by name/email
   - QR icon in app bar → show own QR (`MyQrSheet`)
   - Add person icon in app bar → add friend (`AddFriendSheet`)
   - Removed old FAB-based add dialog
   - New `_sendFriendRequestFromQr()` method handles resolved users

## Updated Dependencies

Added to `pubspec.yaml`:
```yaml
share_plus: ^10.0.0
```

Existing packages (already in project):
- `qr_flutter: ^4.1.0`
- `mobile_scanner: ^7.1.4`
- `path_provider: ^2.1.4`

## Integration Points (Wire These)

### 1. Friends Screen Usage
The friends list screen now:
- Shows search bar for filtering friends
- Opens `MyQrSheet` when QR icon tapped
- Opens `AddFriendSheet` when add icon tapped
- Calls `_sendFriendRequestFromQr()` when friend is selected

### 2. Friend Request Flow
When a user is resolved (via QR or search):
1. Check if already friends
2. Check for existing pending request
3. Create new friend request in Firestore
4. Send notification to recipient
5. Show confirmation to sender

Current implementation uses `NotificationService().sendFriendRequestNotification()`.

### 3. Optional: Friend Service Integration
If you have a dedicated friend service, update `_sendFriendRequestFromQr()` to use it:

```dart
Future<void> _sendFriendRequestFromQr(Map<String, dynamic> userData) async {
  // ... validation ...
  
  // Replace the Firestore writes with:
  await friendService.sendRequest(
    toUid: friendId,
    userData: userData,
  );
  
  // ... notification and feedback ...
}
```

## UX Flow

### Showing Own QR
1. User taps QR icon in app bar
2. `MyQrSheet` opens
3. Shows QR code with UID
4. User can tap "Share QR" to send via system share
5. QR is rendered to PNG and shared

### Adding Friend via QR (Mobile)
1. User taps add person icon
2. `AddFriendSheet` opens
3. User either:
   - Types UID/email in search field
   - Taps "Scan QR Code" button (mobile only)
4. If QR: Scanner opens, user points camera at friend's QR
5. On valid scan: Returns to sheet, auto-searches for that UID
6. Friend card displays with "Add" button
7. Tap "Add" to send request

### Adding Friend via Search (Desktop)
1. User taps add person icon
2. `AddFriendSheet` opens
3. User types UID or email
4. Sheet searches Firestore
5. Result shown in card
6. Tap "Add" to send request

## Security Notes

- **QR contains UID only**: Anyone can scan to see public profile
- **No tokens/keys in QR**: Payload is intentionally minimal
- **Per-user UID is semi-public**: Already exposed in Firestore for friend lookup
- **Future hardening**: Time-limited tokens or magic links could be added in Phase 06

## Platform Specifics

### Mobile (Android/iOS)
- Both search and QR scan available
- `mobile_scanner` provides camera integration
- Permissions required: camera (for QR)

### Desktop (Windows/macOS/Linux)
- QR scan button hidden (no camera API)
- Search by UID/email still available
- Can still receive and display own QR (for UX consistency)

## Testing Checklist

- [ ] Search friend by UID
- [ ] Search friend by email
- [ ] Scan valid Shoq QR code (mobile)
- [ ] Show own QR code and share
- [ ] Invalid QR code shows error
- [ ] Can't add self
- [ ] Already-friends validation works
- [ ] Friend request notification sent
- [ ] Search bar filters friends correctly
- [ ] On desktop: QR scan button hidden

## Files Modified

1. `pubspec.yaml` - Added `share_plus: ^10.0.0`
2. `lib/screens/friends_list_screen.dart` - Integrated QR widgets and search

## Files Created

1. `lib/core/utils/qr_utils.dart`
2. `lib/widgets/add_friend_sheet.dart`
3. `lib/widgets/my_qr_sheet.dart`
4. `lib/screens/qr_scanner_screen.dart`

---

All code follows the project's security-first and clean architecture principles. QR payload intentionally minimal, no encryption on QR itself (UID is semi-public), with all sensitive data fetched from authenticated Firestore calls.
