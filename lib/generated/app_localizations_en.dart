// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Shoq';

  @override
  String get appTagline => 'Private by design.';

  @override
  String get lightMode => 'Light Mode';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get darkThemeEnabled => 'Dark theme enabled';

  @override
  String get lightThemeEnabled => 'Light theme enabled';

  @override
  String get uiSize => 'UI Size';

  @override
  String uiSizeSubtitle(int percent) {
    return '$percent% · Bigger or smaller interface';
  }

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get reduceMotionSubtitle =>
      'Use less animation for smoother navigation';

  @override
  String get linkPreviews => 'Link previews';

  @override
  String get linkPreviewsSubtitle =>
      'Show website and YouTube previews in messages';

  @override
  String get sectionGeneral => 'General';

  @override
  String get sectionPreferences => 'Preferences';

  @override
  String get sectionSupport => 'Support';

  @override
  String get sectionChat => 'Chat';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacySubtitle => 'Control your privacy settings';

  @override
  String get security => 'Security';

  @override
  String get securitySubtitle => 'Password and authentication';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePortuguese => 'Português (Portugal)';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get helpSupport => 'Help & Support';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get languageComingSoon => 'Language settings coming soon';

  @override
  String get helpSupportComingSoon => 'Help & Support coming soon';

  @override
  String get termsComingSoon => 'Terms of Service coming soon';

  @override
  String get privacySettingsComingSoon => 'Privacy settings coming soon';

  @override
  String get securitySettingsComingSoon => 'Security settings coming soon';

  @override
  String get signIn => 'Sign In';

  @override
  String get signUp => 'Sign Up';

  @override
  String get signOut => 'Sign Out';

  @override
  String get createAccount => 'Create Account';

  @override
  String get signUpToGetStarted => 'Sign up to get started';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get fullName => 'Full Name';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get orSeparator => 'or';

  @override
  String get acceptTerms => 'I accept the Terms and Conditions';

  @override
  String get pleaseAcceptTerms => 'Please accept the Terms and Conditions';

  @override
  String get pleaseEnterName => 'Please enter your name';

  @override
  String get pleaseEnterEmail => 'Please enter your email';

  @override
  String get pleaseEnterPassword => 'Please enter a password';

  @override
  String get passwordTooShort => 'Password must be at least 6 characters';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get pleaseConfirmPassword => 'Please confirm your password';

  @override
  String get verificationEmailSent =>
      'Verification email sent! Check your inbox.';

  @override
  String get resendVerificationEmail => 'Resend verification email';

  @override
  String get emailNotVerifiedTitle => 'Verify your email';

  @override
  String get emailNotVerifiedBody =>
      'A verification link was sent to your email address. Please check your inbox and click the link to continue.';

  @override
  String get authErrorDefault => 'An error occurred';

  @override
  String get authErrorWeakPassword => 'The password is too weak';

  @override
  String get authErrorEmailInUse => 'An account already exists for this email';

  @override
  String get authErrorInvalidEmail => 'Invalid email address';

  @override
  String get authErrorNotAllowed => 'Email/password accounts are not enabled';

  @override
  String get authErrorNetwork => 'Network error. Please check your connection.';

  @override
  String get authErrorWrongPassword => 'Incorrect password';

  @override
  String get authErrorUserNotFound => 'No account found for this email';

  @override
  String get authErrorTooManyRequests =>
      'Too many attempts. Please try again later.';

  @override
  String get googleSignInUnsupportedLinux =>
      'Google Sign-In is not supported on Linux desktop. Use email/password.';

  @override
  String get googleSignInUnsupportedPlatform =>
      'Google Sign-In is not supported on this platform.';

  @override
  String get channels => 'Channels';

  @override
  String get serverProfile => 'Server Profile';

  @override
  String get deleteChannel => 'Delete Channel';

  @override
  String deleteChannelConfirm(String name) {
    return 'Delete #$name? Existing messages stay in history.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get channelAlreadyExists => 'Channel already exists';

  @override
  String get selectVoiceChannelFirst => 'Select a voice channel first.';

  @override
  String get channelNoTextSupport =>
      'This channel does not support text messages.';

  @override
  String get channelNoStickerSupport =>
      'This channel does not support stickers.';

  @override
  String get useUploadButton =>
      'Use the upload button to share files in this channel.';

  @override
  String failedToSend(String error) {
    return 'Failed to send: $error';
  }

  @override
  String couldNotOpenChatRoom(String error) {
    return 'Could not open chat room: $error';
  }

  @override
  String dueDate(String date) {
    return 'Due: $date';
  }

  @override
  String get room => 'Room';

  @override
  String get members => 'Members';

  @override
  String get inviteCode => 'Invite Code';

  @override
  String get joinServer => 'Join Server';

  @override
  String get openInShoq => 'Open in Shoq';

  @override
  String get copyCode => 'Copy Code';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get invitePreview => 'Invite Preview';

  @override
  String get invitePageInstructions => 'Use this invite code in the Shoq app.';

  @override
  String get inviteStep1 => 'Open Shoq.';

  @override
  String get inviteStep2 => 'Tap Join Server.';

  @override
  String get inviteStep3 => 'Paste the invite code and confirm.';

  @override
  String get invitePageNote =>
      'This page is for invite links only. If direct opening doesn\'t work, copy the code and join manually in the app.';

  @override
  String get qrScanTitle => 'Scan QR Code';

  @override
  String get qrShareTitle => 'Your QR Code';

  @override
  String get muteAudio => 'Mute';

  @override
  String get unmuteAudio => 'Unmute';

  @override
  String get deafen => 'Deafen';

  @override
  String get undeafen => 'Undeafen';

  @override
  String get leaveVoice => 'Leave Voice';

  @override
  String get voiceConnecting => 'Connecting…';

  @override
  String get voiceConnected => 'Connected';

  @override
  String get voiceDisconnected => 'Disconnected';

  @override
  String get activeVoiceSession => 'Active Voice Session';

  @override
  String get returnToCall => 'Return to Call';

  @override
  String get uploading => 'Uploading…';

  @override
  String get systemDefault => 'System default';

  @override
  String get selectLanguage => 'Select language';
}
