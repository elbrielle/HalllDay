import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:web/web.dart' as web; // For PassLogsDialog export
import '../services/api_service.dart'; // For RosterManager, PassLogsDialog

/// Section header widget for admin panel sections
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? color;

  const SectionHeader({super.key, required this.title, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: color ?? Colors.green[800]),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: TextStyle(fontSize: 24, color: color ?? Colors.green[800]),
          ),
        ],
      ),
    );
  }
}

/// Stats chip widget showing label-value pairs
class StatsChip extends StatelessWidget {
  final String label;
  final String value;

  const StatsChip(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE2ECE4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text("$label:", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(value),
        ],
      ),
    );
  }
}

/// Copy field widget with clipboard functionality
class CopyField extends StatelessWidget {
  final String label;
  final String value;

  const CopyField(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor, size: 16),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied!')));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text("Copy"),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF2F2F2),
              foregroundColor: Colors.black,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stats card widget showing large value and label
class StatsCard extends StatelessWidget {
  final String value;
  final String label;

  const StatsCard(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 32, color: Colors.green[800])),
          Text(label, style: const TextStyle(color: Colors.black)),
        ],
      ),
    );
  }
}

/// Insight card widget with horizontal bar chart
class InsightCard extends StatelessWidget {
  final String title;
  final List<dynamic> items;
  final bool isRed;

  const InsightCard(this.title, this.items, {super.key, this.isRed = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE2ECE4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final item = items[i];
                final maxVal = (items.isNotEmpty)
                    ? items[0]['count'] as int
                    : 1;
                final val = item['count'] as int;
                final pct = val / maxVal;

                return Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        item['name'],
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(height: 12, color: Colors.grey[300]),
                          FractionallySizedBox(
                            widthFactor: pct,
                            child: Container(
                              height: 12,
                              color: isRed ? Colors.red : Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text("$val", style: const TextStyle(fontSize: 12)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Roster manager dialog for viewing and managing student bans
class RosterManager extends StatefulWidget {
  final ApiService api;

  const RosterManager({super.key, required this.api});

  @override
  State<RosterManager> createState() => _RosterManagerState();
}

class _RosterManagerState extends State<RosterManager> {
  bool _loading = true;
  List<Map<String, dynamic>> _roster = [];
  List<Map<String, dynamic>> _filtered = [];
  final TextEditingController _searchCtrl = TextEditingController();

  String _filterOption = 'All'; // All, Banned Only
  String _sortOption = 'Name (A-Z)'; // Name (A-Z), Name (Z-A), Banned First

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await widget.api.fetchRoster();
      setState(() {
        _roster = data;
        _filtered = data;
        _loading = false;
      });
      _filter();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      // 1. Filter
      var temp = _roster.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final id = (s['student_id'] ?? '').toString().toLowerCase();
        final matchesSearch = name.contains(q) || id.contains(q);

        if (_filterOption == 'Banned Only') {
          return matchesSearch && (s['banned'] == true);
        }
        return matchesSearch;
      }).toList();

      // 2. Sort
      temp.sort((a, b) {
        if (_sortOption == 'Banned First') {
          final banA = (a['banned'] == true) ? 1 : 0;
          final banB = (b['banned'] == true) ? 1 : 0;
          if (banA != banB) return banB.compareTo(banA); // Banned (1) first
          // Secondary sort: Name A-Z
          return (a['name'] ?? '').compareTo(b['name'] ?? '');
        } else if (_sortOption == 'Name (Z-A)') {
          return (b['name'] ?? '').compareTo(a['name'] ?? '');
        } else {
          // Name (A-Z) - default
          return (a['name'] ?? '').compareTo(b['name'] ?? '');
        }
      });

      _filtered = temp;
    });
  }

  Future<void> _toggleBan(int index, bool val) async {
    final s = _filtered[index];
    // Optimistic
    setState(() {
      s['banned'] = val;
    });

    try {
      await widget.api.toggleBan(s['name_hash'], val);
    } catch (e) {
      // Revert
      setState(() {
        s['banned'] = !val;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Manage Roster & Bans",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search by Name or ID...",
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _filter(),
            ),
            const SizedBox(height: 16),
            // Filter & Sort Controls
            Row(
              children: [
                // Filter Dropdown
                const Text(
                  "Show: ",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _filterOption,
                  items: ['All', 'Banned Only'].map((String val) {
                    return DropdownMenuItem(value: val, child: Text(val));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _filterOption = val);
                      _filter(); // Re-run filter logic
                    }
                  },
                ),
                const SizedBox(width: 24),
                // Sort Dropdown
                const Text(
                  "Sort: ",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _sortOption,
                  items: ['Name (A-Z)', 'Name (Z-A)', 'Banned First'].map((
                    String val,
                  ) {
                    return DropdownMenuItem(value: val, child: Text(val));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _sortOption = val);
                      _filter(); // Re-run sort logic
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? const Center(child: Text("No students found."))
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (ctx, i) {
                        final s = _filtered[i];
                        final id = s['student_id'] ?? 'Hidden';
                        final isBanned = s['banned'] == true;
                        final banDays = s['ban_days'];

                        // Build subtitle with ID and ban duration
                        String subtitle = "ID: $id";
                        if (isBanned && banDays != null) {
                          subtitle +=
                              ' • Banned: $banDays ${banDays == 1 ? 'day' : 'days'}';
                        }

                        return ListTile(
                          title: Text(
                            s['name'] ?? 'Unknown',
                            style: TextStyle(
                              color: isBanned ? Colors.red : null,
                              fontWeight: isBanned ? FontWeight.bold : null,
                            ),
                          ),
                          subtitle: Text(
                            subtitle,
                            style: TextStyle(
                              color: isBanned ? Colors.red.shade700 : null,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isBanned ? "BANNED" : "Active",
                                style: TextStyle(
                                  color: isBanned ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: isBanned,
                                activeThumbColor: Colors.red,
                                onChanged: (v) => _toggleBan(i, v),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pass logs dialog showing recent hall pass activity
class PassLogsDialog extends StatefulWidget {
  final ApiService api;

  const PassLogsDialog({super.key, required this.api});

  @override
  State<PassLogsDialog> createState() => _PassLogsDialogState();
}

class _PassLogsDialogState extends State<PassLogsDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.getPassLogs();
      if (mounted) {
        setState(() {
          _logs = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 800,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  "Recent Pass Activity",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {
                    web.window.open('/api/admin/logs/export', '_blank');
                  },
                  icon: const Icon(Icons.download),
                  label: const Text("Export CSV"),
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _logs.isEmpty
                  ? const Center(child: Text("No logs found."))
                  : SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text("Student")),
                          DataColumn(label: Text("Start Time")),
                          DataColumn(label: Text("Duration")),
                          DataColumn(label: Text("Status")),
                        ],
                        rows: _logs.map((log) {
                          final status = log['status'] ?? 'active';
                          final isOverdue = status == 'overdue';
                          final isEnded = status == 'completed';

                          Color color = Colors.black;
                          if (isOverdue) {
                            color = Colors.red;
                          } else if (!isEnded) {
                            color = Colors.green[800]!;
                          }

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  log['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  log['start']?.split('T')[1].split('.')[0] ??
                                      '',
                                ),
                              ),
                              DataCell(Text("${log['duration_minutes']} min")),
                              DataCell(
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
