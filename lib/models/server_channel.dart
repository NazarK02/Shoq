class ServerChannelType {
  static const String text = 'text';
  static const String voice = 'voice';
  static const String forum = 'forum';
  static const String file = 'file';
  static const String assignments = 'assignments';

  static const List<String> values = [text, voice, forum, file, assignments];

  static String normalize(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    if (values.contains(value)) return value;
    return text;
  }

  static String label(String type) {
    switch (normalize(type)) {
      case voice:
        return 'Voice';
      case forum:
        return 'Forum';
      case file:
        return 'Files';
      case assignments:
        return 'Assignments';
      case text:
      default:
        return 'Text';
    }
  }

  static bool supportsTextComposer(String type) {
    final normalized = normalize(type);
    return normalized == text ||
        normalized == forum ||
        normalized == assignments;
  }
}

class ServerChannel {
  final String id;
  final String name;
  final String type;

  const ServerChannel({
    required this.id,
    required this.name,
    this.type = ServerChannelType.text,
  });

  static const String generalId = 'general';
  static const ServerChannel general = ServerChannel(
    id: generalId,
    name: 'general',
    type: ServerChannelType.text,
  );

  factory ServerChannel.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString().trim() ?? '';
    final name = map['name']?.toString().trim() ?? '';
    final type = ServerChannelType.normalize(map['type']?.toString());
    return ServerChannel(id: id, name: name, type: type);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'id': id, 'name': name, 'type': type};
  }
}
