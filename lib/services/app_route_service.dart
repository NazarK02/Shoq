import 'package:flutter/material.dart';

class AppRouteService extends NavigatorObserver with ChangeNotifier {
  static final AppRouteService _instance = AppRouteService._internal();
  factory AppRouteService() => _instance;
  AppRouteService._internal();

  Route<dynamic>? _currentRoute;

  Route<dynamic>? get currentRoute => _currentRoute;

  void _setCurrentRoute(Route<dynamic>? route) {
    if (identical(_currentRoute, route)) return;
    _currentRoute = route;
    notifyListeners();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _setCurrentRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _setCurrentRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _setCurrentRoute(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (identical(_currentRoute, route)) {
      _setCurrentRoute(previousRoute);
    }
  }
}
