# Shoq

A production-grade, end-to-end encrypted messenger built with Flutter and Firebase.
Zero server-side plaintext. Every message is encrypted on your device before it leaves.

> **Status:** Active development — core E2EE, messaging, voice, and presence are complete.
> QR-based contact discovery is in progress. Key rotation and Windows installer are planned.

---

## What it is

Shoq is a multiplatform messaging application designed around a single constraint: **the server must never see your messages in plaintext**. Firebase is used purely as an authenticated, encrypted transport — not as a trusted service.

The encryption stack is built on established primitives via `libsodium`:
- **XChaCha20-Poly1305** for symmetric authenticated encryption
- **X25519** for ephemeral Diffie-Hellman key exchange
- **Ed25519** for long-term identity signing

No custom cryptography. No shortcuts. No marketing claims that can't be verified by reading the code.

---

## Platforms

| Platform | Status |
|---|---|
| Android | Supported |
| iOS | Supported |
| Windows | Supported |
| macOS | Supported |
| Linux | Supported |

---

## Feature overview

### Messaging
- One-to-one encrypted chat
- Room/server architecture with named channels (text, voice, file, forum, assignments)
- File and image transfer with per-platform download paths and progress tracking
- Emoji picker, link previews, message status (sent / delivered / read)
- Chat folders for conversation organisation

### Encryption
- Per-device keypairs — each device holds its own private key, which never leaves the device
- Messages stored in Firestore as ciphertext only; a separate encrypted copy is written per recipient device key
- Legacy key fallback for users who have not yet migrated to per-device keys
- E2EE migration helper runs at startup to ensure all accounts have encryption enabled

### Voice
- Real-time voice channels via WebRTC (`flutter_webrtc`)
- Peer-to-peer audio with mute, deafen, and speaker toggle
- Presence heartbeat and connection health checks
- Signalling via Firestore — no audio content is transmitted through Firebase

### Identity and authentication
- Firebase Auth — email/password and Google Sign-In
- Each Firebase Auth UID is tied to one or more device keypairs
- Public keys published to Firestore; private keys stored in platform-native secure storage
- New device enrollment writes the new device key to the user's key registry

### Notifications
- FCM push on Android and iOS
- Local notifications on Windows (no FCM dependency)
- Notification payloads carry zero message content — only a generic wake signal
- User-controlled notification preferences stored in Firestore

### Presence
- Online/offline/away state with Firestore heartbeat
- Active session banner when a voice session is running in the background

### Contact discovery
- QR code-based contact system (`qr_flutter` + `mobile_scanner`) — in progress

---

## Tech stack

| Layer | Technology |
|---|---|
| Frontend | Flutter 3.x / Dart |
| Encryption | libsodium (`sodium_libs` / `libsodium_dart`), `encrypt`, `crypto` |
| Auth | Firebase Authentication |
| Database | Cloud Firestore |
| Push | Firebase Cloud Messaging |
| Voice | `flutter_webrtc` |
| Secure storage | `flutter_secure_storage` (Keychain / Keystore / DPAPI / SecretService) |
| QR | `qr_flutter` + `mobile_scanner` |
| Media | `video_player`, `image_picker`, `file_picker` |

---

## Security model

### What is protected
- Message content is never written to Firestore in plaintext
- FCM payloads contain no message content
- Private keys never leave the originating device
- Firestore security rules enforce access without the server reading content

### Known limitations and threat model
- **Key verification is not implemented.** There is currently no fingerprint comparison or safety number mechanism. A compromised Firestore account could replace a user's public key (a TOFU/key-substitution attack). This is the most significant open security gap.
- **Metadata is visible to Firebase.** Who messages whom, when, and how frequently is observable from Firestore access logs. Only content is encrypted.
- **Multi-device approval is not yet hardened.** The enrollment flow exists, but a formal approval gate from an existing device is planned for Phase 06.
- **Key rotation is planned but not yet complete.** Rotating keys will invalidate old sessions; the implementation is scoped for Phase 06.
- This project is suitable for learning and development use. It is not recommended for adversarial or legally sensitive communications until the key verification and rotation phases are complete.

---

## Project structure

```
lib/
  services/
    auth_service.dart           — Firebase Auth wrapper
    crypto_service.dart         — libsodium key generation, encrypt, decrypt
    chat_service_e2ee.dart      — E2EE message send/receive, per-device ciphertext
    e2ee_migration_helper.dart  — Ensures all users have encryption keys on startup
    notification_service.dart   — FCM registration and local notification dispatch
    device_info_service.dart    — Device ID resolution per platform
    file_download_service.dart  — Encrypted file fetch, progress, platform paths
    chat_folder_service.dart    — Conversation folder management
    active_session_service.dart — Voice session background state
  screens/
    room_chat_screen.dart       — Channel-based room/server chat UI
    voice_channel_screen.dart   — WebRTC voice channel UI
    ...
  models/
    ...
tools/
  signaling-server/             — Node.js WebSocket signalling server (dev/CI use)
functions/                      — Firebase Cloud Functions
docs/
  index.html                    — Project landing page
```

---

## Getting started

### Prerequisites
- Flutter SDK 3.x
- A Firebase project with Authentication, Firestore, and FCM enabled
- Node.js 20+ (only needed if running the standalone signalling server locally)

### Setup

```bash
git clone https://github.com/NazarK02/Shoq
cd Shoq
flutter pub get
flutterfire configure
flutter run
```

`flutterfire configure` will generate `firebase_options.dart` and place the relevant `google-services.json` / `GoogleService-Info.plist` files. These files are gitignored and must be generated per-environment.

### Firestore rules

Firestore security rules must be deployed before the app will function correctly. Rules enforce that:
- Users can only read conversations they are a participant of
- Encrypted message documents can be written only by authenticated senders
- Public key documents are writable only by the owning user

Deploy with:

```bash
firebase deploy --only firestore:rules
```

### Windows build

```bash
flutter build windows --release
```

The output is located at `build/windows/x64/runner/Release/`. An MSIX installer and Inno Setup script are planned for Phase 07.

---

## Roadmap

| Phase | Description | Status |
|---|---|---|
| 01 | Firebase Auth, user profiles, Google Sign-In | Complete |
| 02 | Key generation, secure storage, public key registry | Complete |
| 03 | E2EE messaging, per-device ciphertext, file transfer, WebRTC voice | Complete |
| 04 | FCM push, local notifications, presence heartbeat, notification preferences | Complete |
| 05 | QR code contact discovery | In progress |
| 06 | Signed prekey rotation, multi-device enrollment hardening | Planned |
| 07 | Windows MSIX package, macOS bundle, code-signing pipeline | Planned |

---

## Contributing

The project is open to contributions. Areas most in need of review:

- Cryptographic correctness — any review of `crypto_service.dart` and `chat_service_e2ee.dart` is welcome
- Firestore security rules — rule coverage and edge cases
- Key verification UX — fingerprint / safety number comparison is the highest-priority open security gap
- Windows packaging — MSIX or Inno Setup configuration

Please open an issue before submitting large changes.

---

## License

See `LICENSE` in the repository root.
