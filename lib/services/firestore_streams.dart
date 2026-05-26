import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

extension SafeQuerySnapshots<T extends Object?> on Query<T> {
  Stream<QuerySnapshot<T>> safeSnapshots({
    Duration windowsPollInterval = const Duration(seconds: 2),
  }) {
    if (!Platform.isWindows) {
      return snapshots();
    }
    assert(windowsPollInterval > Duration.zero);
    // The Windows Firestore listener can emit platform-channel messages from a
    // background thread. Polling avoids that native listener path while still
    // keeping desktop UI reasonably fresh.
    return _distinctStream(
      _pollQuerySnapshots(this, windowsPollInterval),
      _queryDigest,
    );
  }
}

extension SafeDocumentSnapshots<T extends Object?> on DocumentReference<T> {
  Stream<DocumentSnapshot<T>> safeSnapshots({
    Duration windowsPollInterval = const Duration(seconds: 2),
  }) {
    if (!Platform.isWindows) {
      return snapshots();
    }
    assert(windowsPollInterval > Duration.zero);
    return _distinctStream(
      _pollDocumentSnapshots(this, windowsPollInterval),
      _documentDigest,
    );
  }
}

Stream<QuerySnapshot<T>> _pollQuerySnapshots<T extends Object?>(
  Query<T> query,
  Duration interval,
) async* {
  QuerySnapshot<T>? lastSnapshot;

  try {
    final cached = await query.get(const GetOptions(source: Source.cache));
    lastSnapshot = cached;
    yield cached;
  } catch (_) {
    // Empty cache is normal on first desktop launch.
  }

  while (true) {
    try {
      final snapshot = await query.get();
      lastSnapshot = snapshot;
      yield snapshot;
    } catch (e, stack) {
      if (lastSnapshot == null) {
        Error.throwWithStackTrace(e, stack);
      }
      debugPrint('Firestore query poll failed: $e');
    }

    await Future<void>.delayed(interval);
  }
}

Stream<DocumentSnapshot<T>> _pollDocumentSnapshots<T extends Object?>(
  DocumentReference<T> document,
  Duration interval,
) async* {
  DocumentSnapshot<T>? lastSnapshot;

  try {
    final cached = await document.get(const GetOptions(source: Source.cache));
    lastSnapshot = cached;
    yield cached;
  } catch (_) {
    // Empty cache is normal on first desktop launch.
  }

  while (true) {
    try {
      final snapshot = await document.get();
      lastSnapshot = snapshot;
      yield snapshot;
    } catch (e, stack) {
      if (lastSnapshot == null) {
        Error.throwWithStackTrace(e, stack);
      }
      debugPrint('Firestore document poll failed: $e');
    }

    await Future<void>.delayed(interval);
  }
}

Stream<T> _distinctStream<T>(
  Stream<T> source,
  String Function(T value) digestBuilder,
) async* {
  String? previousDigest;
  await for (final value in source) {
    try {
      final digest = digestBuilder(value);
      if (digest == previousDigest) {
        continue;
      }
      previousDigest = digest;
      yield value;
    } catch (e, stack) {
      debugPrint('Firestore snapshot digest failed: $e');
      debugPrint('$stack');
      yield value;
    }
  }
}

String _queryDigest<T extends Object?>(QuerySnapshot<T> snapshot) {
  final docs = snapshot.docs.map(_queryDocumentDigest).join('|');
  return '${snapshot.docs.length}:$docs';
}

String _queryDocumentDigest<T extends Object?>(QueryDocumentSnapshot<T> doc) {
  return '${doc.id}:${_digestAny(doc.data())}';
}

String _documentDigest<T extends Object?>(DocumentSnapshot<T> snapshot) {
  return '${snapshot.id}:${snapshot.exists}:${_digestAny(snapshot.data())}';
}

String _digestAny(Object? value) {
  final normalized = _normalizeForDigest(value);
  return jsonEncode(normalized);
}

Object? _normalizeForDigest(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) {
    return <String, Object>{
      'timestamp': <int>[value.seconds, value.nanoseconds],
    };
  }
  if (value is GeoPoint) {
    return <String, Object>{
      'geo': <double>[value.latitude, value.longitude],
    };
  }
  if (value is DocumentReference) {
    return <String, String>{'ref': value.path};
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort(
        (a, b) => a.key.toString().toLowerCase().compareTo(
          b.key.toString().toLowerCase(),
        ),
      );
    return <String, Object?>{
      for (final entry in entries)
        entry.key.toString(): _normalizeForDigest(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_normalizeForDigest).toList();
  }
  return value;
}
