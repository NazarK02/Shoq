import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatFolder {
  final String id;
  final String name;
  final int colorValue;

  const ChatFolder({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'colorValue': colorValue};
  }

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final colorRaw = json['colorValue'];
    final colorValue = colorRaw is int
        ? colorRaw
        : int.tryParse(colorRaw?.toString() ?? '') ?? Colors.blue.toARGB32();
    return ChatFolder(id: id, name: name, colorValue: colorValue);
  }
}

class ChatFolderState {
  final List<ChatFolder> folders;
  final Map<String, String> assignments;

  const ChatFolderState({required this.folders, required this.assignments});
}

class ChatFolderService {
  static final ChatFolderService _instance = ChatFolderService._internal();
  factory ChatFolderService() => _instance;
  ChatFolderService._internal();

  Future<ChatFolderState> loadForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final folderRaw = prefs.getString('chat_folders_$uid');
    final assignmentRaw = prefs.getString('chat_folder_assignments_$uid');

    final folders = <ChatFolder>[];
    if (folderRaw != null) {
      try {
        final decoded = jsonDecode(folderRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final folder = ChatFolder.fromJson(Map<String, dynamic>.from(item));
            if (folder.id.isEmpty || folder.name.isEmpty) continue;
            folders.add(folder);
          }
        }
      } catch (_) {}
    }

    final assignments = <String, String>{};
    if (assignmentRaw != null) {
      try {
        final decoded = jsonDecode(assignmentRaw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final conversationId = key.toString().trim();
            final folderId = value?.toString().trim() ?? '';
            if (conversationId.isEmpty || folderId.isEmpty) return;
            assignments[conversationId] = folderId;
          });
        }
      } catch (_) {}
    }

    if (folders.isEmpty && assignments.isNotEmpty) {
      return const ChatFolderState(folders: [], assignments: {});
    }

    final validFolderIds = folders.map((f) => f.id).toSet();
    assignments.removeWhere(
      (_, folderId) => !validFolderIds.contains(folderId),
    );

    return ChatFolderState(folders: folders, assignments: assignments);
  }

  Future<void> saveForUser(
    String uid, {
    required List<ChatFolder> folders,
    required Map<String, String> assignments,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final uniqueFolders = <String, ChatFolder>{};
    for (final folder in folders) {
      if (folder.id.trim().isEmpty || folder.name.trim().isEmpty) continue;
      uniqueFolders[folder.id] = folder;
    }

    final folderPayload = uniqueFolders.values.map((f) => f.toJson()).toList();
    final validFolderIds = uniqueFolders.keys.toSet();
    final assignmentPayload = <String, String>{};
    assignments.forEach((conversationId, folderId) {
      final conversationKey = conversationId.trim();
      final assignedFolder = folderId.trim();
      if (conversationKey.isEmpty || assignedFolder.isEmpty) return;
      if (!validFolderIds.contains(assignedFolder)) return;
      assignmentPayload[conversationKey] = assignedFolder;
    });

    await prefs.setString('chat_folders_$uid', jsonEncode(folderPayload));
    await prefs.setString(
      'chat_folder_assignments_$uid',
      jsonEncode(assignmentPayload),
    );
  }
}
