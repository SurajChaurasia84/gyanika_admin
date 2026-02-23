import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/login_screen.dart';
import '../services/local_cache_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final String? _uid;
  Map<String, dynamic>? _profileData;
  bool _loading = true;
  String? _error;

  String get _cacheKey => 'admin_profile_${_uid ?? 'unknown'}';

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: const SafeArea(
          child: Center(child: Text('No logged in user found')),
        ),
      );
    }

    if (_loading && _profileData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final data = _profileData;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Profile data not found'),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => _loadProfile(forceRemote: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final name = (data['name'] ?? data['fullName'] ?? '').toString();
    final email = (data['email'] ?? currentUser?.email ?? '').toString();
    final role = (data['role'] ?? 'admin').toString();
    final active = data['active'] == true ? 'Yes' : 'No';
    final adminFrom = _formatAdminFrom(
      data['createdAt'] ?? data['timestamp'] ?? data['joinedAt'],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadProfile(forceRemote: true),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _DetailTile(label: 'Name', value: name.isEmpty ? '-' : name),
                    _DetailTile(label: 'Email', value: email.isEmpty ? '-' : email),
                    _DetailTile(label: 'Role', value: role),
                    _DetailTile(label: 'Active', value: active),
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        onTap: _confirmLogout,
                        title: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Logout',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                        dense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Admin from $adminFrom',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadProfile({bool forceRemote = false}) async {
    if (_uid == null) return;

    if (!forceRemote) {
      final cached = LocalCacheService.getJsonMap(_cacheKey);
      if (cached != null && mounted) {
        setState(() {
          _profileData = cached;
          _loading = false;
          _error = null;
        });
      }
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('admins').doc(_uid).get();
      final raw = doc.data();
      if (!doc.exists || raw == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Profile data not found';
        });
        return;
      }

      final normalized = _normalizeAdminData(raw);
      await LocalCacheService.saveJson(_cacheKey, normalized);

      if (!mounted) return;
      setState(() {
        _profileData = normalized;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Showing cached profile (sync failed)';
      });
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Map<String, dynamic> _normalizeAdminData(Map<String, dynamic> data) {
    final out = Map<String, dynamic>.from(data);
    for (final key in ['createdAt', 'timestamp', 'joinedAt']) {
      final value = out[key];
      if (value is Timestamp) {
        out[key] = value.millisecondsSinceEpoch;
      }
    }
    return out;
  }

  String _formatAdminFrom(dynamic value) {
    DateTime? dt;
    if (value is Timestamp) {
      dt = value.toDate();
    } else if (value is DateTime) {
      dt = value;
    } else if (value is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      final millis = int.tryParse(value);
      if (millis != null) {
        dt = DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }

    if (dt == null) return '-';
    final local = dt.toLocal();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[local.month - 1];
    return '$month ${local.day}, ${local.year}';
  }
}

class _DetailTile extends StatelessWidget {
  final String label;
  final String value;

  const _DetailTile({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}
