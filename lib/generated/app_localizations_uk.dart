// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'Shoq';

  @override
  String get appTagline => 'Приватність за задумом.';

  @override
  String get lightMode => 'Світлий режим';

  @override
  String get darkMode => 'Темний режим';

  @override
  String get darkThemeEnabled => 'Темну тему увімкнено';

  @override
  String get lightThemeEnabled => 'Світлу тему увімкнено';

  @override
  String get uiSize => 'Розмір інтерфейсу';

  @override
  String uiSizeSubtitle(int percent) {
    return '$percent% · Більший або менший інтерфейс';
  }

  @override
  String get reduceMotion => 'Зменшити анімацію';

  @override
  String get reduceMotionSubtitle => 'Менше анімацій для плавнішої навігації';

  @override
  String get linkPreviews => 'Попередній перегляд посилань';

  @override
  String get linkPreviewsSubtitle =>
      'Показувати попередній перегляд сайтів і YouTube у повідомленнях';

  @override
  String get sectionGeneral => 'Загальне';

  @override
  String get sectionPreferences => 'Налаштування';

  @override
  String get sectionSupport => 'Підтримка';

  @override
  String get sectionChat => 'Чат';

  @override
  String get privacy => 'Конфіденційність';

  @override
  String get privacySubtitle => 'Керуйте налаштуваннями конфіденційності';

  @override
  String get security => 'Безпека';

  @override
  String get securitySubtitle => 'Пароль і автентифікація';

  @override
  String get language => 'Мова';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePortuguese => 'Português (Portugal)';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get helpSupport => 'Довідка та підтримка';

  @override
  String get termsOfService => 'Умови використання';

  @override
  String get privacyPolicy => 'Політика конфіденційності';

  @override
  String get comingSoon => 'Незабаром';

  @override
  String get languageComingSoon => 'Налаштування мови незабаром';

  @override
  String get helpSupportComingSoon => 'Довідка та підтримка незабаром';

  @override
  String get termsComingSoon => 'Умови використання незабаром';

  @override
  String get privacySettingsComingSoon =>
      'Налаштування конфіденційності незабаром';

  @override
  String get securitySettingsComingSoon => 'Налаштування безпеки незабаром';

  @override
  String get signIn => 'Увійти';

  @override
  String get signUp => 'Зареєструватися';

  @override
  String get signOut => 'Вийти';

  @override
  String get createAccount => 'Створити обліковий запис';

  @override
  String get signUpToGetStarted => 'Зареєструйтеся, щоб розпочати';

  @override
  String get email => 'Електронна пошта';

  @override
  String get password => 'Пароль';

  @override
  String get confirmPassword => 'Підтвердити пароль';

  @override
  String get fullName => 'Повне ім\'я';

  @override
  String get forgotPassword => 'Забули пароль?';

  @override
  String get continueWithGoogle => 'Продовжити з Google';

  @override
  String get orSeparator => 'або';

  @override
  String get acceptTerms => 'Я приймаю Умови та Положення';

  @override
  String get pleaseAcceptTerms => 'Будь ласка, прийміть Умови та Положення';

  @override
  String get pleaseEnterName => 'Будь ласка, введіть ваше ім\'я';

  @override
  String get pleaseEnterEmail => 'Будь ласка, введіть вашу електронну пошту';

  @override
  String get pleaseEnterPassword => 'Будь ласка, введіть пароль';

  @override
  String get passwordTooShort => 'Пароль повинен містити щонайменше 6 символів';

  @override
  String get passwordsDoNotMatch => 'Паролі не збігаються';

  @override
  String get pleaseConfirmPassword => 'Будь ласка, підтвердіть ваш пароль';

  @override
  String get verificationEmailSent =>
      'Лист із підтвердженням надіслано! Перевірте вашу пошту.';

  @override
  String get resendVerificationEmail => 'Надіслати лист підтвердження повторно';

  @override
  String get emailNotVerifiedTitle => 'Підтвердіть електронну пошту';

  @override
  String get emailNotVerifiedBody =>
      'Посилання для підтвердження надіслано на вашу адресу. Перевірте пошту та натисніть посилання, щоб продовжити.';

  @override
  String get authErrorDefault => 'Сталася помилка';

  @override
  String get authErrorWeakPassword => 'Пароль занадто слабкий';

  @override
  String get authErrorEmailInUse => 'Обліковий запис для цієї адреси вже існує';

  @override
  String get authErrorInvalidEmail => 'Недійсна адреса електронної пошти';

  @override
  String get authErrorNotAllowed =>
      'Облікові записи з електронною поштою/паролем не увімкнено';

  @override
  String get authErrorNetwork => 'Помилка мережі. Перевірте своє з\'єднання.';

  @override
  String get authErrorWrongPassword => 'Неправильний пароль';

  @override
  String get authErrorUserNotFound =>
      'Обліковий запис для цієї адреси не знайдено';

  @override
  String get authErrorTooManyRequests => 'Забагато спроб. Спробуйте пізніше.';

  @override
  String get googleSignInUnsupportedLinux =>
      'Вхід через Google не підтримується на Linux. Використовуйте електронну пошту/пароль.';

  @override
  String get googleSignInUnsupportedPlatform =>
      'Вхід через Google не підтримується на цій платформі.';

  @override
  String get channels => 'Канали';

  @override
  String get serverProfile => 'Профіль сервера';

  @override
  String get deleteChannel => 'Видалити канал';

  @override
  String deleteChannelConfirm(String name) {
    return 'Видалити #$name? Наявні повідомлення залишаться в історії.';
  }

  @override
  String get cancel => 'Скасувати';

  @override
  String get delete => 'Видалити';

  @override
  String get channelAlreadyExists => 'Канал вже існує';

  @override
  String get selectVoiceChannelFirst => 'Спочатку виберіть голосовий канал.';

  @override
  String get channelNoTextSupport =>
      'Цей канал не підтримує текстові повідомлення.';

  @override
  String get channelNoStickerSupport => 'Цей канал не підтримує стікери.';

  @override
  String get useUploadButton =>
      'Використайте кнопку завантаження, щоб поділитися файлами в цьому каналі.';

  @override
  String failedToSend(String error) {
    return 'Помилка надсилання: $error';
  }

  @override
  String couldNotOpenChatRoom(String error) {
    return 'Не вдалося відкрити кімнату чату: $error';
  }

  @override
  String dueDate(String date) {
    return 'Термін: $date';
  }

  @override
  String get room => 'Кімната';

  @override
  String get members => 'Учасники';

  @override
  String get inviteCode => 'Код запрошення';

  @override
  String get joinServer => 'Приєднатися до сервера';

  @override
  String get openInShoq => 'Відкрити в Shoq';

  @override
  String get copyCode => 'Скопіювати код';

  @override
  String get codeCopied => 'Код скопійовано';

  @override
  String get invitePreview => 'Попередній перегляд запрошення';

  @override
  String get invitePageInstructions =>
      'Використайте цей код запрошення у застосунку Shoq.';

  @override
  String get inviteStep1 => 'Відкрийте Shoq.';

  @override
  String get inviteStep2 => 'Натисніть «Приєднатися до сервера».';

  @override
  String get inviteStep3 => 'Вставте код запрошення та підтвердіть.';

  @override
  String get invitePageNote =>
      'Ця сторінка призначена лише для посилань-запрошень. Якщо пряме відкриття не спрацює, скопіюйте код і приєднайтеся вручну у застосунку.';

  @override
  String get qrScanTitle => 'Сканувати QR-код';

  @override
  String get qrShareTitle => 'Ваш QR-код';

  @override
  String get muteAudio => 'Вимкнути мікрофон';

  @override
  String get unmuteAudio => 'Увімкнути мікрофон';

  @override
  String get deafen => 'Вимкнути звук';

  @override
  String get undeafen => 'Увімкнути звук';

  @override
  String get leaveVoice => 'Покинути голосовий канал';

  @override
  String get voiceConnecting => 'Підключення…';

  @override
  String get voiceConnected => 'Підключено';

  @override
  String get voiceDisconnected => 'Відключено';

  @override
  String get activeVoiceSession => 'Активна голосова сесія';

  @override
  String get returnToCall => 'Повернутися до дзвінка';

  @override
  String get uploading => 'Завантаження…';

  @override
  String get systemDefault => 'Системний за замовчуванням';

  @override
  String get selectLanguage => 'Виберіть мову';
}
