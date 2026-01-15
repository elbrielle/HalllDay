class Session {
  final int id;
  final String name;
  final int elapsed; // Fallback if timestamps unavailable
  final bool overdue;
  final int startMs; // Session start (Unix ms) - for accurate sync
  final int serverTimeMs; // Server time when response was generated (Unix ms)

  Session({
    required this.id,
    required this.name,
    required this.elapsed,
    required this.overdue,
    required this.startMs,
    required this.serverTimeMs,
  });

  factory Session.fromJson(Map<String, dynamic> json, {int serverTimeMs = 0}) {
    return Session(
      id: json['id'] is int ? json['id'] : 0,
      name: json['name'] ?? 'Unknown',
      elapsed: json['elapsed'] is int ? json['elapsed'] : 0,
      overdue: json['overdue'] ?? false,
      startMs: json['start_ms'] is int ? json['start_ms'] : 0,
      serverTimeMs: serverTimeMs,
    );
  }

  /// Elapsed seconds at the moment server generated the response
  /// This is the SAME for all clients, regardless of when they polled
  int get serverElapsedAtResponse {
    if (startMs == 0 || serverTimeMs == 0) return elapsed;
    return ((serverTimeMs - startMs) / 1000).floor();
  }

  /// Get current elapsed: serverElapsed + local seconds since we received data
  int getCurrentElapsed(int localSecondsSincePoll) {
    return serverElapsedAtResponse + localSecondsSincePoll;
  }

  /// Format current timer text
  String getCurrentTimerText(int localSecondsSincePoll) {
    final int totalSeconds = getCurrentElapsed(localSecondsSincePoll);
    final int minutes = (totalSeconds / 60).floor();
    final int secs = totalSeconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  // Aliases for compatibility
  bool get isOverdue => overdue;
  String get studentName => name;
}
