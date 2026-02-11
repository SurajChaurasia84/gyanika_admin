import 'package:flutter/material.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: const Center(
        child: Text(
          'User management will be here',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
