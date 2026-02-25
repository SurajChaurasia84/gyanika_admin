import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/local_cache_service.dart';

class CreateSetsScreen extends StatefulWidget {
  const CreateSetsScreen({super.key});

  @override
  State<CreateSetsScreen> createState() => _CreateSetsScreenState();
}

class _CreateSetsScreenState extends State<CreateSetsScreen> {
  static const String _subjectCountsCacheKey = 'subject_counts_v1';

  final Map<String, List<String>> _streams = {
    'Class 9-10th': [
      'Hindi',
      'English',
      'Mathematics',
      'Science',
      'Social Science',
    ],
    'Class 11-12th': [
      'Hindi',
      'English',
      'Mathematics',
      'Physics',
      'Chemistry',
      'Biology',
    ],
    'JEE': ['Mathematics', 'Physics', 'Chemistry'],
    'NEET': ['Botany', 'Zoology', 'Physics', 'Chemistry'],
    'CUET': ['Language', 'Mathematics', 'Physics', 'Chemistry'],
    'College': ['B.Tech', 'B.Sc', 'BCA', 'BA'],
    'GATE': [
      'Computer Science & IT',
      'Mechanical Engineering',
      'Electrical Engineering',
      'Electronics & Communication',
      'Civil Engineering',
    ],
    'SSC': [
      'Reasoning',
      'Quantitative Aptitude',
      'General Awareness',
      'English Comprehension',
    ],
  };

  final TextEditingController _chapterEnCtrl = TextEditingController();
  final TextEditingController _chapterHiCtrl = TextEditingController();
  final TextEditingController _questionCtrl = TextEditingController();
  final TextEditingController _optACtrl = TextEditingController();
  final TextEditingController _optBCtrl = TextEditingController();
  final TextEditingController _optCCtrl = TextEditingController();
  final TextEditingController _optDCtrl = TextEditingController();
  final TextEditingController _explanationCtrl = TextEditingController();

  final List<Map<String, dynamic>> _questions = [];
  final Map<String, Future<Map<String, int>>> _subjectCountsFutures = {};
  final Map<String, Map<String, int>> _subjectCountsLocal = {};

  bool _saving = false;
  bool _keepScreenOn = false;
  int _step = 0;
  int _correctIndex = 0;
  int _nextSetNumber = 1;
  String? _selectedStream;
  String? _selectedSubject;
  String? _selectedChapterId;
  String? _selectedChapterEn;
  String? _selectedChapterHi;
  String? _selectedSetLanguage;

  static const int _minQuestions = 4;

  @override
  void initState() {
    super.initState();
    _loadSubjectCountsFromCache();
  }

  @override
  void dispose() {
    _chapterEnCtrl.dispose();
    _chapterHiCtrl.dispose();
    _questionCtrl.dispose();
    _optACtrl.dispose();
    _optBCtrl.dispose();
    _optCCtrl.dispose();
    _optDCtrl.dispose();
    _explanationCtrl.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _loadSubjectCountsFromCache() {
    final raw = LocalCacheService.getJsonMap(_subjectCountsCacheKey);
    if (raw == null || raw.isEmpty) return;

    raw.forEach((key, value) {
      if (value is Map) {
        _subjectCountsLocal[key] = {
          'setCount': _toInt(value['setCount']),
          'questionCount': _toInt(value['questionCount']),
        };
      }
    });

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _persistSubjectCountsToCache() async {
    final payload = <String, Map<String, int>>{};
    _subjectCountsLocal.forEach((key, value) {
      payload[key] = {
        'setCount': value['setCount'] ?? 0,
        'questionCount': value['questionCount'] ?? 0,
      };
    });
    await LocalCacheService.saveJson(_subjectCountsCacheKey, payload);
  }

  void _setSubjectCountsLocal(String docId, int setCount, int questionCount) {
    final normalized = {
      'setCount': setCount < 0 ? 0 : setCount,
      'questionCount': questionCount < 0 ? 0 : questionCount,
    };
    _subjectCountsLocal[docId] = normalized;
    _subjectCountsFutures[docId] = Future.value(normalized);
    _persistSubjectCountsToCache();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _toggleKeepScreenOn(bool value) async {
    setState(() => _keepScreenOn = value);
    await WakelockPlus.toggle(enable: value);
  }

  Future<bool> _handleBackNavigation() async {
    if (_step > 0) {
      setState(() => _step = _step - 1);
      return false;
    }
    return true;
  }

  void _selectCard({
    required String stream,
    required String subject,
  }) {
    setState(() {
      _selectedStream = stream;
      _selectedSubject = subject;
      _selectedChapterId = null;
      _selectedChapterEn = null;
      _selectedChapterHi = null;
      _selectedSetLanguage = null;
      _chapterEnCtrl.clear();
      _chapterHiCtrl.clear();
      _step = 1;
    });
  }

  String _cardDocId(String stream, String subject) {
    final normalized = '${stream}__$subject'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized;
  }

  DocumentReference<Map<String, dynamic>> _cardRef() {
    return FirebaseFirestore.instance
        .collection('set_cards')
        .doc(_cardDocId(_selectedStream!, _selectedSubject!));
  }

  CollectionReference<Map<String, dynamic>> _chaptersRef() {
    return _cardRef().collection('chapters');
  }

  Future<void> _loadNextSetNumber() async {
    final chapterId = _selectedChapterId;
    if (chapterId == null) return;
    final setsSnap = await _chaptersRef()
        .doc(chapterId)
        .collection('sets')
        .orderBy('setNumber', descending: true)
        .limit(1)
        .get();
    final last = setsSnap.docs.isNotEmpty
        ? (setsSnap.docs.first.data()['setNumber'] as int? ?? 0)
        : 0;
    if (!mounted) return;
    setState(() => _nextSetNumber = last + 1);
  }

  Future<void> _ensureCardDoc() async {
    await _cardRef().set({
      'stream': _selectedStream,
      'subject': _selectedSubject,
      'label': '${_selectedStream!} (${_selectedSubject!})',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _selectExistingChapter(QueryDocumentSnapshot chapterDoc) async {
    final data = chapterDoc.data() as Map<String, dynamic>;
    setState(() {
      _selectedChapterId = chapterDoc.id;
      _selectedChapterEn = (data['chapterEn'] ?? '').toString();
      _selectedChapterHi = (data['chapterHi'] ?? '').toString();
      _selectedSetLanguage = null;
      _chapterEnCtrl.clear();
      _chapterHiCtrl.clear();
    });
    await _loadNextSetNumber();
  }

  Future<void> _continueToQuestions() async {
    if (_saving) return;
    final newChapterEn = _chapterEnCtrl.text.trim();
    final newChapterHi = _chapterHiCtrl.text.trim();
    final hasExisting = _selectedChapterId != null;
    final wantsNew = newChapterEn.isNotEmpty;

    if (!hasExisting && !wantsNew) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select existing chapter or add new chapter name'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _ensureCardDoc();

      if (wantsNew) {
        final chapterDoc = await _chaptersRef().add({
          'chapterEn': newChapterEn,
          'chapterHi': newChapterHi,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _selectedChapterId = chapterDoc.id;
        _selectedChapterEn = newChapterEn;
        _selectedChapterHi = newChapterHi;
      }

      await _loadNextSetNumber();
      if (!mounted) return;
      setState(() => _step = 2);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to continue: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addQuestion() {
    final question = _questionCtrl.text.trim();
    final a = _optACtrl.text.trim();
    final b = _optBCtrl.text.trim();
    final c = _optCCtrl.text.trim();
    final d = _optDCtrl.text.trim();
    if (question.isEmpty || a.isEmpty || b.isEmpty || c.isEmpty || d.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question and all options are required')),
      );
      return;
    }

    setState(() {
      _questions.add({
        'question': question,
        'options': [a, b, c, d],
        'correctIndex': _correctIndex,
        'explanation': _explanationCtrl.text.trim(),
      });
      _questionCtrl.clear();
      _optACtrl.clear();
      _optBCtrl.clear();
      _optCCtrl.clear();
      _optDCtrl.clear();
      _explanationCtrl.clear();
      _correctIndex = 0;
    });
  }

  Future<void> _publishSet() async {
    if (_saving) return;
    if (_questions.length < _minQuestions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum 4 questions required in a set')),
      );
      return;
    }
    final stream = _selectedStream;
    final subject = _selectedSubject;
    final chapterId = _selectedChapterId;
    if (stream == null || subject == null || chapterId == null) return;
    if (_selectedSetLanguage == null || _selectedSetLanguage!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select set language')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _ensureCardDoc();
      final chapterRef = _chaptersRef().doc(chapterId);
      final setRef = chapterRef.collection('sets').doc('set_$_nextSetNumber');
      final nowTs = FieldValue.serverTimestamp();

      await setRef.set({
        'setNumber': _nextSetNumber,
        'stream': stream,
        'subject': subject,
        'language': _selectedSetLanguage,
        'chapterEn': _selectedChapterEn ?? '',
        'chapterHi': _selectedChapterHi ?? '',
        'questionCount': _questions.length,
        'published': true,
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': nowTs,
        'updatedAt': nowTs,
      });

      final batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < _questions.length; i++) {
        final q = _questions[i];
        final qRef = setRef.collection('questions').doc('q_${i + 1}');
        batch.set(qRef, {
          'question': q['question'],
          'options': q['options'],
          'correctIndex': q['correctIndex'],
          'explanation': q['explanation'],
          'order': i + 1,
          'createdAt': nowTs,
        });
      }
      batch.set(chapterRef, {
        'updatedAt': nowTs,
        'setCount': FieldValue.increment(1),
        'questionCount': FieldValue.increment(_questions.length),
      }, SetOptions(merge: true));
      batch.set(_cardRef(), {
        'updatedAt': nowTs,
        'setCount': FieldValue.increment(1),
        'questionCount': FieldValue.increment(_questions.length),
      }, SetOptions(merge: true));
      await batch.commit();
      final docId = _cardDocId(stream, subject);
      final existing = _subjectCountsLocal[docId];
      final nextSetCount = (existing?['setCount'] ?? 0) + 1;
      final nextQuestionCount =
          (existing?['questionCount'] ?? 0) + _questions.length;
      _setSubjectCountsLocal(docId, nextSetCount, nextQuestionCount);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Set $_nextSetNumber published successfully')),
      );
      setState(() {
        _questions.clear();
        _selectedSetLanguage = null;
      });
      await _loadNextSetNumber();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to publish set: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBackNavigation,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          title: const Text('Create Sets'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final canPop = await _handleBackNavigation();
              if (canPop && mounted) {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            Row(
              children: [
                const Text('Keep on', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _keepScreenOn,
                  onChanged: _toggleKeepScreenOn,
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          child: _step == 0
              ? _buildSubjectCards()
              : _step == 1
              ? _buildChapterStep()
              : _buildQuestionStep(),
        ),
      ),
    );
  }

  Widget _buildSubjectCards() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: _streams.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.key,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(.7),
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entry.value.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.9,
              ),
              itemBuilder: (_, i) {
                final subject = entry.value[i];
                final bgColor = Theme.of(context).colorScheme.surfaceContainer;
                final isDarkBg =
                    ThemeData.estimateBrightnessForColor(bgColor) ==
                    Brightness.dark;
                final titleColor = isDarkBg ? Colors.white : Colors.black87;
                final metaColor = isDarkBg
                    ? Colors.white.withOpacity(.82)
                    : Colors.black87.withOpacity(.72);
                final countsFuture = _subjectCountsFutureFor(
                  stream: entry.key,
                  subject: subject,
                );
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _selectCard(stream: entry.key, subject: subject),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FutureBuilder<Map<String, int>>(
                      future: countsFuture,
                      builder: (context, snap) {
                        final setCount = snap.data?['setCount'] ?? 0;
                        final questionCount = snap.data?['questionCount'] ?? 0;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$setCount sets • $questionCount questions',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: metaColor,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        );
      }).toList(),
    );
  }

  Future<Map<String, int>> _subjectCountsFutureFor({
    required String stream,
    required String subject,
  }) {
    final docId = _cardDocId(stream, subject);
    final local = _subjectCountsLocal[docId];
    if (local != null) {
      return Future.value(local);
    }
    return _subjectCountsFutures.putIfAbsent(
      docId,
      () => _resolveSubjectCounts(docId),
    );
  }

  Future<Map<String, int>> _resolveSubjectCounts(String cardDocId) async {
    final cardRef = FirebaseFirestore.instance.collection('set_cards').doc(cardDocId);
    final cardSnap = await cardRef.get();
    final cardData = cardSnap.data();
    final existingSetCount = (cardData?['setCount'] as num?)?.toInt();
    final existingQuestionCount = (cardData?['questionCount'] as num?)?.toInt();
    if (existingSetCount != null && existingQuestionCount != null) {
      _setSubjectCountsLocal(cardDocId, existingSetCount, existingQuestionCount);
      return {
        'setCount': existingSetCount,
        'questionCount': existingQuestionCount,
      };
    }

    final chaptersSnap = await cardRef.collection('chapters').get();
    int totalSets = 0;
    int totalQuestions = 0;

    for (final chapterDoc in chaptersSnap.docs) {
      final chapterData = chapterDoc.data();
      int setCount = (chapterData['setCount'] as num?)?.toInt() ?? 0;
      int questionCount = (chapterData['questionCount'] as num?)?.toInt() ?? 0;

      if (setCount == 0 && questionCount == 0) {
        final setsSnap = await chapterDoc.reference.collection('sets').get();
        setCount = setsSnap.docs.length;
        questionCount = 0;
        for (final setDoc in setsSnap.docs) {
          questionCount += (setDoc.data()['questionCount'] as num?)?.toInt() ?? 0;
        }
      }

      totalSets += setCount;
      totalQuestions += questionCount;
    }

    await cardRef.set({
      'setCount': totalSets,
      'questionCount': totalQuestions,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _setSubjectCountsLocal(cardDocId, totalSets, totalQuestions);

    return {
      'setCount': totalSets,
      'questionCount': totalQuestions,
    };
  }

  Widget _buildChapterStep() {
    final stream = _selectedStream;
    final subject = _selectedSubject;
    if (stream == null || subject == null) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Selected Card: $stream ($subject)',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'Choose existing chapter or add new chapter',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _chaptersRef().orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No chapter found. Add a new chapter below.',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Existing Chapters',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...docs.map((doc) {
                  final data = doc.data();
                  final chapterEn = (data['chapterEn'] ?? '').toString();
                  final chapterHi = (data['chapterHi'] ?? '').toString();
                  final selected = _selectedChapterId == doc.id;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(chapterEn),
                      subtitle: chapterHi.trim().isEmpty ? null : Text(chapterHi),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.chevron_right),
                      onTap: () => _selectExistingChapter(doc),
                    ),
                  );
                }),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 10),
        TextField(
          controller: _chapterEnCtrl,
          decoration: const InputDecoration(
            labelText: 'Chapter Name (English)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _chapterHiCtrl,
          decoration: const InputDecoration(
            labelText: 'Chapter Name (Hindi - Optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (_saving)
          const Center(child: CircularProgressIndicator())
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _continueToQuestions,
              child: const Text('Next'),
            ),
          ),
      ],
    );
  }

  Widget _buildQuestionStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${_selectedStream!} (${_selectedSubject!})',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Chapter: ${_selectedChapterEn ?? ''}${(_selectedChapterHi ?? '').trim().isNotEmpty ? ' / ${_selectedChapterHi!}' : ''}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Language',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
            const Spacer(),
            SizedBox(
              width: 90,
              child: DropdownButtonFormField<String>(
                value: _selectedSetLanguage,
                hint: const Text('Select'),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'English', child: Text('English')),
                  DropdownMenuItem(value: 'Hindi', child: Text('Hindi')),
                ],
                onChanged: (value) {
                  setState(() => _selectedSetLanguage = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Set $_nextSetNumber',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Minimum $_minQuestions questions required',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _questionCtrl,
          decoration: const InputDecoration(
            labelText: 'Question',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _optACtrl,
          decoration: const InputDecoration(
            labelText: 'Option A',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _optBCtrl,
          decoration: const InputDecoration(
            labelText: 'Option B',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _optCCtrl,
          decoration: const InputDecoration(
            labelText: 'Option C',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _optDCtrl,
          decoration: const InputDecoration(
            labelText: 'Option D',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: _correctIndex,
          decoration: const InputDecoration(
            labelText: 'Correct Option',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Option A')),
            DropdownMenuItem(value: 1, child: Text('Option B')),
            DropdownMenuItem(value: 2, child: Text('Option C')),
            DropdownMenuItem(value: 3, child: Text('Option D')),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() => _correctIndex = v);
            }
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _explanationCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Explanation (Optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _addQuestion,
          icon: const Icon(Icons.add),
          label: const Text('Add Question'),
        ),
        const SizedBox(height: 14),
        Text(
          'Added Questions (${_questions.length})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ..._questions.asMap().entries.map((entry) {
          final index = entry.key;
          final q = entry.value;
          final options = List<String>.from(q['options'] as List);
          final correct = q['correctIndex'] as int;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(q['question'].toString()),
              subtitle: Text('Correct: ${options[correct]}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _questions.removeAt(index)),
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        if (_saving)
          const Center(child: CircularProgressIndicator())
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _publishSet,
              child: Text('Publish Set $_nextSetNumber'),
            ),
          ),
      ],
    );
  }
}
