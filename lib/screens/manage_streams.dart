import 'package:flutter/material.dart';

class ManageStreamsScreen extends StatelessWidget {
  const ManageStreamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Streams')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(title: Text('SSC')),
          ListTile(title: Text('NEET')),
          ListTile(title: Text('JEE')),
          ListTile(title: Text('UPSC')),
          ListTile(title: Text('School')),
          ListTile(title: Text('College')),
        ],
      ),
    );
  }
}
