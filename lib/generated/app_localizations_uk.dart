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

  @override
  String get settingsTitle => 'Налаштування';

  @override
  String get sectionNotifications => 'Сповіщення';

  @override
  String get sectionAppearance => 'Зовнішній вигляд';

  @override
  String get friendRequestsTitle => 'Запити в друзі';

  @override
  String get friendRequestsSubtitle =>
      'Отримуйте сповіщення, коли хтось надсилає вам запит у друзі';

  @override
  String get messagesTitle => 'Повідомлення';

  @override
  String get messagesSubtitle =>
      'Отримуйте сповіщення, коли надходить нове повідомлення';

  @override
  String get textSize => 'Розмір тексту';

  @override
  String textSizeSubtitle(int percent) {
    return '$percent% - Множник розміру тексту';
  }

  @override
  String get welcomeBack => 'З поверненням';

  @override
  String get signInToContinue => 'Увійдіть, щоб продовжити';

  @override
  String get rememberMe => 'Запам\'ятати мене';

  @override
  String get dontHaveAnAccount => 'Немає облікового запису? ';

  @override
  String get alreadyHaveAnAccount => 'Вже є обліковий запис? ';

  @override
  String get acceptTermsPrefix => 'Я приймаю ';

  @override
  String get couldNotOpenLink => 'Не вдалося відкрити посилання';

  @override
  String get accountCreatedVerificationSent =>
      'Обліковий запис створено. Лист для підтвердження надіслано. Підтвердьте адресу на цьому екрані.';

  @override
  String get verifyYourEmail => 'Підтвердьте свою електронну пошту';

  @override
  String get verificationEmailSentTo =>
      'Ми надіслали лист для підтвердження на:';

  @override
  String get verificationWindowsHint =>
      'Автоперевірка працює у фоновому режимі на Windows. Якщо стан не оновився, натисніть \"Я підтвердив(-ла) електронну пошту\".';

  @override
  String resendInSeconds(int seconds) {
    return 'Надіслати повторно через $seconds с';
  }

  @override
  String get emailNotVerifiedYet =>
      'Електронну пошту ще не підтверджено. Перевірте свою скриньку.';

  @override
  String get iveVerifiedMyEmail => 'Я підтвердив(-ла) електронну пошту';

  @override
  String logoutFailed(String error) {
    return 'Не вдалося вийти: $error';
  }

  @override
  String get createAction => 'Створити';

  @override
  String get createFolder => 'Створити папку';

  @override
  String get createGroupChat => 'Створити груповий чат';

  @override
  String get createServer => 'Створити сервер';

  @override
  String get folderName => 'Назва папки';

  @override
  String get folderNameHint => 'Робота, Сім\'я, Ігри...';

  @override
  String get folderAlreadyExists => 'Папка вже існує';

  @override
  String get defaultUser => 'Користувач';

  @override
  String get addFriendsFirstToCreateRoom =>
      'Спочатку додайте друзів, щоб створити кімнату';

  @override
  String get createGroup => 'Створити групу';

  @override
  String get groupName => 'Назва групи';

  @override
  String get groupNameHint => 'Проєкт на вихідні';

  @override
  String get selectMembers => 'Виберіть учасників';

  @override
  String get selectAtLeastOneMember => 'Виберіть принаймні одного учасника';

  @override
  String get serverName => 'Назва сервера';

  @override
  String get serverNameHint => 'Мій сервер';

  @override
  String get serverIconPersonalizeHint =>
      'Ви можете налаштувати значок сервера в профілі сервера.';

  @override
  String get inviteLinkOrCode => 'Посилання або код запрошення';

  @override
  String get pasteInviteLinkOrServerCode =>
      'Вставте посилання-запрошення або код сервера';

  @override
  String get enterValidInviteLinkOrCode =>
      'Введіть дійсне посилання-запрошення або код';

  @override
  String get join => 'Приєднатися';

  @override
  String get inviteLinkInvalid => 'Посилання-запрошення недійсне';

  @override
  String get inviteLinkExpired => 'Термін дії цього запрошення закінчився';

  @override
  String get serverNotFoundForInvite =>
      'Сервер для цього запрошення не знайдено';

  @override
  String get permissionDeniedJoiningServer =>
      'Немає дозволу на приєднання до сервера. Оновіть правила Firestore для серверних запрошень і входу в розмови.';

  @override
  String couldNotJoinServer(String error) {
    return 'Не вдалося приєднатися до сервера: $error';
  }

  @override
  String couldNotJoinServerCode(String code) {
    return 'Не вдалося приєднатися до сервера ($code)';
  }

  @override
  String get atLeastTwoMembersRequired => 'Потрібно щонайменше 2 учасники';

  @override
  String get permissionDeniedCreatingRoom =>
      'Немає дозволу на створення кімнати. Перевірте правила Firestore для розмов.';

  @override
  String failedToCreateRoom(String error) {
    return 'Не вдалося створити кімнату: $error';
  }

  @override
  String failedToCreateRoomCode(String code) {
    return 'Не вдалося створити кімнату ($code)';
  }

  @override
  String moveConversation(String name) {
    return 'Перемістити \"$name\"';
  }

  @override
  String get allChats => 'Усі чати';

  @override
  String get createFolderFirst => 'Спочатку створіть папку';

  @override
  String get groupLabel => 'Група';

  @override
  String get serverLabel => 'Сервер';

  @override
  String get groupChat => 'Груповий чат';

  @override
  String get searchChats => 'Пошук чатів...';

  @override
  String get folder => 'Папка';

  @override
  String get myProfile => 'Мій профіль';

  @override
  String get myFriends => 'Мої друзі';

  @override
  String get about => 'Про застосунок';

  @override
  String get aboutDescription =>
      'Безпечний месенджер із наскрізним шифруванням.';

  @override
  String get notLoggedIn => 'Ви не увійшли';

  @override
  String genericError(String error) {
    return 'Помилка: $error';
  }

  @override
  String get chatOptions => 'Параметри чату';

  @override
  String get moveToFolder => 'Перемістити до папки';

  @override
  String removeFromFolder(String name) {
    return 'Видалити з $name';
  }

  @override
  String get noChatsYet => 'Чатів поки немає';

  @override
  String get addFriendsToStartChatting =>
      'Додайте друзів, щоб почати спілкування';

  @override
  String get addFriends => 'Додати друзів';

  @override
  String noChatsInFolder(String name) {
    return 'У $name немає чатів';
  }

  @override
  String get moveChatHereHint =>
      'Перемістіть чат сюди через меню будь-якої розмови.';

  @override
  String get yesterday => 'Учора';

  @override
  String daysAgo(int days) {
    return '$days дн. тому';
  }

  @override
  String get sentAMessage => 'Надіслав(-ла) повідомлення';

  @override
  String get startChatting => 'Почніть спілкування';

  @override
  String couldNotOpenInvite(String error) {
    return 'Не вдалося відкрити запрошення: $error';
  }

  @override
  String get friendsTitle => 'Друзі';

  @override
  String get myQrCode => 'Мій QR-код';

  @override
  String get addFriend => 'Додати друга';

  @override
  String get requestsTitle => 'Запити';

  @override
  String get blockedTitle => 'Заблоковані';

  @override
  String get searchFriends => 'Пошук друзів';

  @override
  String get noFriendsYet => 'Друзів поки немає';

  @override
  String get sendFriendRequestsToConnect =>
      'Надсилайте запити в друзі, щоб спілкуватися';

  @override
  String noFriendsMatch(String filter) {
    return 'Немає друзів за запитом \"$filter\"';
  }

  @override
  String get noFriendRequests => 'Немає запитів у друзі';

  @override
  String get noBlockedUsers => 'Немає заблокованих користувачів';

  @override
  String get unblock => 'Розблокувати';

  @override
  String get invalidUserData => 'Недійсні дані користувача';

  @override
  String get cannotAddYourself => 'Не можна додати себе';

  @override
  String get alreadyFriends => 'Ви вже друзі';

  @override
  String get friendRequestAlreadySent => 'Запит у друзі вже надіслано';

  @override
  String friendRequestSentTo(String name) {
    return 'Запит у друзі надіслано користувачу $name!';
  }

  @override
  String get friendRequestAccepted => 'Запит у друзі прийнято!';

  @override
  String get friendRequestDenied => 'Запит у друзі відхилено';

  @override
  String get userBlocked => 'Користувача заблоковано';

  @override
  String get userUnblocked => 'Користувача розблоковано';

  @override
  String get removeFriend => 'Видалити друга';

  @override
  String removeFriendConfirm(String name) {
    return 'Ви впевнені, що хочете видалити $name зі списку друзів?';
  }

  @override
  String get remove => 'Видалити';

  @override
  String get friendRemoved => 'Друга видалено';

  @override
  String get removeFriendMenu => 'Видалити друга';

  @override
  String get block => 'Заблокувати';
}
