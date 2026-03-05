import 'package:flutter/material.dart';

enum ActiveSessionKind { call, voice }

class ActiveSessionState {
  final ActiveSessionKind kind;
  final String sessionId;
  final String title;
  final String subtitle;
  final Route<dynamic>? route;

  const ActiveSessionState({
    required this.kind,
    required this.sessionId,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  ActiveSessionState copyWith({
    ActiveSessionKind? kind,
    String? sessionId,
    String? title,
    String? subtitle,
    Route<dynamic>? route,
  }) {
    return ActiveSessionState(
      kind: kind ?? this.kind,
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      route: route ?? this.route,
    );
  }
}

class ActiveSessionService extends ChangeNotifier {
  static final ActiveSessionService _instance =
      ActiveSessionService._internal();
  factory ActiveSessionService() => _instance;
  ActiveSessionService._internal();

  ActiveSessionState? _session;

  ActiveSessionState? get session => _session;

  void setCallSession({
    required String sessionId,
    required String peerName,
    required bool isVideo,
  }) {
    final normalizedName = peerName.trim().isNotEmpty
        ? peerName.trim()
        : 'User';
    final route = _session?.sessionId == sessionId ? _session?.route : null;
    _session = ActiveSessionState(
      kind: ActiveSessionKind.call,
      sessionId: sessionId,
      title: isVideo ? 'Video call in progress' : 'Audio call in progress',
      subtitle: normalizedName,
      route: route,
    );
    notifyListeners();
  }

  void setVoiceSession({
    required String sessionId,
    required String conversationTitle,
    required String channelName,
  }) {
    final conversation = conversationTitle.trim().isNotEmpty
        ? conversationTitle.trim()
        : 'Server';
    final channel = channelName.trim().isNotEmpty
        ? channelName.trim()
        : 'voice';
    final route = _session?.sessionId == sessionId ? _session?.route : null;
    _session = ActiveSessionState(
      kind: ActiveSessionKind.voice,
      sessionId: sessionId,
      title: 'Voice channel connected',
      subtitle: '$conversation | #$channel',
      route: route,
    );
    notifyListeners();
  }

  void bindRoute(BuildContext context, {required String sessionId}) {
    final current = _session;
    if (current == null || current.sessionId != sessionId) return;
    final route = ModalRoute.of(context);
    if (route == null || identical(route, current.route)) return;
    _session = current.copyWith(route: route);
    notifyListeners();
  }

  void clearSession({String? sessionId}) {
    final current = _session;
    if (current == null) return;
    if (sessionId != null && current.sessionId != sessionId) return;
    _session = null;
    notifyListeners();
  }

  void returnToSession(GlobalKey<NavigatorState> navigatorKey) {
    final current = _session;
    if (current == null) return;

    final targetRoute = current.route;
    final navigator = navigatorKey.currentState;
    if (navigator == null || targetRoute == null || !targetRoute.isActive) {
      clearSession(sessionId: current.sessionId);
      return;
    }

    navigator.popUntil((route) => identical(route, targetRoute));
  }
}
