/// Chat mesaj modeli
class AIMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime timestamp;

  AIMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// JSON'a dönüştür (Groq API için)
  Map<String, String> toJson() => {
        'role': role,
        'content': content,
      };

  /// JSON'dan oluştur
  factory AIMessage.fromJson(Map<String, dynamic> json) {
    return AIMessage(
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }

  /// Map'e dönüştür (veritabanı için)
  Map<String, dynamic> toMap() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Map'ten oluştur
  factory AIMessage.fromMap(Map<String, dynamic> map) {
    return AIMessage(
      role: map['role'] as String,
      content: map['content'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';

  @override
  String toString() => '$role: $content';
}
