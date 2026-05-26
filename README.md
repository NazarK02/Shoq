# Shoq

Shoq is a Flutter and Firebase messenger focused on client-side encryption,
multi-platform chat, rooms, voice/video calling, and friend discovery.

The project is in active development. Core messaging, rooms, calls,
notifications, presence, QR discovery, and invite links are implemented, but
Shoq should not be marketed as production-secure until the open security gaps
below are fixed and audited.

## Current Status

Implemented:

- Firebase Auth with email/password, Google Sign-In, email verification, and
  password reset flows
- User profiles with display names, avatars, friend IDs, profile editing, and
  cached profile data
- Friends, friend requests, blocking/removal, QR contact sharing, and QR
  scanning on camera-supported platforms
- One-to-one conversations and room/server conversations
- Room channels for text, voice, forum, files, and assignments
- Shareable room invite links through Firebase Hosting and deep links
- Client-side encrypted text, sticker, location, and room message bodies using
  libsodium `crypto.box`
- Per-device ciphertext maps so each registered recipient device can receive an
  encrypted copy
- Legacy public-key fallback and startup E2EE migration helper
- Message edit, delete, reply, read status, pinned previews, link previews,
  emoji, stickers, and GIPHY GIF search
- File and image upload/download through Firebase Storage with per-platform
  download paths and progress tracking
- One-to-one WebRTC audio/video calls, incoming call notifications, and active
  call session handling
- WebRTC voice channels with mute, deafen, speaker toggle, presence heartbeat,
  and connection health checks
- FCM notifications on Android/iOS and local notifications on Android/iOS/Windows
- CallKit integration for incoming calls on supported mobile platforms
- Firestore offline cache warming for conversations, messages, and profiles
- Light/dark themes, UI scale settings, and localization for English,
  Portuguese, Portuguese (Portugal), and Ukrainian

Planned or high priority:

- Key fingerprint / safety number verification
- Signed prekeys, key rotation, and stronger forward-secrecy story
- Removal or redesign of the Firestore account key backup path
- App-layer encryption for uploaded file bytes
- Audit and removal/encryption of plaintext compatibility fields
- Multi-device enrollment approval from an existing trusted device
- Windows MSIX packaging, macOS packaging, and code-signing pipeline

## Platforms

Primary app targets:

| Platform | Status |
| --- | --- |
| Android | Supported |
| iOS | Supported |
| Windows | Supported |
| macOS | Supported |
| Linux | Supported |

Flutter web files are present, but the web build is not treated as a primary
secure client target.

## Security Model

Shoq treats Firebase as an untrusted transport for encrypted chat content. The
current E2EE implementation encrypts message bodies on the client before
writing them to Firestore.

Implemented protections:

- Message bodies for text, sticker, location, and room chat are encrypted before
  Firestore writes.
- Recipient ciphertext is stored per registered device and by short public-key
  identifier.
- Active local key material is stored through `flutter_secure_storage`.
- FCM data payloads carry routing metadata such as type, sender/conversation
  IDs, and call IDs. They do not contain message text.
- Notification display fields may include generic text and sender names, but
  not decrypted message bodies.

Known limitations:

- No key verification exists yet. A Firestore-level attacker could substitute a
  public key and perform a key-substitution attack.
- The current migration/recovery path can store account key material in
  Firestore at `users/{uid}/settings/e2ee_keys`. This weakens the threat model
  and must be removed or replaced with a client-encrypted recovery design before
  production security claims.
- File bytes uploaded to Firebase Storage are not app-layer E2EE. Direct file
  message metadata may be encrypted, but room file records and storage objects
  are protected mainly by Firebase rules.
- Some compatibility fields can be plaintext, including reply previews, pin
  previews, call signaling documents, file metadata, timestamps, sender IDs,
  read state, channel IDs, and participant metadata.
- Metadata is visible to Firebase: who talks to whom, when, how often, room
  membership, device counts, and notification routing data.
- Key rotation and signed prekeys are not implemented. Do not claim complete
  forward secrecy.
- Endpoint compromise is out of scope. If a device is compromised, displayed
  plaintext can be captured.

## Crypto Stack

| Purpose | Current implementation |
| --- | --- |
| Public-key encryption | libsodium `crypto.box.easy/openEasy` |
| Key agreement | Curve25519/X25519-compatible `crypto.box` keypairs |
| Authenticated cipher | libsodium `crypto_box` construction, XSalsa20-Poly1305 |
| Public-key IDs | SHA-256 hash prefix of the base64 public key |
| Local key storage | `flutter_secure_storage` |
| Backend key registry | Firestore user device map |

Notes:

- The code does not currently implement an Ed25519 identity/signing layer.
- The code does not currently use XChaCha20-Poly1305 for chat messages.
- Do not introduce custom cryptography.

## Architecture

Important app modules:

```text
lib/services/
  crypto_service.dart             - key creation, local key loading, encryption/decryption
  chat_service_e2ee.dart          - conversations, encrypted payloads, files, read state
  notification_service.dart       - FCM tokens, local notifications, call notifications
  user_service_e2ee.dart          - profiles, friend IDs, auth-side user data
  e2ee_migration_helper.dart      - startup key migration helper
  device_info_service.dart        - per-platform device IDs
  presence_service.dart           - online/offline heartbeat
  active_session_service.dart     - background call/voice session state
  file_download_service.dart      - per-platform downloads and progress tracking
  chat_folder_service.dart        - local conversation folders
  server_invite_service.dart      - Firebase Hosting invite links and deep-link parsing
  signaling_service.dart          - WebRTC signaling client
  app_prefetch_service.dart       - Firestore cache warm-up after login
  theme_service.dart              - themes and UI scaling
  locale_service.dart             - locale persistence

lib/screens/
  chat_screen_e2ee.dart           - one-to-one chat UI
  room_chat_screen.dart           - room/channel chat UI
  call_screen.dart                - one-to-one WebRTC calls
  voice_channel_screen.dart       - room voice channel UI
  friends_list_screen.dart        - contacts, requests, QR entry points
  qr_scanner_screen.dart          - camera QR scanner
  profile_screen.dart             - profile and avatar editing

functions/
  index.js                        - Cloud Functions for push notification fan-out

hosting/
  index.html                      - Firebase Hosting invite landing page

docs/
  index.html                      - project landing page
  PROJECT_INSTRUCTIONS.md         - current engineering/security instructions
```

## Firestore And Storage

Core collections used by the app include:

- `users/{uid}` for profile data, device public keys, FCM tokens, presence, and
  settings
- `conversations/{conversationId}` for direct and room metadata
- `conversations/{conversationId}/messages/{messageId}` for encrypted message
  documents and metadata
- `contacts/{uid}/friends/{friendUid}` for friend lists
- `friendRequests/{requestId}` for friend request workflow
- `serverInvites/{code}` for shareable room invite links
- `notifications/{notificationId}` for Cloud Functions notification fan-out
- Firebase Storage paths such as `chat_files/{conversationId}/...` and
  `profile_pictures/{uid}/...`

Firestore and Storage rules live under `tools/signaling-server/`.

## Getting Started

Prerequisites:

- Flutter SDK compatible with Dart `^3.10.7`
- A Firebase project with Auth, Firestore, Storage, FCM, Functions, and Hosting
- Node.js 20+ for Firebase Functions and the optional local signaling server

Setup:

```bash
git clone https://github.com/NazarK02/Shoq
cd Shoq
flutter pub get
flutterfire configure
flutter run
```

Deploy Firebase rules and backend pieces as needed:

```bash
firebase deploy --only firestore:rules,storage:rules
firebase deploy --only functions
firebase deploy --only hosting
```

Optional local signaling server:

```bash
cd tools/signaling-server
npm install
npm start
```

Then pass its URL with `--dart-define=SIGNALING_URL=ws://host:3000` if you are
testing WebRTC signaling through the standalone server.

## Roadmap

| Phase | Scope | Status |
| --- | --- | --- |
| 01 | Auth, profiles, friend IDs, email verification | Complete |
| 02 | libsodium key generation, secure storage, device public-key registry | Complete with caveats |
| 03 | Direct encrypted messaging, rooms, channels, stickers, location, files | Complete with caveats |
| 04 | WebRTC calls, voice channels, notifications, presence | Complete |
| 05 | QR contacts, friend discovery, server invite links, localization | Mostly complete |
| 06 | Safety numbers, key rotation, signed prekeys, multi-device approval | Planned |
| 07 | File-byte encryption, plaintext-field audit, key-backup redesign | Planned/high priority |
| 08 | Desktop installers, macOS bundle, code signing, release pipeline | Planned |

## Contributing

Security review is especially welcome around:

- `lib/services/crypto_service.dart`
- `lib/services/chat_service_e2ee.dart`
- Firestore and Storage rules
- notification payload design
- key backup, key verification, and file encryption

Open an issue before large changes so security and architecture tradeoffs can be
discussed first.

## License

No repository license file is currently present. Add a license before publishing
or accepting external contributions as open-source work.
