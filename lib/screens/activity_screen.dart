import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/local_cache_service.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const String _cacheKey = 'activity_feed_v1';

  List<_ActivityItem> _activities = <_ActivityItem>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _activities.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activity')),
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
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
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadActivities(forceRemote: true),
                child: _activities.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 260),
                          Center(child: Text('No activity found')),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                        itemCount: _activities.length,
                        itemBuilder: (context, index) {
                          final item = _activities[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: item.type == _ActivityType.course
                                    ? Colors.indigo.shade100
                                    : Colors.green.shade100,
                                child: Icon(
                                  item.type == _ActivityType.course
                                      ? Icons.menu_book
                                      : Icons.layers,
                                  color: item.type == _ActivityType.course
                                      ? Colors.indigo
                                      : Colors.green,
                                ),
                              ),
                              title: Text(item.title),
                              subtitle: Text(item.subtitle),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: item.published
                                      ? Colors.green.shade100
                                      : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  item.published ? 'Published' : 'Unpublished',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: item.published
                                        ? Colors.green.shade800
                                        : Colors.orange.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _ActivityEditScreen(item: item),
                                  ),
                                );
                                if (mounted) {
                                  _loadActivities(forceRemote: true);
                                }
                              },
                            ),
                          );
                        },
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadActivities({bool forceRemote = false}) async {
    if (!forceRemote) {
      final cached = LocalCacheService.getJsonList(_cacheKey);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _activities = _buildActivitiesFromCache(cached);
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
      final coursesFuture = FirebaseFirestore.instance
          .collection('courses')
          .orderBy('createdAt', descending: true)
          .get();
      final setsFuture = FirebaseFirestore.instance.collectionGroup('sets').get();
      final results = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
        coursesFuture,
        setsFuture,
      ]);

      final courses = results[0];
      final sets = results[1];

      final items = _buildActivitiesFromDocs(courses.docs, sets.docs);
      final payload = items.map(_toCacheItem).toList();
      await LocalCacheService.saveJson(_cacheKey, payload);

      if (!mounted) return;
      setState(() {
        _activities = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _activities.isEmpty
            ? 'Failed to load activity'
            : 'Showing cached activity (sync failed)';
      });
    }
  }

  List<_ActivityItem> _buildActivitiesFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> setDocs,
  ) {
    final items = <_ActivityItem>[
      ...courseDocs.map((doc) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;
        final createdAtMs = createdAt?.millisecondsSinceEpoch;
        return _ActivityItem(
          type: _ActivityType.course,
          title: (data['courseName'] ?? 'Untitled course').toString(),
          subtitle:
              '${(data['stream'] ?? '-').toString()} | ${_formatDate(createdAtMs)}',
          createdAtMs: createdAtMs,
          published: data['published'] != false,
          ref: doc.reference,
          data: _normalizeMap(data),
        );
      }),
      ...setDocs.map((doc) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;
        final createdAtMs = createdAt?.millisecondsSinceEpoch;
        final setNumber = (data['setNumber'] ?? '-').toString();
        final chapter = (data['chapterEn'] ?? '').toString();
        final stream = (data['stream'] ?? '').toString();
        final subject = (data['subject'] ?? '').toString();
        return _ActivityItem(
          type: _ActivityType.set,
          title: 'Set $setNumber${chapter.isEmpty ? '' : ' - $chapter'}',
          subtitle: '$stream $subject | ${_formatDate(createdAtMs)}'.trim(),
          createdAtMs: createdAtMs,
          published: data['published'] != false,
          ref: doc.reference,
          data: _normalizeMap(data),
        );
      }),
    ];

    items.sort((a, b) {
      final at = a.createdAtMs ?? 0;
      final bt = b.createdAtMs ?? 0;
      return bt.compareTo(at);
    });
    return items;
  }

  List<_ActivityItem> _buildActivitiesFromCache(List<Map<String, dynamic>> raw) {
    final out = raw
        .where((e) => (e['path'] ?? '').toString().trim().isNotEmpty)
        .map((e) {
      final data = e['data'];
      return _ActivityItem(
        type: e['type'] == 'set' ? _ActivityType.set : _ActivityType.course,
        title: (e['title'] ?? '').toString(),
        subtitle: (e['subtitle'] ?? '').toString(),
        createdAtMs: e['createdAtMs'] as int?,
        published: e['published'] != false,
        ref: FirebaseFirestore.instance
            .doc((e['path'] ?? '').toString())
            .withConverter<Map<String, dynamic>>(
              fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
              toFirestore: (value, _) => value,
            ),
        data: data is Map
            ? Map<String, dynamic>.from(data)
            : <String, dynamic>{},
      );
    }).toList();

    out.sort((a, b) => (b.createdAtMs ?? 0).compareTo(a.createdAtMs ?? 0));
    return out;
  }

  Map<String, dynamic> _toCacheItem(_ActivityItem item) {
    return <String, dynamic>{
      'type': item.type == _ActivityType.set ? 'set' : 'course',
      'title': item.title,
      'subtitle': item.subtitle,
      'createdAtMs': item.createdAtMs,
      'published': item.published,
      'path': item.ref.path,
      'data': item.data,
    };
  }

  Map<String, dynamic> _normalizeMap(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    source.forEach((key, value) {
      out[key] = _normalizeValue(value);
    });
    return out;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), _normalizeValue(val)));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    return value;
  }

  String _formatDate(int? millis) {
    if (millis == null) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
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
    final month = months[dt.month - 1];
    return '$month ${dt.day}, ${dt.year}';
  }
}

enum _ActivityType { course, set }

class _ActivityItem {
  const _ActivityItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createdAtMs,
    required this.published,
    required this.ref,
    required this.data,
  });

  final _ActivityType type;
  final String title;
  final String subtitle;
  final int? createdAtMs;
  final bool published;
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;

  String get path => ref.path;
}

class _ActivityEditScreen extends StatefulWidget {
  const _ActivityEditScreen({required this.item});

  final _ActivityItem item;

  @override
  State<_ActivityEditScreen> createState() => _ActivityEditScreenState();
}

class _ActivityEditScreenState extends State<_ActivityEditScreen> {
  static const List<String> _streams = <String>[
    'Class 9-10th',
    'Class 11-12th',
    'JEE',
    'NEET',
    'CUET',
    'College',
    'GATE',
    'SSC',
  ];

  static const List<String> _levels = <String>['Beginner', 'Medium', 'Hard'];

  final _formKey = GlobalKey<FormState>();
  final _newQuestionFormKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _chapterEnCtrl;
  late final TextEditingController _chapterHiCtrl;
  late final TextEditingController _setNumberCtrl;
  late final TextEditingController _newQuestionCtrl;
  late final TextEditingController _newOptACtrl;
  late final TextEditingController _newOptBCtrl;
  late final TextEditingController _newOptCCtrl;
  late final TextEditingController _newOptDCtrl;
  late final TextEditingController _newExplanationCtrl;

  String? _stream;
  String? _level;
  bool _published = true;
  bool _saving = false;
  bool _addingQuestion = false;
  int _newCorrectIndex = 0;

  bool get _isCourse => widget.item.type == _ActivityType.course;

  @override
  void initState() {
    super.initState();
    final data = widget.item.data;
    _titleCtrl = TextEditingController(
      text: _isCourse
          ? (data['courseName'] ?? '').toString()
          : (data['chapterEn'] ?? '').toString(),
    );
    _subtitleCtrl = TextEditingController(
      text: (data['subtitle'] ?? '').toString(),
    );
    _contentCtrl = TextEditingController(
      text: (data['content'] ?? '').toString(),
    );
    _subjectCtrl = TextEditingController(
      text: (data['subject'] ?? '').toString(),
    );
    _chapterEnCtrl = TextEditingController(
      text: (data['chapterEn'] ?? '').toString(),
    );
    _chapterHiCtrl = TextEditingController(
      text: (data['chapterHi'] ?? '').toString(),
    );
    _setNumberCtrl = TextEditingController(
      text: (data['setNumber'] ?? '').toString(),
    );
    _newQuestionCtrl = TextEditingController();
    _newOptACtrl = TextEditingController();
    _newOptBCtrl = TextEditingController();
    _newOptCCtrl = TextEditingController();
    _newOptDCtrl = TextEditingController();
    _newExplanationCtrl = TextEditingController();
    _stream = (data['stream'] ?? '').toString();
    if (_stream!.isEmpty || !_streams.contains(_stream)) {
      _stream = null;
    }
    _level = (data['level'] ?? '').toString();
    if (_level!.isEmpty || !_levels.contains(_level)) {
      _level = null;
    }
    _published = data['published'] != false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _contentCtrl.dispose();
    _subjectCtrl.dispose();
    _chapterEnCtrl.dispose();
    _chapterHiCtrl.dispose();
    _setNumberCtrl.dispose();
    _newQuestionCtrl.dispose();
    _newOptACtrl.dispose();
    _newOptBCtrl.dispose();
    _newOptCCtrl.dispose();
    _newOptDCtrl.dispose();
    _newExplanationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final payload = <String, dynamic>{
        'stream': _stream,
        'published': _published,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isCourse) {
        payload.addAll({
          'courseName': _titleCtrl.text.trim(),
          'subtitle': _subtitleCtrl.text.trim(),
          'content': _contentCtrl.text.trim(),
          'level': _level,
        });
      } else {
        payload.addAll({
          'subject': _subjectCtrl.text.trim(),
          'chapterEn': _chapterEnCtrl.text.trim(),
          'chapterHi': _chapterHiCtrl.text.trim(),
        });
        final parsed = int.tryParse(_setNumberCtrl.text.trim());
        if (parsed != null) {
          payload['setNumber'] = parsed;
        }
      }

      await widget.item.ref.update(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCourse ? 'Edit Course' : 'Edit Set'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _confirmDelete();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Published'),
                    value: _published,
                    onChanged: (v) => setState(() => _published = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _stream,
                    hint: const Text('Select stream'),
                    items: _streams
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _stream = v),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Please select stream' : null,
                    decoration: const InputDecoration(
                      labelText: 'Stream',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isCourse) ...[
                    _field(
                      controller: _titleCtrl,
                      label: 'Course Name',
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _subtitleCtrl,
                      label: 'Subtitle',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _level,
                      hint: const Text('Select level'),
                      items: _levels
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => _level = v),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Please select level'
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Level',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _contentCtrl,
                      label: 'Course Content',
                      maxLines: 5,
                    ),
                  ] else ...[
                    _field(
                      controller: _setNumberCtrl,
                      label: 'Set Number',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (int.tryParse(v.trim()) == null) return 'Enter number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _subjectCtrl,
                      label: 'Subject',
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _chapterEnCtrl,
                      label: 'Chapter (English)',
                    ),
                    const SizedBox(height: 12),
                    _field(
                      controller: _chapterHiCtrl,
                      label: 'Chapter (Hindi)',
                      validator: (_) => null,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _saving
                      ? const Center(child: CircularProgressIndicator())
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _save,
                            child: const Text('Save Changes'),
                          ),
                        ),
                ],
              ),
            ),
            if (!_isCourse) ...[
              const SizedBox(height: 22),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Questions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _buildQuestionsSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionsSection() {
    final questionsRef = widget.item.ref.collection('questions');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: questionsRef.orderBy('order').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Text('Failed to load questions: ${snap.error}');
        }
        final docs = snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (docs.isEmpty)
              const Text(
                'No question found in this set.',
                style: TextStyle(color: Colors.grey),
              ),
            ...docs.map((doc) {
              final data = doc.data();
              final question = (data['question'] ?? '').toString();
              final options = List<String>.from(
                (data['options'] as List?) ?? const [],
              );
              final correct = (data['correctIndex'] as int?) ?? -1;
              final cs = Theme.of(context).colorScheme;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Text(
                                'Q${(data['order'] ?? '-').toString()}: $question',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _editQuestion(doc, data);
                              } else if (value == 'delete') {
                                _confirmQuestionDelete(doc);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                textStyle: TextStyle(color: Colors.red),
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...options.asMap().entries.map((entry) {
                        final i = entry.key;
                        final label = String.fromCharCode(65 + i);
                        final isCorrect = i == correct;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? cs.secondaryContainer
                                  : cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$label. ${entry.value}${isCorrect ? '  (Correct)' : ''}',
                              style: TextStyle(
                                color: isCorrect
                                    ? cs.onSecondaryContainer
                                    : cs.onSurface,
                                fontWeight: isCorrect
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                ),
              );
            }),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Add New Question'),
              children: [
                Form(
                  key: _newQuestionFormKey,
                  child: Column(
                    children: [
                      _field(controller: _newQuestionCtrl, label: 'Question'),
                      const SizedBox(height: 10),
                      _field(controller: _newOptACtrl, label: 'Option A'),
                      const SizedBox(height: 10),
                      _field(controller: _newOptBCtrl, label: 'Option B'),
                      const SizedBox(height: 10),
                      _field(controller: _newOptCCtrl, label: 'Option C'),
                      const SizedBox(height: 10),
                      _field(controller: _newOptDCtrl, label: 'Option D'),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: _newCorrectIndex,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Correct: Option A')),
                          DropdownMenuItem(value: 1, child: Text('Correct: Option B')),
                          DropdownMenuItem(value: 2, child: Text('Correct: Option C')),
                          DropdownMenuItem(value: 3, child: Text('Correct: Option D')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _newCorrectIndex = v);
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _field(
                        controller: _newExplanationCtrl,
                        label: 'Explanation (Optional)',
                        maxLines: 3,
                        validator: (_) => null,
                      ),
                      const SizedBox(height: 12),
                      _addingQuestion
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _addQuestion(docs),
                                child: const Text('Add Question to This Set'),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _addQuestion(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!_newQuestionFormKey.currentState!.validate()) return;
    setState(() => _addingQuestion = true);

    try {
      int maxOrder = 0;
      for (final doc in docs) {
        final order = (doc.data()['order'] as int?) ?? 0;
        if (order > maxOrder) maxOrder = order;
      }
      final nextOrder = maxOrder + 1;
      final qRef = widget.item.ref.collection('questions').doc('q_$nextOrder');
      await qRef.set({
        'question': _newQuestionCtrl.text.trim(),
        'options': [
          _newOptACtrl.text.trim(),
          _newOptBCtrl.text.trim(),
          _newOptCCtrl.text.trim(),
          _newOptDCtrl.text.trim(),
        ],
        'correctIndex': _newCorrectIndex,
        'explanation': _newExplanationCtrl.text.trim(),
        'order': nextOrder,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await widget.item.ref.set({
        'questionCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _newQuestionFormKey.currentState?.reset();
      _newQuestionCtrl.clear();
      _newOptACtrl.clear();
      _newOptBCtrl.clear();
      _newOptCCtrl.clear();
      _newOptDCtrl.clear();
      _newExplanationCtrl.clear();
      setState(() => _newCorrectIndex = 0);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question added')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add question: $e')),
      );
    } finally {
      if (mounted) setState(() => _addingQuestion = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: const Text('Are you sure you want to delete this item?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    setState(() => _saving = true);

    try {
      if (_isCourse) {
        await widget.item.ref.delete();
      } else {
        final qSnap = await widget.item.ref.collection('questions').get();
        final deletedQuestions = qSnap.docs.length;
        for (final qDoc in qSnap.docs) {
          await qDoc.reference.delete();
        }
        final chapterRef = widget.item.ref.parent.parent;
        if (chapterRef != null) {
          await chapterRef.set({
            'setCount': FieldValue.increment(-1),
            'questionCount': FieldValue.increment(-deletedQuestions),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await widget.item.ref.delete();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deleted successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editQuestion(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> data,
  ) async {
    final qCtrl = TextEditingController(
      text: (data['question'] ?? '').toString(),
    );
    final options = List<String>.from((data['options'] as List?) ?? const []);
    final aCtrl = TextEditingController(text: options.length > 0 ? options[0] : '');
    final bCtrl = TextEditingController(text: options.length > 1 ? options[1] : '');
    final cCtrl = TextEditingController(text: options.length > 2 ? options[2] : '');
    final dCtrl = TextEditingController(text: options.length > 3 ? options[3] : '');
    final expCtrl = TextEditingController(
      text: (data['explanation'] ?? '').toString(),
    );
    int correctIndex = (data['correctIndex'] as int?) ?? 0;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Question'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field(controller: qCtrl, label: 'Question'),
                    const SizedBox(height: 10),
                    _field(controller: aCtrl, label: 'Option A'),
                    const SizedBox(height: 10),
                    _field(controller: bCtrl, label: 'Option B'),
                    const SizedBox(height: 10),
                    _field(controller: cCtrl, label: 'Option C'),
                    const SizedBox(height: 10),
                    _field(controller: dCtrl, label: 'Option D'),
                    const SizedBox(height: 10),
                    StatefulBuilder(
                      builder: (context, setLocalState) {
                        return DropdownButtonFormField<int>(
                          value: correctIndex,
                          items: const [
                            DropdownMenuItem(
                              value: 0,
                              child: Text('Correct: Option A'),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text('Correct: Option B'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('Correct: Option C'),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text('Correct: Option D'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setLocalState(() => correctIndex = v);
                            }
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _field(
                      controller: expCtrl,
                      label: 'Explanation (Optional)',
                      maxLines: 3,
                      validator: (_) => null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await doc.reference.set({
                  'question': qCtrl.text.trim(),
                  'options': [
                    aCtrl.text.trim(),
                    bCtrl.text.trim(),
                    cCtrl.text.trim(),
                    dCtrl.text.trim(),
                  ],
                  'correctIndex': correctIndex,
                  'explanation': expCtrl.text.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (!context.mounted) return;
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    qCtrl.dispose();
    aCtrl.dispose();
    bCtrl.dispose();
    cCtrl.dispose();
    dCtrl.dispose();
    expCtrl.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question updated')),
      );
    }
  }

  Future<void> _confirmQuestionDelete(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Question'),
          content: const Text('Are you sure you want to delete this question?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await doc.reference.delete();
      await widget.item.ref.set({
        'questionCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator ??
          (v) => v == null || v.trim().isEmpty ? 'Required field' : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
