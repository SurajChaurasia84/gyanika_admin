import 'package:flutter/material.dart';

class CreatePollScreen extends StatelessWidget {
  const CreatePollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Poll')),
      body: const Center(
        child: Text(
          'Poll Creation Screen',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
