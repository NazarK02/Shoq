# Shoq

[English](README.md) · **Português (Portugal)** · [Українська](README.uk.md)

> Mensageiro multiplataforma com encriptação ponta a ponta, construído com Flutter e Firebase.

---

## O que é o Shoq?

O Shoq é um mensageiro seguro e de código aberto com encriptação ponta a ponta (E2EE). As mensagens são encriptadas no dispositivo do remetente e só podem ser desencriptadas no dispositivo do destinatário. A Firebase nunca recebe conteúdo em texto simples.

---

## Plataformas suportadas

| Plataforma | Estado |
|---|---|
| Android | ✅ Suportado |
| iOS | ✅ Suportado |
| Windows | ✅ Suportado |
| macOS | ✅ Suportado |
| Linux | ✅ Suportado |

---

## Pilha tecnológica

| Camada | Tecnologia |
|---|---|
| Framework | Flutter / Dart |
| Backend | Firebase Auth, Firestore, FCM, Storage |
| Cifra simétrica | XChaCha20-Poly1305 |
| Troca de chaves | X25519 (ECDH) |
| Identidade | Ed25519 |
| Armazenamento de chaves | flutter_secure_storage |
| Implementação criptográfica | libsodium via sodium_libs |

---

## Funcionalidades

- **Encriptação ponta a ponta** — cifra por dispositivo via X25519 + XChaCha20-Poly1305
- **Autenticação** — e-mail/palavra-passe e Google Sign-In
- **Conversas individuais e servidores** — canais de texto, voz, ficheiros, fórum e tarefas
- **Transferência de ficheiros e imagens** — com progresso e diretorias por plataforma
- **Canais de voz WebRTC** — com silenciar, ensurdecer, alternância de altifalante e verificações de saúde da ligação
- **Notificações push FCM** — sem conteúdo no payload (zero-content)
- **Presença de utilizador** — com heartbeat Firestore
- **Descoberta de contactos por QR** — via `qr_flutter` + `mobile_scanner`
- **Pastas de conversa** — organização personalizada
- **Seletor de emojis**, pré-visualizações de ligações, estado das mensagens

---

## Arquitetura de segurança

### O que está protegido
- **Conteúdo das mensagens** — encriptado no dispositivo do remetente antes de qualquer escrita na Firestore
- **Mapa de texto cifrado por dispositivo** — cada dispositivo destinatário recebe a sua própria cópia encriptada
- **Chaves privadas** — nunca saem do dispositivo em que foram geradas, armazenadas via `flutter_secure_storage`

### Limitações conhecidas (seja honesto com os seus utilizadores)
- **Sem verificação de chaves.** Não existe comparação de impressão digital nem mecanismo de número de segurança. Um atacante com acesso à Firestore poderia substituir uma chave pública (ataque TOFU / substituição de chave). Esta é a lacuna de segurança em aberto mais significativa.
- **Os metadados não estão protegidos.** A Firebase observa quem comunica com quem, quando e com que frequência. Apenas o conteúdo das mensagens é encriptado.
- **A rotação de chaves não está implementada.** Está prevista para a Fase 06. O segredo direto (forward secrecy) não está completo até que seja implementada.

---

## Roteiro

| Fase | Título | Estado |
|---|---|---|
| 01 | Fundação | ✅ Concluído |
| 02 | Registo de chaves públicas | ✅ Concluído |
| 03 | Núcleo de mensagens E2EE | ✅ Concluído |
| 04 | Notificações e presença | ✅ Concluído |
| 05 | Descoberta de contactos | 🔄 Em progresso |
| 06 | Rotação de chaves e multi-dispositivo | 📋 Planeado |
| 07 | Distribuição para desktop | 📋 Planeado |

---

## Início rápido

```bash
# Pré-requisitos: Flutter SDK, Firebase CLI, conta Firebase

git clone https://github.com/NazarK02/Shoq.git
cd Shoq

flutter pub get
flutter gen-l10n

# Configure o seu projeto Firebase e coloque o google-services.json / GoogleService-Info.plist
flutter run
```

---

## Contribuir

Contribuições são bem-vindas, especialmente em áreas de segurança. Antes de submeter uma pull request que afete a criptografia, por favor abra uma issue primeiro para discussão.

---

## Licença

Consulte o ficheiro [LICENSE](LICENSE) para mais detalhes.

---

## Aviso de segurança

Este software está em desenvolvimento ativo. A lacuna de verificação de chaves descrita acima representa um vetor de ataque real. Não o utilize em contextos onde o sigilo contra um adversário com acesso à base de dados seja um requisito crítico — até que a verificação de impressão digital seja implementada (Fase 06).
