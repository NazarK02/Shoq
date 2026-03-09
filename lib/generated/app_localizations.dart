import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
    Locale('pt', 'PT'),
    Locale('uk'),
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'Shoq'**
  String get appTitle;

  /// App tagline shown on landing / splash
  ///
  /// In en, this message translates to:
  /// **'Private by design.'**
  String get appTagline;

  /// Tooltip: switch to light theme
  ///
  /// In en, this message translates to:
  /// **'Light Mode'**
  String get lightMode;

  /// Tooltip: switch to dark theme
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @darkThemeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Dark theme enabled'**
  String get darkThemeEnabled;

  /// No description provided for @lightThemeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Light theme enabled'**
  String get lightThemeEnabled;

  /// No description provided for @uiSize.
  ///
  /// In en, this message translates to:
  /// **'UI Size'**
  String get uiSize;

  /// No description provided for @uiSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{percent}% · Bigger or smaller interface'**
  String uiSizeSubtitle(int percent);

  /// No description provided for @reduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// No description provided for @reduceMotionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use less animation for smoother navigation'**
  String get reduceMotionSubtitle;

  /// No description provided for @linkPreviews.
  ///
  /// In en, this message translates to:
  /// **'Link previews'**
  String get linkPreviews;

  /// No description provided for @linkPreviewsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show website and YouTube previews in messages'**
  String get linkPreviewsSubtitle;

  /// No description provided for @sectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get sectionGeneral;

  /// No description provided for @sectionPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get sectionPreferences;

  /// No description provided for @sectionSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get sectionSupport;

  /// No description provided for @sectionChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get sectionChat;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Control your privacy settings'**
  String get privacySubtitle;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @securitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Password and authentication'**
  String get securitySubtitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languagePortuguese.
  ///
  /// In en, this message translates to:
  /// **'Português (Portugal)'**
  String get languagePortuguese;

  /// No description provided for @languageUkrainian.
  ///
  /// In en, this message translates to:
  /// **'Українська'**
  String get languageUkrainian;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @languageComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Language settings coming soon'**
  String get languageComingSoon;

  /// No description provided for @helpSupportComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Help & Support coming soon'**
  String get helpSupportComingSoon;

  /// No description provided for @termsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service coming soon'**
  String get termsComingSoon;

  /// No description provided for @privacySettingsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Privacy settings coming soon'**
  String get privacySettingsComingSoon;

  /// No description provided for @securitySettingsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Security settings coming soon'**
  String get securitySettingsComingSoon;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @signUpToGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Sign up to get started'**
  String get signUpToGetStarted;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @orSeparator.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get orSeparator;

  /// No description provided for @acceptTerms.
  ///
  /// In en, this message translates to:
  /// **'I accept the Terms and Conditions'**
  String get acceptTerms;

  /// No description provided for @pleaseAcceptTerms.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Terms and Conditions'**
  String get pleaseAcceptTerms;

  /// No description provided for @pleaseEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get pleaseEnterName;

  /// No description provided for @pleaseEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get pleaseEnterEmail;

  /// No description provided for @pleaseEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password'**
  String get pleaseEnterPassword;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordTooShort;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @pleaseConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get pleaseConfirmPassword;

  /// No description provided for @verificationEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent! Check your inbox.'**
  String get verificationEmailSent;

  /// No description provided for @resendVerificationEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend verification email'**
  String get resendVerificationEmail;

  /// No description provided for @emailNotVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get emailNotVerifiedTitle;

  /// No description provided for @emailNotVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'A verification link was sent to your email address. Please check your inbox and click the link to continue.'**
  String get emailNotVerifiedBody;

  /// No description provided for @authErrorDefault.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get authErrorDefault;

  /// No description provided for @authErrorWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'The password is too weak'**
  String get authErrorWeakPassword;

  /// No description provided for @authErrorEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'An account already exists for this email'**
  String get authErrorEmailInUse;

  /// No description provided for @authErrorInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get authErrorInvalidEmail;

  /// No description provided for @authErrorNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Email/password accounts are not enabled'**
  String get authErrorNotAllowed;

  /// No description provided for @authErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection.'**
  String get authErrorNetwork;

  /// No description provided for @authErrorWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get authErrorWrongPassword;

  /// No description provided for @authErrorUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'No account found for this email'**
  String get authErrorUserNotFound;

  /// No description provided for @authErrorTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get authErrorTooManyRequests;

  /// No description provided for @googleSignInUnsupportedLinux.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In is not supported on Linux desktop. Use email/password.'**
  String get googleSignInUnsupportedLinux;

  /// No description provided for @googleSignInUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In is not supported on this platform.'**
  String get googleSignInUnsupportedPlatform;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @serverProfile.
  ///
  /// In en, this message translates to:
  /// **'Server Profile'**
  String get serverProfile;

  /// No description provided for @deleteChannel.
  ///
  /// In en, this message translates to:
  /// **'Delete Channel'**
  String get deleteChannel;

  /// No description provided for @deleteChannelConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete #{name}? Existing messages stay in history.'**
  String deleteChannelConfirm(String name);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @channelAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Channel already exists'**
  String get channelAlreadyExists;

  /// No description provided for @selectVoiceChannelFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a voice channel first.'**
  String get selectVoiceChannelFirst;

  /// No description provided for @channelNoTextSupport.
  ///
  /// In en, this message translates to:
  /// **'This channel does not support text messages.'**
  String get channelNoTextSupport;

  /// No description provided for @channelNoStickerSupport.
  ///
  /// In en, this message translates to:
  /// **'This channel does not support stickers.'**
  String get channelNoStickerSupport;

  /// No description provided for @useUploadButton.
  ///
  /// In en, this message translates to:
  /// **'Use the upload button to share files in this channel.'**
  String get useUploadButton;

  /// No description provided for @failedToSend.
  ///
  /// In en, this message translates to:
  /// **'Failed to send: {error}'**
  String failedToSend(String error);

  /// No description provided for @couldNotOpenChatRoom.
  ///
  /// In en, this message translates to:
  /// **'Could not open chat room: {error}'**
  String couldNotOpenChatRoom(String error);

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due: {date}'**
  String dueDate(String date);

  /// No description provided for @room.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get room;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @inviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite Code'**
  String get inviteCode;

  /// No description provided for @joinServer.
  ///
  /// In en, this message translates to:
  /// **'Join Server'**
  String get joinServer;

  /// No description provided for @openInShoq.
  ///
  /// In en, this message translates to:
  /// **'Open in Shoq'**
  String get openInShoq;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy Code'**
  String get copyCode;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get codeCopied;

  /// No description provided for @invitePreview.
  ///
  /// In en, this message translates to:
  /// **'Invite Preview'**
  String get invitePreview;

  /// No description provided for @invitePageInstructions.
  ///
  /// In en, this message translates to:
  /// **'Use this invite code in the Shoq app.'**
  String get invitePageInstructions;

  /// No description provided for @inviteStep1.
  ///
  /// In en, this message translates to:
  /// **'Open Shoq.'**
  String get inviteStep1;

  /// No description provided for @inviteStep2.
  ///
  /// In en, this message translates to:
  /// **'Tap Join Server.'**
  String get inviteStep2;

  /// No description provided for @inviteStep3.
  ///
  /// In en, this message translates to:
  /// **'Paste the invite code and confirm.'**
  String get inviteStep3;

  /// No description provided for @invitePageNote.
  ///
  /// In en, this message translates to:
  /// **'This page is for invite links only. If direct opening doesn\'t work, copy the code and join manually in the app.'**
  String get invitePageNote;

  /// No description provided for @qrScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get qrScanTitle;

  /// No description provided for @qrShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Your QR Code'**
  String get qrShareTitle;

  /// No description provided for @muteAudio.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get muteAudio;

  /// No description provided for @unmuteAudio.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmuteAudio;

  /// No description provided for @deafen.
  ///
  /// In en, this message translates to:
  /// **'Deafen'**
  String get deafen;

  /// No description provided for @undeafen.
  ///
  /// In en, this message translates to:
  /// **'Undeafen'**
  String get undeafen;

  /// No description provided for @leaveVoice.
  ///
  /// In en, this message translates to:
  /// **'Leave Voice'**
  String get leaveVoice;

  /// No description provided for @voiceConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get voiceConnecting;

  /// No description provided for @voiceConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get voiceConnected;

  /// No description provided for @voiceDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get voiceDisconnected;

  /// No description provided for @activeVoiceSession.
  ///
  /// In en, this message translates to:
  /// **'Active Voice Session'**
  String get activeVoiceSession;

  /// No description provided for @returnToCall.
  ///
  /// In en, this message translates to:
  /// **'Return to Call'**
  String get returnToCall;

  /// No description provided for @uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploading;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select language'**
  String get selectLanguage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'PT':
            return AppLocalizationsPtPt();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
