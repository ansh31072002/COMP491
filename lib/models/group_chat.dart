class GroupChat {
  final String id;
  final String name;
  final String description;
  final String createdBy;
  final List<String> members;
  final DateTime createdAt;
  final String? lastMessage;
  final DateTime? lastMessageTime;

  GroupChat({
    required this.id,
    required this.name,
    required this.description,
    required this.createdBy,
    required this.members,
    required this.createdAt,
    this.lastMessage,
    this.lastMessageTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'members': members,
      'createdAt': createdAt,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime,
    };
  }

  factory GroupChat.fromMap(Map<String, dynamic> map) {
    return GroupChat(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      createdBy: map['createdBy'] ?? '',
      members: List<String>.from(map['members'] ?? []),
      createdAt: map['createdAt']?.toDate() ?? DateTime.now(),
      lastMessage: map['lastMessage'],
      lastMessageTime: map['lastMessageTime']?.toDate(),
    );
  }
}
