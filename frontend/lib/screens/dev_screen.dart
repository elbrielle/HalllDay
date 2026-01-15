import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/app_nav_drawer.dart';

class DevScreen extends StatefulWidget {
  const DevScreen({super.key});

  @override
  State<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends State<DevScreen> {
  final ApiService _api = ApiService();
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _stats;

  // Login Controller
  final TextEditingController _passcodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final stats = await _api.getExpandedDevStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isAuthenticated = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      // If 401, we are just not authenticated yet
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    final success = await _api.devAuth(_passcodeController.text);
    if (success) {
      await _checkAuth(); // Fetch stats
      setState(() {
        _error = null;
      });
    } else {
      setState(() {
        _error = "Invalid Passcode";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text("Dev Tools Login")),
        body: Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.security, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    "Developer Access",
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: _passcodeController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Passcode",
                        errorText: _error,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _login, child: const Text("Unlock")),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("System Health (Dev)"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      drawer: const AppNavDrawer(currentRoute: '/dev'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildGlobalStats(),
          const SizedBox(height: 32),
          const Text(
            "Active Teachers",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildTeachersList(),
          const SizedBox(height: 32),
          const Text(
            "System Activity (Anonymized)",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildActivityFeed(),
          const SizedBox(height: 32),
          const Text(
            "Database Actions",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text(
                  "Wipe Database",
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: () {
                  // Implementation for wipe would go here
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Not implemented in frontend yet"),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalStats() {
    final g = _stats?['global_stats'] ?? {};
    return Card(
      elevation: 0,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatRow("Total Sessions", g['total_sessions']),
            _buildStatRow("Active Sessions", g['active_sessions']),
            const Divider(),
            _buildStatRow("Total Students", g['total_students']),
            _buildStatRow("Total Users", g['total_users']),
          ],
        ),
      ),
    );
  }

  Widget _buildTeachersList() {
    final teachers = List<Map<String, dynamic>>.from(_stats?['teachers'] ?? []);
    if (teachers.isEmpty) return const Text("No active teachers found.");

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: teachers.length,
        separatorBuilder: (c, i) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final t = teachers[index];
          final isActive = (t['active_sessions'] ?? 0) > 0;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isActive ? Colors.green : Colors.grey[300],
              child: Icon(
                Icons.person,
                color: isActive ? Colors.white : Colors.grey,
              ),
            ),
            title: Text(t['email'] ?? "Unknown"),
            subtitle: Text("Last Active: ${t['last_login'] ?? 'Never'}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${t['active_sessions']} Active",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.green[700] : Colors.grey,
                  ),
                ),
                Text(
                  "${t['total_sessions']} Total Sessions",
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActivityFeed() {
    final activity = List<Map<String, dynamic>>.from(_stats?['activity'] ?? []);
    if (activity.isEmpty) return const Text("No recent activity.");

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activity.length,
        separatorBuilder: (c, i) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final a = activity[index];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 16),
            title: Text("${a['action']} - ${a['teacher']}"),
            subtitle: Text(a['timestamp']?.toString().split('.').first ?? ""),
            trailing: Text(a['duration'] ?? ""),
          );
        },
      ),
    );
  }

  Widget _buildStatRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 18)),
          Text(
            value.toString(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
