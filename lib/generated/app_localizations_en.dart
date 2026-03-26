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

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionNotifications => 'Notifications';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get friendRequestsTitle => 'Friend Requests';

  @override
  String get friendRequestsSubtitle =>
      'Get notified when someone sends you a friend request';

  @override
  String get messagesTitle => 'Messages';

  @override
  String get messagesSubtitle => 'Get notified when you receive a new message';

  @override
  String get textSize => 'Text Size';

  @override
  String textSizeSubtitle(int percent) {
    return '$percent% - Text size multiplier';
  }

  @override
  String get welcomeBack => 'Welcome Back';

  @override
  String get signInToContinue => 'Sign in to continue';

  @override
  String get rememberMe => 'Remember me';

  @override
  String get dontHaveAnAccount => 'Don\'t have an account? ';

  @override
  String get alreadyHaveAnAccount => 'Already have an account? ';

  @override
  String get acceptTermsPrefix => 'I accept the ';

  @override
  String get couldNotOpenLink => 'Could not open link';

  @override
  String get accountCreatedVerificationSent =>
      'Account created. Verification email sent. Please verify from the screen.';

  @override
  String get verifyYourEmail => 'Verify Your Email';

  @override
  String get verificationEmailSentTo => 'We sent a verification email to:';

  @override
  String get verificationWindowsHint =>
      'Auto-check runs in the background on Windows. If it doesn\'t update, tap \"I\'ve Verified My Email\".';

  @override
  String resendInSeconds(int seconds) {
    return 'Resend in $seconds seconds';
  }

  @override
  String get emailNotVerifiedYet =>
      'Email not verified yet. Please check your inbox.';

  @override
  String get iveVerifiedMyEmail => 'I\'ve Verified My Email';

  @override
  String logoutFailed(String error) {
    return 'Logout failed: $error';
  }

  @override
  String get createAction => 'Create';

  @override
  String get createFolder => 'Create folder';

  @override
  String get createGroupChat => 'Create group chat';

  @override
  String get createServer => 'Create server';

  @override
  String get folderName => 'Folder name';

  @override
  String get folderNameHint => 'Work, Family, Gaming...';

  @override
  String get folderAlreadyExists => 'Folder already exists';

  @override
  String get defaultUser => 'User';

  @override
  String get addFriendsFirstToCreateRoom =>
      'Add friends first to create a room';

  @override
  String get createGroup => 'Create group';

  @override
  String get groupName => 'Group name';

  @override
  String get groupNameHint => 'Weekend project';

  @override
  String get selectMembers => 'Select members';

  @override
  String get selectAtLeastOneMember => 'Select at least one member';

  @override
  String get serverName => 'Server name';

  @override
  String get serverNameHint => 'My server';

  @override
  String get serverIconPersonalizeHint =>
      'You can personalize the server icon from Server profile.';

  @override
  String get inviteLinkOrCode => 'Invite link or code';

  @override
  String get pasteInviteLinkOrServerCode => 'Paste invite link or server code';

  @override
  String get enterValidInviteLinkOrCode => 'Enter a valid invite link or code';

  @override
  String get join => 'Join';

  @override
  String get inviteLinkInvalid => 'Invite link is invalid';

  @override
  String get inviteLinkExpired => 'This invite link has expired';

  @override
  String get serverNotFoundForInvite => 'Server not found for this invite';

  @override
  String get permissionDeniedJoiningServer =>
      'Permission denied while joining server. Update Firestore rules for server invites and conversation joins.';

  @override
  String couldNotJoinServer(String error) {
    return 'Could not join server: $error';
  }

  @override
  String couldNotJoinServerCode(String code) {
    return 'Could not join server ($code)';
  }

  @override
  String get atLeastTwoMembersRequired => 'At least 2 members are required';

  @override
  String get permissionDeniedCreatingRoom =>
      'Permission denied while creating room. Check Firestore rules for conversations.';

  @override
  String failedToCreateRoom(String error) {
    return 'Failed to create room: $error';
  }

  @override
  String failedToCreateRoomCode(String code) {
    return 'Failed to create room ($code)';
  }

  @override
  String moveConversation(String name) {
    return 'Move \"$name\"';
  }

  @override
  String get allChats => 'All chats';

  @override
  String get createFolderFirst => 'Create a folder first';

  @override
  String get groupLabel => 'Group';

  @override
  String get serverLabel => 'Server';

  @override
  String get groupChat => 'Group chat';

  @override
  String get searchChats => 'Search chats...';

  @override
  String get folder => 'Folder';

  @override
  String get myProfile => 'My Profile';

  @override
  String get myFriends => 'My Friends';

  @override
  String get about => 'About';

  @override
  String get aboutDescription =>
      'Secure messaging app with end-to-end encryption.';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String genericError(String error) {
    return 'Error: $error';
  }

  @override
  String get chatOptions => 'Chat options';

  @override
  String get moveToFolder => 'Move to folder';

  @override
  String removeFromFolder(String name) {
    return 'Remove from $name';
  }

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get addFriendsToStartChatting => 'Add friends to start chatting';

  @override
  String get addFriends => 'Add Friends';

  @override
  String noChatsInFolder(String name) {
    return 'No chats in $name';
  }

  @override
  String get moveChatHereHint =>
      'Move a chat here from the menu on any conversation.';

  @override
  String get yesterday => 'Yesterday';

  @override
  String daysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get sentAMessage => 'Sent a message';

  @override
  String get startChatting => 'Start chatting';

  @override
  String couldNotOpenInvite(String error) {
    return 'Could not open invite: $error';
  }

  @override
  String get friendsTitle => 'Friends';

  @override
  String get myQrCode => 'My QR Code';

  @override
  String get addFriend => 'Add Friend';

  @override
  String get requestsTitle => 'Requests';

  @override
  String get blockedTitle => 'Blocked';

  @override
  String get searchFriends => 'Search friends';

  @override
  String get noFriendsYet => 'No friends yet';

  @override
  String get sendFriendRequestsToConnect => 'Send friend requests to connect';

  @override
  String noFriendsMatch(String filter) {
    return 'No friends match \"$filter\"';
  }

  @override
  String get noFriendRequests => 'No friend requests';

  @override
  String get noBlockedUsers => 'No blocked users';

  @override
  String get unblock => 'Unblock';

  @override
  String get invalidUserData => 'Invalid user data';

  @override
  String get cannotAddYourself => 'You cannot add yourself';

  @override
  String get alreadyFriends => 'Already friends';

  @override
  String get friendRequestAlreadySent => 'Friend request already sent';

  @override
  String friendRequestSentTo(String name) {
    return 'Friend request sent to $name!';
  }

  @override
  String get friendRequestAccepted => 'Friend request accepted!';

  @override
  String get friendRequestDenied => 'Friend request denied';

  @override
  String get userBlocked => 'User blocked';

  @override
  String get userUnblocked => 'User unblocked';

  @override
  String get removeFriend => 'Remove Friend';

  @override
  String removeFriendConfirm(String name) {
    return 'Are you sure you want to remove $name from your friends?';
  }

  @override
  String get remove => 'Remove';

  @override
  String get friendRemoved => 'Friend removed';

  @override
  String get removeFriendMenu => 'Remove Friend';

  @override
  String get block => 'Block';
}
