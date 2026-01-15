import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:universal_html/html.dart' as html;
import '../services/api_service.dart';

/// Common US timezones for dropdown selection
const List<String> kTimezones = [
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Anchorage',
  'Pacific/Honolulu',
];

/// Schedule management widget with week view calendar
class ScheduleManager extends StatefulWidget {
  final ApiService api;
  final bool scheduleEnabled;
  final String? timezone;
  final bool allowQueueWhileSuspended;
  final Function(bool enabled, String? timezone, bool allowQueue)
  onSettingsChanged;

  const ScheduleManager({
    super.key,
    required this.api,
    required this.scheduleEnabled,
    required this.timezone,
    required this.allowQueueWhileSuspended,
    required this.onSettingsChanged,
  });

  @override
  State<ScheduleManager> createState() => _ScheduleManagerState();
}

class _ScheduleManagerState extends State<ScheduleManager> {
  List<ScheduleEntry> _entries = [];
  bool _loading = true;
  DateTime _weekStart = _getWeekStart(DateTime.now());

  static DateTime _getWeekStart(DateTime date) {
    // Monday = 1, Sunday = 7 in Dart
    final daysToSubtract = date.weekday - 1; // Days since Monday
    return DateTime(date.year, date.month, date.day - daysToSubtract);
  }

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() => _loading = true);
    try {
      final entries = await widget.api.getSchedules();
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load schedules: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with toggle
            _buildHeader(),
            const SizedBox(height: 16),

            // Settings row (timezone, queue option)
            if (widget.scheduleEnabled) ...[
              _buildSettingsRow(),
              const Divider(height: 24),

              // Week view calendar
              _buildWeekView(),
              const SizedBox(height: 16),

              // Schedule list
              _buildScheduleList(),
              const SizedBox(height: 16),

              // Add button
              _buildAddButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.schedule, color: Colors.green[700]),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Schedule Mode',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Switch(
          value: widget.scheduleEnabled,
          onChanged: (enabled) {
            if (enabled && widget.timezone == null) {
              // Show timezone picker first
              _showTimezonePrompt();
            } else {
              widget.onSettingsChanged(
                enabled,
                widget.timezone,
                widget.allowQueueWhileSuspended,
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildSettingsRow() {
    return Column(
      children: [
        Row(
          children: [
            const Text('Timezone: '),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: widget.timezone,
              hint: const Text('Select timezone'),
              items: kTimezones.map((tz) {
                final label = tz.replaceAll('_', ' ').split('/').last;
                return DropdownMenuItem(value: tz, child: Text(label));
              }).toList(),
              onChanged: (tz) {
                widget.onSettingsChanged(
                  widget.scheduleEnabled,
                  tz,
                  widget.allowQueueWhileSuspended,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: widget.allowQueueWhileSuspended,
              onChanged: (v) {
                widget.onSettingsChanged(
                  widget.scheduleEnabled,
                  widget.timezone,
                  v ?? false,
                );
              },
            ),
            const Text('Allow waitlist while suspended'),
          ],
        ),
      ],
    );
  }

  Widget _buildWeekView() {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final today = DateTime.now();

    return Column(
      children: [
        // Week navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _weekStart = _weekStart.subtract(const Duration(days: 7));
                });
              },
            ),
            Text(
              '${DateFormat('MMM d').format(_weekStart)} - ${DateFormat('MMM d, yyyy').format(days.last)}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _weekStart = _weekStart.add(const Duration(days: 7));
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Day columns
        SizedBox(
          height: 120,
          child: Row(
            children: days.map((day) {
              final isToday =
                  day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day;
              final entriesForDay = _getEntriesForDay(day);

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isToday
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: isToday
                        ? Border.all(color: Colors.green, width: 2)
                        : null,
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            Text(
                              DateFormat('E').format(day),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: isToday
                                    ? Colors.green[700]
                                    : Colors.grey[700],
                              ),
                            ),
                            Text(
                              DateFormat('d').format(day),
                              style: TextStyle(
                                fontSize: 14,
                                color: isToday
                                    ? Colors.green[700]
                                    : Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(2),
                          children: entriesForDay.take(3).map((e) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[100],
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                e.label,
                                style: const TextStyle(fontSize: 8),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      if (entriesForDay.length > 3)
                        Text(
                          '+${entriesForDay.length - 3}',
                          style: const TextStyle(fontSize: 10),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  List<ScheduleEntry> _getEntriesForDay(DateTime day) {
    final weekday = day.weekday - 1; // Convert to 0=Mon, 6=Sun
    return _entries.where((e) {
      if (!e.enabled) return false;

      // Check date bounds
      final startDate = DateTime.parse(e.startDate);
      if (day.isBefore(startDate)) return false;
      if (e.endDate != null) {
        final endDate = DateTime.parse(e.endDate!);
        if (day.isAfter(endDate)) return false;
      }

      // Check repeat pattern
      switch (e.repeatType) {
        case 'none':
          return day.year == startDate.year &&
              day.month == startDate.month &&
              day.day == startDate.day;
        case 'weekdays':
          return weekday <= 4; // Mon-Fri
        case 'weekly':
          return startDate.weekday - 1 == weekday;
        case 'custom':
          if (e.repeatDays == null) return false;
          final days = e.repeatDays!
              .split(',')
              .map((d) => int.tryParse(d) ?? -1)
              .toList();
          return days.contains(weekday);
        default:
          return false;
      }
    }).toList();
  }

  Widget _buildScheduleList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No schedule windows defined. Kiosk will be suspended at all times.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Allowed Times',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        ..._entries.map((e) => _buildEntryTile(e)),
      ],
    );
  }

  Widget _buildEntryTile(ScheduleEntry entry) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.enabled ? Icons.timer : Icons.timer_off,
        color: entry.enabled ? Colors.green : Colors.grey,
      ),
      title: Text(entry.label),
      subtitle: Text('${entry.timeRangeDisplay} • ${entry.repeatDisplay}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _showEditDialog(entry),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            onPressed: () => _deleteEntry(entry),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: _showAddDialog,
          icon: const Icon(Icons.add),
          label: const Text('Add Allowed Time'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _exportSchedules,
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Export'),
        ),
        TextButton.icon(
          onPressed: _importSchedules,
          icon: const Icon(Icons.upload, size: 18),
          label: const Text('Import'),
        ),
      ],
    );
  }

  void _showTimezonePrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Timezone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please select your timezone to enable schedule mode.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Timezone',
                border: OutlineInputBorder(),
              ),
              value: 'America/Chicago',
              items: kTimezones.map((tz) {
                final label = tz.replaceAll('_', ' ').split('/').last;
                return DropdownMenuItem(value: tz, child: Text(label));
              }).toList(),
              onChanged: (tz) {
                if (tz != null) {
                  widget.onSettingsChanged(
                    true,
                    tz,
                    widget.allowQueueWhileSuspended,
                  );
                  Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showAddDialog() {
    _showScheduleDialog(null);
  }

  void _showEditDialog(ScheduleEntry entry) {
    _showScheduleDialog(entry);
  }

  void _showScheduleDialog(ScheduleEntry? existing) {
    final labelController = TextEditingController(text: existing?.label ?? '');
    TimeOfDay startTime = existing != null
        ? TimeOfDay(
            hour: int.parse(existing.startTime.split(':')[0]),
            minute: int.parse(existing.startTime.split(':')[1]),
          )
        : const TimeOfDay(hour: 8, minute: 15);
    TimeOfDay endTime = existing != null
        ? TimeOfDay(
            hour: int.parse(existing.endTime.split(':')[0]),
            minute: int.parse(existing.endTime.split(':')[1]),
          )
        : const TimeOfDay(hour: 8, minute: 25);
    DateTime startDate = existing != null
        ? DateTime.parse(existing.startDate)
        : DateTime.now();
    DateTime? endDate = existing?.endDate != null
        ? DateTime.parse(existing!.endDate!)
        : null;
    String repeatType = existing?.repeatType ?? 'weekdays';
    List<int> customDays = existing?.repeatDays != null
        ? existing!.repeatDays!.split(',').map((d) => int.parse(d)).toList()
        : [0, 1, 2, 3, 4]; // Default M-F

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Add Allowed Time' : 'Edit Allowed Time',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    hintText: 'e.g., Passing Period 1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Time pickers
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: startTime,
                          );
                          if (picked != null) {
                            setDialogState(() => startTime = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Time',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(startTime.format(ctx)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: endTime,
                          );
                          if (picked != null) {
                            setDialogState(() => endTime = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Time',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(endTime.format(ctx)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Date pickers
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => startDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Date',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            DateFormat('MMM d, yyyy').format(startDate),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate:
                                endDate ??
                                startDate.add(const Duration(days: 120)),
                            firstDate: startDate,
                            lastDate: DateTime(2100),
                          );
                          setDialogState(() => endDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Date (optional)',
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  endDate != null
                                      ? DateFormat(
                                          'MMM d, yyyy',
                                        ).format(endDate!)
                                      : 'No end date',
                                ),
                              ),
                              if (endDate != null)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () =>
                                      setDialogState(() => endDate = null),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Repeat type
                DropdownButtonFormField<String>(
                  value: repeatType,
                  decoration: const InputDecoration(
                    labelText: 'Repeats',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('Does not repeat'),
                    ),
                    DropdownMenuItem(
                      value: 'weekdays',
                      child: Text('Monday - Friday'),
                    ),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom...')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => repeatType = v ?? 'weekdays'),
                ),

                // Custom day chips
                if (repeatType == 'custom') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (int i = 0; i < 7; i++)
                        FilterChip(
                          label: Text(
                            ['M', 'T', 'W', 'Th', 'F', 'Sa', 'Su'][i],
                          ),
                          selected: customDays.contains(i),
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                customDays.add(i);
                              } else {
                                customDays.remove(i);
                              }
                              customDays.sort();
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (labelController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a label')),
                  );
                  return;
                }

                if (repeatType == 'custom' && customDays.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select at least one day'),
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                final entry = ScheduleEntry(
                  id: existing?.id,
                  label: labelController.text,
                  startTime:
                      '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                  endTime:
                      '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                  startDate: DateFormat('yyyy-MM-dd').format(startDate),
                  endDate: endDate != null
                      ? DateFormat('yyyy-MM-dd').format(endDate!)
                      : null,
                  repeatType: repeatType,
                  repeatDays: repeatType == 'custom'
                      ? customDays.join(',')
                      : null,
                );

                try {
                  if (existing == null) {
                    await widget.api.createSchedule(entry);
                  } else {
                    await widget.api.updateSchedule(
                      existing.id!,
                      entry.toJson(),
                    );
                  }
                  _loadSchedules();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    // Dispose controller
    Future.microtask(() => labelController.dispose);
  }

  Future<void> _deleteEntry(ScheduleEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text('Delete "${entry.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && entry.id != null) {
      try {
        await widget.api.deleteSchedule(entry.id!);
        _loadSchedules();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  void _exportSchedules() {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No schedules to export')));
      return;
    }

    // Convert entries to JSON
    final exportData = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'entries': _entries.map((e) => e.toJson()).toList(),
    };
    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

    // Create download
    final bytes = utf8.encode(jsonString);
    final blob = html.Blob([bytes], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'halllday_schedule_${DateFormat('yyyyMMdd').format(DateTime.now())}.json',
      )
      ..click();
    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Schedule exported!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _importSchedules() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        throw Exception('Could not read file');
      }

      final jsonString = utf8.decode(bytes);
      final data = json.decode(jsonString) as Map<String, dynamic>;

      if (data['entries'] == null || data['entries'] is! List) {
        throw Exception('Invalid schedule file format');
      }

      final entries = (data['entries'] as List)
          .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      if (entries.isEmpty) {
        throw Exception('No entries found in file');
      }

      // Confirm import
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import Schedules'),
          content: Text(
            'Import ${entries.length} schedule entries? This will add to your existing schedules.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Create each entry
      int created = 0;
      for (final entry in entries) {
        try {
          await widget.api.createSchedule(entry);
          created++;
        } catch (e) {
          debugPrint('Failed to import entry: ${entry.label} - $e');
        }
      }

      await _loadSchedules();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $created of ${entries.length} schedules'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
