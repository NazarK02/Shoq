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

        return Positioned(
          left: 12,
          right: 12,
          top: 10,
          child: SafeArea(
            bottom: false,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => sessionService.returnToSession(navigatorKey),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              session.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        actionText,
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
        );
      },
    );
  }
}
