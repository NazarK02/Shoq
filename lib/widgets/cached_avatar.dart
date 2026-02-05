import 'package:flutter/material.dart';

/// Avatar that shows a loading placeholder while image loads
/// Uses Flutter's built-in image caching
class CachedAvatar extends StatelessWidget {
  final String? photoUrl;
  final String fallbackText;
  final double radius;
  final Color? backgroundColor;

  const CachedAvatar({
    super.key,
    this.photoUrl,
    required this.fallbackText,
    this.radius = 20,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null || photoUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Colors.grey[300],
        child: Text(
          fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: radius * 0.8,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey[200],
      child: ClipOval(
        child: Image.network(
          photoUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          // Show loading indicator
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            
            return Center(
              child: SizedBox(
                width: radius * 0.8,
                height: radius * 0.8,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          // Show fallback text on error
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Text(
                fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: radius * 0.8,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}