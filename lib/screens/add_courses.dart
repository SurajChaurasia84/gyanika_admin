import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddCourseScreen extends StatefulWidget {
  const AddCourseScreen({super.key});

  @override
  State<AddCourseScreen> createState() => _AddCourseScreenState();
}

class _AddCourseScreenState extends State<AddCourseScreen> {
  final _formKey = GlobalKey<FormState>();

  final _courseName = TextEditingController();
  final _subtitle = TextEditingController();
  final _content = TextEditingController();
  final _keywords = TextEditingController();
  final _hashtags = TextEditingController();

  String level = 'Beginner';
  String stream = 'SSC';

  bool loading = false;

  final levels = ['Beginner', 'Medium', 'Hard'];
  final streams = [
    'SSC',
    'JEE',
    'NEET',
    'IIT',
    'UPSC',
    'School',
    'College',
    'Programming',
    'Other',
  ];

  Future<void> saveCourse() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);

    try {
      await FirebaseFirestore.instance.collection('courses').add({
        'courseName': _courseName.text.trim(),
        'subtitle': _subtitle.text.trim(),
        'content': _content.text.trim(),
        'level': level,
        'stream': stream,
        'keywords': _keywords.text
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .toList(),
        'hashtags': _hashtags.text
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .toList(),
        'published': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Course added successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Course')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _field(_courseName, 'Course Name'),
              _field(_subtitle, 'Subtitle'),

              _dropdown(
                label: 'Level',
                value: level,
                items: levels,
                onChanged: (v) => setState(() => level = v!),
              ),

              _dropdown(
                label: 'Stream',
                value: stream,
                items: streams,
                onChanged: (v) => setState(() => stream = v!),
              ),

              _field(_content, 'Course Content / Description', maxLines: 5),

              _field(
                _keywords,
                'Keywords (comma separated)',
                hint: 'flutter, ui, exam',
              ),

              _field(
                _hashtags,
                'Hashtags',
                hint: '#flutter #ssc #neet',
              ),

              const SizedBox(height: 24),

              loading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saveCourse,
                        child: const Text('Publish Course'),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        textCapitalization: TextCapitalization.sentences,
        maxLines: maxLines,
        validator: (v) => v == null || v.isEmpty ? 'Required field' : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: value,
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
