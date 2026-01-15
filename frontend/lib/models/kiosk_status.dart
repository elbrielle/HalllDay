import 'session.dart';

class KioskStatus {
  final int overdueMinutes;
  final bool kioskSuspended;
  final bool autoBanOverdue;
  final int capacity;
  final List<Session> activeSessions;
  final List<String> queue;
  final int serverTimeMs;

  KioskStatus({
    required this.overdueMinutes,
    required this.kioskSuspended,
    required this.autoBanOverdue,
    required this.capacity,
    required this.activeSessions,
    required this.queue,
    required this.serverTimeMs,
  });

  factory KioskStatus.fromJson(Map<String, dynamic> json) {
    // Get server time first - needed for session time sync
    final int serverTimeMs = json['server_time_ms'] is int
        ? json['server_time_ms']
        : 0;

    var rawSessions = json['active_sessions'] as List?;
    List<Session> sessions = [];
    if (rawSessions != null) {
      sessions = rawSessions
          .map((s) => Session.fromJson(s, serverTimeMs: serverTimeMs))
          .toList();
    }

    var rawQueue = json['queue'] as List?;
    List<String> queueList = [];
    if (rawQueue != null) {
      queueList = List<String>.from(rawQueue);
    }

    return KioskStatus(
      overdueMinutes: json['overdue_minutes'] is int
          ? json['overdue_minutes']
          : 10,
      kioskSuspended: json['kiosk_suspended'] ?? false,
      autoBanOverdue: json['auto_ban_overdue'] ?? false,
      capacity: json['capacity'] is int ? json['capacity'] : 1,
      activeSessions: sessions,
      queue: queueList,
      serverTimeMs: serverTimeMs,
    );
  }
}
