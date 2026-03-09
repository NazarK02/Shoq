import 'package:flutter/material.dart';

import '../services/active_session_service.dart';
import '../services/app_route_service.dart';

class ActiveSessionBanner extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const ActiveSessionBanner({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    final sessionService = ActiveSessionService();
    final routeService = AppRouteService();

    return AnimatedBuilder(
      animation: Listenable.merge([sessionService, routeService]),
      builder: (context, child) {
        final session = sessionService.session;
        if (session == null) return const SizedBox.shrink();
        if (session.route == null) return const SizedBox.shrink();

        final currentRoute = routeService.currentRoute;
        if (identical(currentRoute, session.route)) {
          return const SizedBox.shrink();
        }

        final isCall = session.kind == ActiveSessionKind.call;
        final icon = isCall ? Icons.call : Icons.volume_up;
        final actionText = isCall ? 'Return to call' : 'Return to voice';

        final topOffset = MediaQuery.of(context).padding.top + 62;
        final label = isCall ? 'Call' : 'Voice';

        return Positioned(
          right: 8,
          top: topOffset,
          child: SafeArea(
            left: false,
            bottom: false,
            child: Tooltip(
              message: '${session.title}\n${session.subtitle}\n$actionText',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => sessionService.returnToSession(navigatorKey),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
