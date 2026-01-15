import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/kiosk_status.dart';

class MobileListView extends StatelessWidget {
  final KioskStatus status;
  final int Function() getLocalSecondsSincePoll; // Getter for fresh time

  const MobileListView({
    super.key,
    required this.status,
    required this.getLocalSecondsSincePoll,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header
            const SizedBox(height: 24),

            // ACTIVE PASSES Section
            if (status.activeSessions.isNotEmpty) ...[
              const _SectionHeader(title: "ACTIVE PASSES", color: Colors.green),
              const SizedBox(height: 8),
              ...status.activeSessions.map((session) {
                final isOverdue = session.isOverdue;
                return Card(
                      color: isOverdue ? Colors.red[900] : Colors.green[800],
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isOverdue ? Colors.red : Colors.greenAccent,
                          width: 2,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Icon(
                          Icons.timer,
                          color: Colors.white,
                          size: 32,
                        ),
                        title: Text(
                          session.studentName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        trailing: Text(
                          session.getCurrentTimerText(
                            getLocalSecondsSincePoll(),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                    .animate(
                      onPlay: (c) => isOverdue ? c.repeat(reverse: true) : null,
                    )
                    .shimmer(
                      duration: 2.seconds,
                      color: Colors.white.withValues(alpha: 0.1),
                    );
              }),
            ] else ...[
              // Empty State for Active
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: Colors.green,
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Room is Empty",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // WAITLIST Section
            if (status.queue.isNotEmpty) ...[
              const _SectionHeader(title: "WAITLIST", color: Colors.orange),
              const SizedBox(height: 8),
              ...status.queue.asMap().entries.map((entry) {
                final index = entry.key;
                final name = entry.value;
                return Card(
                  color: Colors.grey[900],
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Colors.orange.withValues(alpha: 0.5),
                    ),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        "${index + 1}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
            ] else ...[
              // Optional: Show "Join Queue" hint or nothing
            ],

            const SizedBox(height: 48), // Padding at bottom
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 24, color: color),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
