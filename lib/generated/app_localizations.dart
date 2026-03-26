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

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get sectionNotifications;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get sectionAppearance;

  /// No description provided for @friendRequestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Friend Requests'**
  String get friendRequestsTitle;

  /// No description provided for @friendRequestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get notified when someone sends you a friend request'**
  String get friendRequestsSubtitle;

  /// No description provided for @messagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messagesTitle;

  /// No description provided for @messagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get notified when you receive a new message'**
  String get messagesSubtitle;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text Size'**
  String get textSize;

  /// No description provided for @textSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{percent}% - Text size multiplier'**
  String textSizeSubtitle(int percent);

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @signInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get signInToContinue;

  /// No description provided for @rememberMe.
  ///
  /// In en, this message translates to:
  /// **'Remember me'**
  String get rememberMe;

  /// No description provided for @dontHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get dontHaveAnAccount;

  /// No description provided for @alreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get alreadyHaveAnAccount;

  /// No description provided for @acceptTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'I accept the '**
  String get acceptTermsPrefix;

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get couldNotOpenLink;

  /// No description provided for @accountCreatedVerificationSent.
  ///
  /// In en, this message translates to:
  /// **'Account created. Verification email sent. Please verify from the screen.'**
  String get accountCreatedVerificationSent;

  /// No description provided for @verifyYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Email'**
  String get verifyYourEmail;

  /// No description provided for @verificationEmailSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a verification email to:'**
  String get verificationEmailSentTo;

  /// No description provided for @verificationWindowsHint.
  ///
  /// In en, this message translates to:
  /// **'Auto-check runs in the background on Windows. If it doesn\'t update, tap \"I\'ve Verified My Email\".'**
  String get verificationWindowsHint;

  /// No description provided for @resendInSeconds.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds} seconds'**
  String resendInSeconds(int seconds);

  /// No description provided for @emailNotVerifiedYet.
  ///
  /// In en, this message translates to:
  /// **'Email not verified yet. Please check your inbox.'**
  String get emailNotVerifiedYet;

  /// No description provided for @iveVerifiedMyEmail.
  ///
  /// In en, this message translates to:
  /// **'I\'ve Verified My Email'**
  String get iveVerifiedMyEmail;

  /// No description provided for @logoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Logout failed: {error}'**
  String logoutFailed(String error);

  /// No description provided for @createAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createAction;

  /// No description provided for @createFolder.
  ///
  /// In en, this message translates to:
  /// **'Create folder'**
  String get createFolder;

  /// No description provided for @createGroupChat.
  ///
  /// In en, this message translates to:
  /// **'Create group chat'**
  String get createGroupChat;

  /// No description provided for @createServer.
  ///
  /// In en, this message translates to:
  /// **'Create server'**
  String get createServer;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @folderNameHint.
  ///
  /// In en, this message translates to:
  /// **'Work, Family, Gaming...'**
  String get folderNameHint;

  /// No description provided for @folderAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Folder already exists'**
  String get folderAlreadyExists;

  /// No description provided for @defaultUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get defaultUser;

  /// No description provided for @addFriendsFirstToCreateRoom.
  ///
  /// In en, this message translates to:
  /// **'Add friends first to create a room'**
  String get addFriendsFirstToCreateRoom;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroup;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Weekend project'**
  String get groupNameHint;

  /// No description provided for @selectMembers.
  ///
  /// In en, this message translates to:
  /// **'Select members'**
  String get selectMembers;

  /// No description provided for @selectAtLeastOneMember.
  ///
  /// In en, this message translates to:
  /// **'Select at least one member'**
  String get selectAtLeastOneMember;

  /// No description provided for @serverName.
  ///
  /// In en, this message translates to:
  /// **'Server name'**
  String get serverName;

  /// No description provided for @serverNameHint.
  ///
  /// In en, this message translates to:
  /// **'My server'**
  String get serverNameHint;

  /// No description provided for @serverIconPersonalizeHint.
  ///
  /// In en, this message translates to:
  /// **'You can personalize the server icon from Server profile.'**
  String get serverIconPersonalizeHint;

  /// No description provided for @inviteLinkOrCode.
  ///
  /// In en, this message translates to:
  /// **'Invite link or code'**
  String get inviteLinkOrCode;

  /// No description provided for @pasteInviteLinkOrServerCode.
  ///
  /// In en, this message translates to:
  /// **'Paste invite link or server code'**
  String get pasteInviteLinkOrServerCode;

  /// No description provided for @enterValidInviteLinkOrCode.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid invite link or code'**
  String get enterValidInviteLinkOrCode;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @inviteLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invite link is invalid'**
  String get inviteLinkInvalid;

  /// No description provided for @inviteLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'This invite link has expired'**
  String get inviteLinkExpired;

  /// No description provided for @serverNotFoundForInvite.
  ///
  /// In en, this message translates to:
  /// **'Server not found for this invite'**
  String get serverNotFoundForInvite;

  /// No description provided for @permissionDeniedJoiningServer.
  ///
  /// In en, this message translates to:
  /// **'Permission denied while joining server. Update Firestore rules for server invites and conversation joins.'**
  String get permissionDeniedJoiningServer;

  /// No description provided for @couldNotJoinServer.
  ///
  /// In en, this message translates to:
  /// **'Could not join server: {error}'**
  String couldNotJoinServer(String error);

  /// No description provided for @couldNotJoinServerCode.
  ///
  /// In en, this message translates to:
  /// **'Could not join server ({code})'**
  String couldNotJoinServerCode(String code);

  /// No description provided for @atLeastTwoMembersRequired.
  ///
  /// In en, this message translates to:
  /// **'At least 2 members are required'**
  String get atLeastTwoMembersRequired;

  /// No description provided for @permissionDeniedCreatingRoom.
  ///
  /// In en, this message translates to:
  /// **'Permission denied while creating room. Check Firestore rules for conversations.'**
  String get permissionDeniedCreatingRoom;

  /// No description provided for @failedToCreateRoom.
  ///
  /// In en, this message translates to:
  /// **'Failed to create room: {error}'**
  String failedToCreateRoom(String error);

  /// No description provided for @failedToCreateRoomCode.
  ///
  /// In en, this message translates to:
  /// **'Failed to create room ({code})'**
  String failedToCreateRoomCode(String code);

  /// No description provided for @moveConversation.
  ///
  /// In en, this message translates to:
  /// **'Move \"{name}\"'**
  String moveConversation(String name);

  /// No description provided for @allChats.
  ///
  /// In en, this message translates to:
  /// **'All chats'**
  String get allChats;

  /// No description provided for @createFolderFirst.
  ///
  /// In en, this message translates to:
  /// **'Create a folder first'**
  String get createFolderFirst;

  /// No description provided for @groupLabel.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get groupLabel;

  /// No description provided for @serverLabel.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get serverLabel;

  /// No description provided for @groupChat.
  ///
  /// In en, this message translates to:
  /// **'Group chat'**
  String get groupChat;

  /// No description provided for @searchChats.
  ///
  /// In en, this message translates to:
  /// **'Search chats...'**
  String get searchChats;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @myProfile.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get myProfile;

  /// No description provided for @myFriends.
  ///
  /// In en, this message translates to:
  /// **'My Friends'**
  String get myFriends;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Secure messaging app with end-to-end encryption.'**
  String get aboutDescription;

  /// No description provided for @notLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get notLoggedIn;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String genericError(String error);

  /// No description provided for @chatOptions.
  ///
  /// In en, this message translates to:
  /// **'Chat options'**
  String get chatOptions;

  /// No description provided for @moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get moveToFolder;

  /// No description provided for @removeFromFolder.
  ///
  /// In en, this message translates to:
  /// **'Remove from {name}'**
  String removeFromFolder(String name);

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @addFriendsToStartChatting.
  ///
  /// In en, this message translates to:
  /// **'Add friends to start chatting'**
  String get addFriendsToStartChatting;

  /// No description provided for @addFriends.
  ///
  /// In en, this message translates to:
  /// **'Add Friends'**
  String get addFriends;

  /// No description provided for @noChatsInFolder.
  ///
  /// In en, this message translates to:
  /// **'No chats in {name}'**
  String noChatsInFolder(String name);

  /// No description provided for @moveChatHereHint.
  ///
  /// In en, this message translates to:
  /// **'Move a chat here from the menu on any conversation.'**
  String get moveChatHereHint;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String daysAgo(int days);

  /// No description provided for @sentAMessage.
  ///
  /// In en, this message translates to:
  /// **'Sent a message'**
  String get sentAMessage;

  /// No description provided for @startChatting.
  ///
  /// In en, this message translates to:
  /// **'Start chatting'**
  String get startChatting;

  /// No description provided for @couldNotOpenInvite.
  ///
  /// In en, this message translates to:
  /// **'Could not open invite: {error}'**
  String couldNotOpenInvite(String error);

  /// No description provided for @friendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friendsTitle;

  /// No description provided for @myQrCode.
  ///
  /// In en, this message translates to:
  /// **'My QR Code'**
  String get myQrCode;

  /// No description provided for @addFriend.
  ///
  /// In en, this message translates to:
  /// **'Add Friend'**
  String get addFriend;

  /// No description provided for @requestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requestsTitle;

  /// No description provided for @blockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blockedTitle;

  /// No description provided for @searchFriends.
  ///
  /// In en, this message translates to:
  /// **'Search friends'**
  String get searchFriends;

  /// No description provided for @noFriendsYet.
  ///
  /// In en, this message translates to:
  /// **'No friends yet'**
  String get noFriendsYet;

  /// No description provided for @sendFriendRequestsToConnect.
  ///
  /// In en, this message translates to:
  /// **'Send friend requests to connect'**
  String get sendFriendRequestsToConnect;

  /// No description provided for @noFriendsMatch.
  ///
  /// In en, this message translates to:
  /// **'No friends match \"{filter}\"'**
  String noFriendsMatch(String filter);

  /// No description provided for @noFriendRequests.
  ///
  /// In en, this message translates to:
  /// **'No friend requests'**
  String get noFriendRequests;

  /// No description provided for @noBlockedUsers.
  ///
  /// In en, this message translates to:
  /// **'No blocked users'**
  String get noBlockedUsers;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @invalidUserData.
  ///
  /// In en, this message translates to:
  /// **'Invalid user data'**
  String get invalidUserData;

  /// No description provided for @cannotAddYourself.
  ///
  /// In en, this message translates to:
  /// **'You cannot add yourself'**
  String get cannotAddYourself;

  /// No description provided for @alreadyFriends.
  ///
  /// In en, this message translates to:
  /// **'Already friends'**
  String get alreadyFriends;

  /// No description provided for @friendRequestAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'Friend request already sent'**
  String get friendRequestAlreadySent;

  /// No description provided for @friendRequestSentTo.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent to {name}!'**
  String friendRequestSentTo(String name);

  /// No description provided for @friendRequestAccepted.
  ///
  /// In en, this message translates to:
  /// **'Friend request accepted!'**
  String get friendRequestAccepted;

  /// No description provided for @friendRequestDenied.
  ///
  /// In en, this message translates to:
  /// **'Friend request denied'**
  String get friendRequestDenied;

  /// No description provided for @userBlocked.
  ///
  /// In en, this message translates to:
  /// **'User blocked'**
  String get userBlocked;

  /// No description provided for @userUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User unblocked'**
  String get userUnblocked;

  /// No description provided for @removeFriend.
  ///
  /// In en, this message translates to:
  /// **'Remove Friend'**
  String get removeFriend;

  /// No description provided for @removeFriendConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove {name} from your friends?'**
  String removeFriendConfirm(String name);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @friendRemoved.
  ///
  /// In en, this message translates to:
  /// **'Friend removed'**
  String get friendRemoved;

  /// No description provided for @removeFriendMenu.
  ///
  /// In en, this message translates to:
  /// **'Remove Friend'**
  String get removeFriendMenu;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;
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
