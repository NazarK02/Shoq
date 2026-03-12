import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

extension SafeQuerySnapshots<T extends Object?> on Query<T> {
  Stream<QuerySnapshot<T>> safeSnapshots({
    Duration windowsPollInterval = const Duration(milliseconds: 650),
  }) {
    if (!Platform.isWindows) {
      return snapshots();
    }
    return _windowsQuerySnapshots(this, windowsPollInterval);
  }
}

extension SafeDocumentSnapshots<T extends Object?> on DocumentReference<T> {
  Stream<DocumentSnapshot<T>> safeSnapshots({
    Duration windowsPollInterval = const Duration(milliseconds: 650),
  }) {
    if (!Platform.isWindows) {
      return snapshots();
    }
    return _windowsDocumentSnapshots(this, windowsPollInterval);
  }
}

Stream<QuerySnapshot<T>> _windowsQuerySnapshots<T extends Object?>(
  Query<T> query,
  Duration interval,
) async* {
  String? previousDigest;
  while (true) {
    try {
      final snapshot = await query.get(const GetOptions(source: Source.server));
      final digest = _queryDigest(snapshot);
      if (digest != previousDigest) {
        previousDigest = digest;
        yield snapshot;
      }
    } catch (e) {
      debugPrint('Firestore query polling failed: $e');
    }
    await Future<void>.delayed(interval);
  }
}

Stream<DocumentSnapshot<T>> _windowsDocumentSnapshots<T extends Object?>(
  DocumentReference<T> document,
  Duration interval,
) async* {
  String? previousDigest;
  while (true) {
    try {
      final snapshot =
          await document.get(const GetOptions(source: Source.server));
      final digest = _documentDigest(snapshot);
      if (digest != previousDigest) {
        previousDigest = digest;
        yield snapshot;
      }
    } catch (e) {
      debugPrint('Firestore document polling failed: $e');
    }
    await Future<void>.delayed(interval);
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
