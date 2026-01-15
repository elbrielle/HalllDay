import 'package:flutter/material.dart';
import 'dart:async'; // For Timer
import 'package:web/web.dart' as web;
import '../services/api_service.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/app_nav_drawer.dart';
import '../widgets/admin_widgets.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  Map<String, dynamic>? _data;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _roomCtrl;
  late TextEditingController _capacityCtrl;
  late TextEditingController _overdueCtrl;
  late TextEditingController _slugCtrl;
  bool _autoPromoteQueue = false;
  bool _enableQueue = false;
  bool _autoBanOverdue = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _roomCtrl = TextEditingController();
    _capacityCtrl = TextEditingController();
    _overdueCtrl = TextEditingController();
    _slugCtrl = TextEditingController();
    _loadData();
    // Auto-Refresh every 8 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadData(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _roomCtrl.dispose();
    _capacityCtrl.dispose();
    _overdueCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await _api.getAdminStats();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;

          if (!silent) {
            final settings = data['settings'] ?? {};
            _roomCtrl.text = settings['room_name'] ?? 'Hall Pass';
            _capacityCtrl.text = (settings['capacity'] ?? 1).toString();
            _overdueCtrl.text = (settings['overdue_minutes'] ?? 10).toString();

            final user = data['user'] ?? {};
            _slugCtrl.text = user['slug'] ?? '';

            _autoPromoteQueue = settings['auto_promote_queue'] == true;
            _enableQueue = settings['enable_queue'] == true;
            _autoBanOverdue = settings['auto_ban_overdue'] == true;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (e.toString().contains('Unauthorized')) {
        web.window.location.href = '/admin/login';
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _updateSettings() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await _api.updateSettings({
        'room_name': _roomCtrl.text,
        'capacity': int.tryParse(_capacityCtrl.text) ?? 1,
        'overdue_minutes': int.tryParse(_overdueCtrl.text) ?? 10,
        'auto_promote_queue': _autoPromoteQueue,
        'enable_queue': _enableQueue,
        'auto_ban_overdue': _autoBanOverdue,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateSlug() async {
    try {
      await _api.updateSlug(_slugCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL Slug updated!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData(); // To refresh URLs
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _suspendKiosk(bool suspend) async {
    try {
      await _api.suspendKiosk(suspend);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadRoster() async {
    try {
      // Modern file picker (replaces dart:html)
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // Critical for web - gets bytes
      );

      if (result != null && result.files.first.bytes != null) {
        final bytes = result.files.first.bytes!;
        final name = result.files.first.name;

        final count = await _api.uploadRoster(bytes, name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Uploaded $count students!'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearRoster() async {
    bool clearHistory = true;
    final cur = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Clear Roster?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This will remove all students. IDs will show as "Anonymous" until a new roster is uploaded.',
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text("Also delete session history?"),
                  subtitle: const Text("Prevents 'Anonymous' stats."),
                  value: clearHistory,
                  onChanged: (val) =>
                      setState(() => clearHistory = val ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Clear Roster'),
              ),
            ],
          );
        },
      ),
    );

    if (cur == true) {
      try {
        await _api.clearRoster(clearHistory: clearHistory);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Roster cleared.')));
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _banOverdue() async {
    try {
      final count = await _api.banOverdue();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Banned $count overdue students'),
            backgroundColor: Colors.amber,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteHistory() async {
    final cur = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear History?'),
        content: const Text(
          'Permanently delete all session history logs. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete History'),
          ),
        ],
      ),
    );

    if (cur == true) {
      try {
        await _api.deleteHistory();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('History cleared.')));
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _endSessionForId(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("End Session for $name?"),
        content: const Text(
          "This will mark the student as returned immediately.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("End Session"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.endSession(id);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Session ended.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _removeFromQueue(String studentId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Remove $name from Waitlist?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.deleteFromQueue(studentId, ""); // Token not needed for admin
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Removed from waitlist.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _banStudent(String studentId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Ban $name?"),
        content: const Text(
          "This will end their current session (if any) and prevent them from checking out in the future.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Ban Student"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.banStudent(studentId);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Student banned.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = _data?['user'] ?? {};
    final stats = _data ?? {};
    final settings = _data?['settings'] ?? {};
    final urls = user['urls'] ?? {};
    final insights = _data?['insights'] ?? {};
    final isSuspended = settings['kiosk_suspended'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFDF8), // Material 3 surface
      drawer: const AppNavDrawer(currentRoute: '/admin'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.deepOrange,
                      radius: 24,
                      child: Text(
                        (user['name']?[0] ?? 'A').toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${user['name']}'s Dashboard",
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          user['email'] ?? '',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => web.window.location.href = '/logout',
                      child: const Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Launch Actions
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Launch:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: urls['kiosk']?.toString().isNotEmpty == true
                            ? () => web.window.open(urls['kiosk'], '_blank')
                            : null,
                        icon: const Icon(Icons.devices_other),
                        label: const Text("Kiosk"),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed:
                            urls['display']?.toString().isNotEmpty == true
                            ? () => web.window.open(urls['display'], '_blank')
                            : null,
                        icon: const Icon(Icons.tv),
                        label: const Text("Display"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Quick Stats & Suspend
                Row(
                  children: [
                    StatsChip(
                      "Open Sessions",
                      stats['active_sessions_count'].toString(),
                    ),
                    const SizedBox(width: 12),
                    StatsChip(
                      "Total Sessions",
                      stats['total_sessions'].toString(),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _suspendKiosk(!isSuspended),
                      icon: Icon(isSuspended ? Icons.play_arrow : Icons.pause),
                      label: Text(
                        isSuspended ? 'Resume Kiosk' : 'Suspend Kiosk',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: isSuspended
                            ? Colors.orange
                            : Colors.green[800],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // LIVE ACTIVITY (Active Sessions & Waitlist)
                const SectionHeader(
                  icon: Icons.access_time_filled,
                  title: "Live Activity",
                ),
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    // Active Sessions
                    Container(
                      width: 480,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2ECE4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Active Sessions (${stats['active_sessions_count'] ?? 0})",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if ((_data?['active_sessions'] as List?)?.isEmpty ??
                              true)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                "No active sessions.",
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else
                            ...(_data!['active_sessions'] as List).map(
                              (s) => Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s['name'] ?? 'Unknown',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            "Started: ${s['start_ts']?.split('T')[1]?.split('.')[0]}",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.stop_circle_outlined,
                                        color: Colors.red,
                                      ),
                                      tooltip: "End Session",
                                      onPressed: () =>
                                          _endSessionForId(s['id'], s['name']),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.block,
                                        color: Colors.red,
                                      ),
                                      tooltip: "Ban Student",
                                      onPressed: () => _banStudent(
                                        s['student_id'],
                                        s['name'],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Waitlist
                    Container(
                      width: 480,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0), // Orange tint
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Waitlist (${(_data?['queue_list'] as List?)?.length ?? 0})",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.orange[900],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if ((_data?['queue_list'] as List?)?.isEmpty ?? true)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                "Waitlist is empty.",
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              onReorder: (oldIndex, newIndex) async {
                                if (oldIndex < newIndex) {
                                  newIndex -= 1;
                                }
                                final queue = List<Map<String, dynamic>>.from(
                                  _data!['queue_list'],
                                );
                                final item = queue.removeAt(oldIndex);
                                queue.insert(newIndex, item);

                                // Optimistic update
                                setState(() {
                                  _data!['queue_list'] = queue;
                                });

                                // Sync API
                                final ids = queue
                                    .map((e) => e['student_id'] as String)
                                    .toList();
                                try {
                                  await _api.reorderQueue(ids);
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Reorder failed: $e'),
                                      ),
                                    );
                                  }
                                  _loadData(); // Revert on failure
                                }
                              },
                              children: [
                                for (
                                  int i = 0;
                                  i < (_data!['queue_list'] as List).length;
                                  i++
                                )
                                  Container(
                                    key: ValueKey(
                                      (_data!['queue_list']
                                          as List)[i]['student_id'],
                                    ),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.orange[200]!,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.drag_handle,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Colors.orange,
                                          child: Text(
                                            "${i + 1}",
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            (_data!['queue_list']
                                                    as List)[i]['name'] ??
                                                'Unknown',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.grey,
                                          ),
                                          tooltip: "Remove from Waitlist",
                                          onPressed: () => _removeFromQueue(
                                            (_data!['queue_list']
                                                as List)[i]['student_id'],
                                            (_data!['queue_list']
                                                as List)[i]['name'],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Share Section
                const SectionHeader(
                  icon: Icons.share,
                  title: "Share Your Kiosk",
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2ECE4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CopyField("Kiosk URL", urls['kiosk'] ?? ''),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: CopyField(
                              "Display URL",
                              urls['display'] ?? '',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Embed Code
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Embed Code (iframe)",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SelectableText(
                          '<iframe src="${urls['display']}" width="400" height="600" frameborder="0"></iframe>',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Customize URL
                const SectionHeader(title: "Customize URL"),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _slugCtrl,
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Color(0xFFE2ECE4),
                          hintText: "Enter custom slug (e.g. mr-smith)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: _updateSlug,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green[800],
                        padding: const EdgeInsets.all(22),
                      ),
                      child: const Text('Save Slug'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Roster Management
                SectionHeader(
                  title: "Roster Management",
                  color: Colors.green[800],
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2ECE4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock, size: 16),
                          SizedBox(width: 8),
                          Text(
                            "FERPA-Compliant Upload",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Supported CSV Formats: Name, ID (e.g. 'John Doe, 12345') OR ID, Name. Header row is optional.",
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _uploadRoster,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[800],
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Upload CSV"),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              web.window.open('/api/roster/template', '_blank');
                            },
                            icon: const Icon(Icons.download),
                            label: const Text("Template"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green[800],
                            ),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (c) => RosterManager(api: _api),
                            ),
                            icon: const Icon(Icons.list),
                            label: const Text("Manage Roster & Bans"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: StatsCard(
                              "${stats['roster_count']}",
                              "Database Roster (Encrypted)",
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: StatsCard(
                              "${stats['memory_roster_count']}",
                              "Display Cache",
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              web.window.open('/api/roster/export', '_blank');
                            },
                            icon: const Icon(Icons.download),
                            label: const Text("Export Roster"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green[800],
                            ),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton(
                            onPressed: _clearRoster,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            child: const Text("Clear All Roster Data"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Settings
                const SectionHeader(title: "Settings"),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2ECE4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _roomCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Room Name",
                                ),
                                validator: (v) => v!.isEmpty ? "Req" : null,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: TextFormField(
                                controller: _capacityCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Capacity",
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: TextFormField(
                                controller: _overdueCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Overdue (min)",
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const SizedBox(height: 16),

                        // Queue Master Switch
                        CheckboxListTile(
                          title: const Text("Enable Waitlist Queue"),
                          subtitle: const Text(
                            "Allow students to join a queue when room is full.",
                          ),
                          value: _enableQueue,
                          onChanged: (val) =>
                              setState(() => _enableQueue = val ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.orange,
                        ),

                        if (_enableQueue) ...[
                          const Padding(
                            padding: EdgeInsets.only(left: 16.0),
                            child: Divider(),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: CheckboxListTile(
                              title: const Text("Auto-Start Next in Queue"),
                              subtitle: const Text(
                                "Automatically start the next student when a pass is returned.",
                              ),
                              value: _autoPromoteQueue,
                              onChanged: (val) => setState(
                                () => _autoPromoteQueue = val ?? false,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],

                        const Divider(),
                        CheckboxListTile(
                          title: const Text("Auto-Ban Overdue Students"),
                          subtitle: const Text(
                            "Automatically ban students if they exceed the overdue limit.",
                          ),
                          value: _autoBanOverdue,
                          onChanged: (val) =>
                              setState(() => _autoBanOverdue = val ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.red,
                        ),

                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _updateSettings,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green[800],
                          ),
                          child: const Text("Save Settings"),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Insights
                const SectionHeader(title: "Weekly Insights"),
                const Text(
                  '"Anonymous" entries appear when IDs are scanned without a roster.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 250,
                  child: Row(
                    children: [
                      Expanded(
                        child: InsightCard(
                          "Top Users",
                          insights['top_students'] ?? [],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InsightCard(
                          "Most Overdue",
                          insights['most_overdue'] ?? [],
                          isRed: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (c) => PassLogsDialog(api: _api),
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text("View Full Pass Logs"),
                  ),
                ),

                const SizedBox(height: 32),

                const SizedBox(height: 32),
                const SectionHeader(
                  title: "System Status",
                  icon: Icons.monitor_heart,
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2ECE4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      const Text(
                        "Currently Overdue",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: _loadData,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Check Overdue"),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _banOverdue,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[800],
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Ban All Overdue"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                const SectionHeader(title: "System Controls"),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2ECE4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Danger Zone",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        color: Colors.red[50],
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Permanently delete all session history.",
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _deleteHistory,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[800],
                                foregroundColor: Colors.white,
                              ),
                              child: const Text("Delete History"),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
