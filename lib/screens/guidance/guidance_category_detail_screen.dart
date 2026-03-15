import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/guidance/tests/guidance_test_definition.dart';
import '../../models/survey_model.dart';
import '../school/survey/survey_response_screen.dart';
import 'guidance_test_publish_screen.dart';
import 'guidance_test_history_screen.dart';

class GuidanceCategoryDetailScreen extends StatefulWidget {
  final String title;
  final String description;
  final List<GuidanceTestDefinition> tests;
  final String institutionId;
  final String schoolTypeId;

  const GuidanceCategoryDetailScreen({
    Key? key,
    required this.title,
    required this.description,
    required this.tests,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<GuidanceCategoryDetailScreen> createState() =>
      _GuidanceCategoryDetailScreenState();
}

class _GuidanceCategoryDetailScreenState
    extends State<GuidanceCategoryDetailScreen> {
  bool _isListView = false;
  String _searchQuery = '';
  late List<GuidanceTestDefinition> _displayTests;

  @override
  void initState() {
    super.initState();
    _displayTests = List.from(widget.tests);
    _displayTests.sort((a, b) => a.title.compareTo(b.title));
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _displayTests = widget.tests
          .where(
            (t) =>
                t.title.toLowerCase().contains(_searchQuery) ||
                t.description.toLowerCase().contains(_searchQuery),
          )
          .toList();
      _displayTests.sort((a, b) => a.title.compareTo(b.title));
    });
  }

  void _onTestSelected(GuidanceTestDefinition test, String action) async {
    if (action == 'preview') {
      final dummySurvey = test.createSurvey(
        institutionId: 'preview',
        schoolTypeId: 'preview',
        authorId: 'preview',
        targetIds: [],
        targetType: SurveyTargetType.students,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => SurveyResponseScreen(survey: dummySurvey),
        ),
      );
    } else if (action == 'history') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => GuidanceTestHistoryScreen(
            templateId: test.id,
            templateTitle: test.title,
            institutionId: widget.institutionId,
          ),
        ),
      );
    } else if (action == 'publish') {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => GuidanceTestPublishScreen(
            test: test,
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            authorId: userId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: GoogleFonts.inter()),
        actions: [
          IconButton(
            icon: Icon(_isListView ? Icons.grid_view : Icons.list),
            onPressed: () => setState(() => _isListView = !_isListView),
            tooltip: _isListView ? 'Kart Görünümü' : 'Liste Görünümü',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              _buildHeader(),
              _buildSearchBox(),
              Expanded(
                child: _isListView ? _buildListView() : _buildGridView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.indigo.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.description,
            style: TextStyle(
              color: Colors.indigo.shade800,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        onChanged: _onSearch,
        decoration: InputDecoration(
          hintText: 'Test ara...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  Widget _buildListView() {
    if (_displayTests.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _displayTests.length,
      itemBuilder: (context, index) {
        final test = _displayTests[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.assignment_ind,
              color: Colors.indigo,
              size: 20,
            ),
          ),
          title: Text(
            test.title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) => _onTestSelected(test, val),
            itemBuilder: (ctx) => [
              _buildPopupItem(
                'publish',
                Icons.send,
                'Gönder',
                color: Colors.indigo,
              ),
              _buildPopupItem('preview', Icons.visibility, 'Önizle'),
              _buildPopupItem('history', Icons.history, 'Geçmiş'),
            ],
          ),
          onTap: () => _onTestSelected(test, 'publish'),
        );
      },
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.grey, size: 20),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    if (_displayTests.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _displayTests.length,
      itemBuilder: (context, index) {
        final test = _displayTests[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.assignment_ind,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              test.title,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              test.description,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => _onTestSelected(test, 'publish'),
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Öğrencilere Gönder'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.visibility,
                          size: 22,
                          color: Colors.grey,
                        ),
                        onPressed: () => _onTestSelected(test, 'preview'),
                        tooltip: 'Önizle',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.history,
                          size: 22,
                          color: Colors.grey,
                        ),
                        onPressed: () => _onTestSelected(test, 'history'),
                        tooltip: 'Geçmiş',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Test bulunamadı.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
