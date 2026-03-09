# Shoq

**English** · [Português (Portugal)](README.pt-PT.md) · [Українська](README.uk.md)

> Cross-platform messenger with end-to-end encryption, built with Flutter and Firebase.

---

## What is Shoq?

Shoq is a secure, open-source messenger with end-to-end encryption (E2EE). Messages are encrypted on the sender's device and can only be decrypted on the recipient's device. Firebase never receives plaintext content.

---

## Supported Platforms

| Platform | Status |
|---|---|
| Android | ✅ Supported |
| iOS | ✅ Supported |
| Windows | ✅ Supported |
| macOS | ✅ Supported |
| Linux | ✅ Supported |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter / Dart |
| Backend | Firebase Auth, Firestore, FCM, Storage |
| Symmetric cipher | XChaCha20-Poly1305 |
| Key exchange | X25519 (ECDH) |
| Identity | Ed25519 |
| Key storage | flutter_secure_storage |
| Cryptographic implementation | libsodium via sodium_libs |

---

## Features

- **End-to-end encryption** — per-device encryption via X25519 + XChaCha20-Poly1305
- **Authentication** — email/password and Google Sign-In
- **Individual chats and servers** — text, voice, file channels, forum, and tasks
- **File and image transfer** — with progress display and platform-specific directories
- **WebRTC voice channels** — with mute, deafen, speaker toggle, and connection health checks
- **FCM push notifications** — with zero-content payloads
- **User presence** — with Firestore heartbeat
- **QR contact discovery** — via `qr_flutter` + `mobile_scanner`
- **Conversation folders** — custom organization
- **Emoji picker**, link previews, message status

---

## Security Architecture

### What's Protected
- **Message content** — encrypted on sender's device before any Firestore write
- **Per-device ciphertext map** — each recipient device receives its own encrypted copy
- **Private keys** — never leave the device they were generated on; stored via `flutter_secure_storage`

### Known Limitations (Be Honest with Your Users)
- **No key verification.** There is no fingerprint comparison or security number mechanism. An attacker with Firestore access could substitute a public key (TOFU / key substitution attack). This is the most significant open security gap.
- **Metadata is unprotected.** Firebase observes who communicates with whom, when, and how often. Only message content is encrypted.
- **Key rotation is not implemented.** Scheduled for Phase 06. Forward secrecy is incomplete until rotation is deployed.

---

## Roadmap

| Phase | Title | Status |
|---|---|---|
| 01 | Foundation | ✅ Complete |
| 02 | Public key registry | ✅ Complete |
| 03 | E2EE messaging core | ✅ Complete |
| 04 | Notifications and presence | ✅ Complete |
| 05 | Contact discovery | 🔄 In progress |
| 06 | Key rotation and multi-device | 📋 Planned |
| 07 | Desktop distribution | 📋 Planned |

---

## Quick Start

```bash
# Prerequisites: Flutter SDK, Firebase CLI, Firebase account

git clone https://github.com/NazarK02/Shoq.git
cd Shoq

flutter pub get
flutter gen-l10n

# Configure your Firebase project and place google-services.json / GoogleService-Info.plist
flutter run
```

---

## Contributing

Contributions are welcome, especially in security areas. Before submitting a pull request that affects cryptography, please open an issue first for discussion.

---

## License

See the [LICENSE](LICENSE) file for details.

---

## Security Warning

This software is under active development. The key verification gap described above represents a real attack vector. Do not use it in contexts where secrecy from an attacker with database access is a critical requirement — until fingerprint verification is implemented (Phase 06).
