import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/school/book_model.dart';
import '../../models/school/book_assignment_model.dart';
import '../../services/assessment_service.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';

class BookManagementScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const BookManagementScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  }) : super(key: key);

  @override
  _BookManagementScreenState createState() => _BookManagementScreenState();
}

class _BookManagementScreenState extends State<BookManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  // Data
  List<Book> _allBooks = [];
  List<Book> _filteredBooks = [];
  List<String> _branches = [];
  List<String> _classLevels = [];

  // Filters
  String? _selectedType; // 'reading', 'questionBank'
  String? _selectedBranch;
  String _searchQuery = '';

  // Selection
  Book? _selectedBook;
  Book? _selectedAssignmentBook;
  bool _isCreatingNew = false;
  int _newCreationKey = 0;
  bool _isLoading = true;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadAll();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
          _applyFilters();
        });
      }
    });
  }

  void _applyFilters() {
    var books = _allBooks;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      books = books
          .where(
            (b) =>
                b.name.toLowerCase().contains(q) ||
                (b.author?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    if (_selectedType != null) {
      books = books.where((b) => b.type.name == _selectedType).toList();
    }

    if (_selectedBranch != null) {
      books = books.where((b) => b.branch == _selectedBranch).toList();
    }

    _filteredBooks = books;
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // 1. Load Metadata (Branches & Levels)
    try {
      final branches = await AssessmentService().getAvailableBranches(
        widget.institutionId,
      );
      final stDoc = await FirebaseFirestore.instance
          .collection('school_types')
          .doc(widget.schoolTypeId)
          .get();

      List<String> levels = [];
      if (stDoc.exists && stDoc.data()?['activeGrades'] != null) {
        levels = List<String>.from(
          stDoc.data()!['activeGrades'].map((e) => e.toString()),
        );
      }

      if (mounted) {
        setState(() {
          _branches = branches;
          _classLevels = levels;
        });
      }
    } catch (e) {
      print('Error loading metadata: $e');
    }

    // 2. Load Books
    try {
      final bookSnap = await FirebaseFirestore.instance
          .collection('books')
          .where('institutionId', isEqualTo: widget.institutionId)
          .orderBy('createdAt', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _allBooks = bookSnap.docs
              .map((doc) => Book.fromMap(doc.data(), doc.id))
              .toList();
          _applyFilters();
        });
      }
    } catch (e) {
      print('Error loading book list: $e');
      if (mounted && e.toString().contains('permission-denied')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Veri erişim yetkisi reddedildi. Lütfen yöneticiye başvurun.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _selectBook(Book book) {
    setState(() {
      if (_tabController.index == 0) {
        _selectedBook = book;
        _isCreatingNew = false;
      } else {
        _selectedAssignmentBook = book;
      }
    });
  }

  void _createNew() {
    setState(() {
      _selectedBook = null;
      _isCreatingNew = true;
      _newCreationKey++;
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectedBook = null;
      _isCreatingNew = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kitap İşlemleri & Kütüphane',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            Text(
              widget.schoolTypeName,
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.indigo.shade700,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Kitap Tanımları'),
            Tab(text: 'Kitap Atamaları'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: NeverScrollableScrollPhysics(),
        children: [_buildDefinitionsTab(), _buildAssignmentsTab()],
      ),
    );
  }

  Widget _buildDefinitionsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;

        if (isMobile) {
          if (_selectedBook != null || _isCreatingNew) {
            return BookDetailView(
              key: ValueKey(_selectedBook?.id ?? 'new_$_newCreationKey'),
              book: _selectedBook,
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
              branches: _branches,
              schoolTypeLevels: _classLevels,
              onSaved: () {
                _cancelSelection();
                _loadAll();
              },
              onCancelled: _cancelSelection,
              isMobile: true,
            );
          }
          return Column(
            children: [
              _buildLeftPanelHeader(),
              Expanded(child: _buildBookList()),
              _buildMobileAddFab(),
            ],
          );
        }

        // Desktop View
        return Row(
          children: [
            // Left Panel
            Container(
              width: 380,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                children: [
                  _buildLeftPanelHeader(),
                  Expanded(child: _buildBookList()),
                  _buildDesktopAddButton(),
                ],
              ),
            ),
            // Right Panel
            Expanded(
              child: Container(
                color: Colors.grey.shade50,
                child: (_selectedBook != null || _isCreatingNew)
                    ? BookDetailView(
                        key: ValueKey(
                          _selectedBook?.id ?? 'new_$_newCreationKey',
                        ),
                        book: _selectedBook,
                        institutionId: widget.institutionId,
                        schoolTypeId: widget.schoolTypeId,
                        branches: _branches,
                        schoolTypeLevels: _classLevels,
                        onSaved: () {
                          // In desktop we can stay or refresh
                          _loadAll();
                        },
                        onCancelled: _cancelSelection,
                        isMobile: false,
                      )
                    : _buildPlaceholder(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLeftPanelHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Kitap ara...',
              hintStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.search, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildExcelActionButton(
                  icon: Icons.download_for_offline_outlined,
                  label: 'Şablon İndir',
                  onTap: _downloadExcelTemplate,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildExcelActionButton(
                  icon: Icons.upload_file_rounded,
                  label: 'Excel Yükle',
                  onTap: _importExcelData,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildHeaderFilterChip(
                  'Tümü',
                  _selectedType == null && _selectedBranch == null,
                  () {
                    setState(() {
                      _selectedType = null;
                      _selectedBranch = null;
                      _applyFilters();
                    });
                  },
                ),
                SizedBox(width: 8),
                _buildHeaderFilterChip(
                  'Soru Bankası',
                  _selectedType == 'questionBank',
                  () {
                    setState(() {
                      _selectedType = _selectedType == 'questionBank'
                          ? null
                          : 'questionBank';
                      _applyFilters();
                    });
                  },
                ),
                SizedBox(width: 8),
                _buildHeaderFilterChip(
                  'Okuma Kitabı',
                  _selectedType == 'reading',
                  () {
                    setState(() {
                      _selectedType = _selectedType == 'reading'
                          ? null
                          : 'reading';
                      _applyFilters();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderFilterChip(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.white : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.indigo.shade900 : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildExcelActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadExcelTemplate() async {
    try {
      var excel = excel_pkg.Excel.createExcel();
      excel_pkg.Sheet sheet = excel['Kitap_Yukleme_Sablonu'];
      excel.delete('Sheet1');

      List<String> headers = [
        'Kitap Adı',
        'Tür (SB veya OK)',
        'Branş',
        'Yazar (Sadece OK)',
        'Sayfa Sayısı (Sadece OK)',
        'Konu Adı',
        'Alt Konu Adı (Boş bırakılabilir)',
        'Test Sayısı',
        'Soru Sayıları (Örn: 20,20,15)',
      ];

      for (var i = 0; i < headers.length; i++) {
        var cell = sheet.cell(
          excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = excel_pkg.TextCellValue(headers[i]);
      }

      // Add example rows to show hierarchy
      List<List<String>> exampleRows = [
        [
          'Matematik Soru Bankası',
          'SB',
          'Matematik',
          '',
          '',
          'ÜNİTE 1: SAYILAR',
          'Doğal Sayılar',
          '2',
          '20, 20',
        ],
        [
          'Matematik Soru Bankası',
          'SB',
          'Matematik',
          '',
          '',
          'ÜNİTE 1: SAYILAR',
          'Tam Sayılar',
          '1',
          '15',
        ],
        [
          'Matematik Soru Bankası',
          'SB',
          'Matematik',
          '',
          '',
          'ÜNİTE 2: DENKLEMLER',
          '1. Derece Denklemler',
          '3',
          '20, 20, 20',
        ],
        ['Sefiller', 'OK', 'Türkçe', 'Victor Hugo', '450', '', '', '', ''],
      ];

      for (var rIdx = 0; rIdx < exampleRows.length; rIdx++) {
        var rowData = exampleRows[rIdx];
        for (var cIdx = 0; cIdx < rowData.length; cIdx++) {
          sheet
              .cell(
                excel_pkg.CellIndex.indexByColumnRow(
                  columnIndex: cIdx,
                  rowIndex: rIdx + 1,
                ),
              )
              .value = excel_pkg.TextCellValue(
            rowData[cIdx],
          );
        }
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        await FileSaver.instance.saveFile(
          name: 'kitap_yukleme_sablonu',
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Şablon indirildi.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Şablon indirilirken hata oluştu: $e')),
      );
    }
  }

  Future<void> _importExcelData() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result != null) {
      try {
        var bytes = result.files.first.bytes;
        if (bytes == null) return;

        var excel = excel_pkg.Excel.decodeBytes(bytes);
        var sheetName = excel.sheets.keys.first;
        var table = excel.sheets[sheetName]!;

        Map<String, Book> booksToSave = {};

        for (var i = 1; i < table.maxRows; i++) {
          var row = table.rows[i];
          if (row.isEmpty || row[0] == null) continue;

          String bookName = row[0]?.value?.toString().trim() ?? '';
          if (bookName.isEmpty) continue;

          String typeStr = row[1]?.value?.toString().trim().toUpperCase() ?? '';
          BookType type = typeStr == 'SB'
              ? BookType.questionBank
              : BookType.reading;
          String branch = row[2]?.value?.toString().trim() ?? '';
          String author = row[3]?.value?.toString().trim() ?? '';
          int? pageCount = int.tryParse(row[4]?.value?.toString() ?? '');

          String topicName = row[5]?.value?.toString().trim() ?? '';
          String subtopicName = row[6]?.value?.toString().trim() ?? '';
          int testCount = int.tryParse(row[7]?.value?.toString() ?? '') ?? 0;
          String questionsStr = row[8]?.value?.toString().trim() ?? '';

          List<int> questionsPerTest = questionsStr.isNotEmpty
              ? questionsStr
                    .split(',')
                    .map((e) => int.tryParse(e.trim()) ?? 20)
                    .toList()
              : List.filled(testCount, 20);

          if (!booksToSave.containsKey(bookName)) {
            booksToSave[bookName] = Book(
              id: '',
              institutionId: widget.institutionId,
              name: bookName,
              type: type,
              branch: type == BookType.questionBank ? branch : null,
              author: type == BookType.reading ? author : null,
              pageCount: type == BookType.reading ? pageCount : null,
              classLevels: [],
              topics: [],
              createdAt: DateTime.now(),
            );
          }

          if (type == BookType.questionBank && topicName.isNotEmpty) {
            var book = booksToSave[bookName]!;
            BookTopic? topic;
            for (var t in book.topics) {
              if (t.name == topicName) {
                topic = t;
                break;
              }
            }

            if (topic == null) {
              topic = BookTopic(
                id:
                    DateTime.now().millisecondsSinceEpoch.toString() +
                    i.toString(),
                name: topicName,
                subtopics: [],
              );
              book.topics.add(topic);
            }

            if (subtopicName.isNotEmpty) {
              topic.subtopics.add(
                BookSubtopic(
                  id:
                      DateTime.now().millisecondsSinceEpoch.toString() +
                      i.toString() +
                      "s",
                  name: subtopicName,
                  testCount: testCount,
                  questionsPerTestList: questionsPerTest,
                ),
              );
            } else {
              topic.testCount = testCount;
              topic.questionsPerTestList = questionsPerTest;
            }
          }
        }

        if (booksToSave.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Yüklenecek geçerli veri bulunamadı.'),
            ),
          );
          return;
        }

        int count = 0;
        final batch = FirebaseFirestore.instance.batch();
        for (var book in booksToSave.values) {
          var docRef = FirebaseFirestore.instance.collection('books').doc();
          batch.set(docRef, book.toMap());
          count++;
        }
        await batch.commit();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count kitap başarıyla yüklendi.')),
        );
        _loadAll();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Yükleme hatası: $e')));
      }
    }
  }

  Widget _buildBookList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final books = _filteredBooks;

    if (books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 64,
              color: Colors.grey.shade200,
            ),
            SizedBox(height: 16),
            Text(
              'Kayıtlı kitap bulunamadı.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(12),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final currentSelection = _tabController.index == 0
            ? _selectedBook
            : _selectedAssignmentBook;
        final isSelected = currentSelection?.id == book.id;
        final isQB = book.type == BookType.questionBank;

        return Card(
          elevation: isSelected ? 4 : 0.5,
          margin: EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(color: Colors.indigo, width: 1.5)
                : BorderSide.none,
          ),
          color: isSelected ? Colors.indigo.shade50 : Colors.white,
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: isQB
                  ? Colors.blue.shade50
                  : Colors.green.shade50,
              child: Icon(
                isQB ? Icons.quiz : Icons.menu_book,
                color: isQB ? Colors.blue : Colors.green,
                size: 20,
              ),
            ),
            title: Text(
              book.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isSelected ? Colors.indigo.shade900 : Colors.black87,
              ),
            ),
            subtitle: Text(
              isQB
                  ? (book.branch ?? 'Branşsız')
                  : (book.author ?? 'Yazar Bilgisi Yok'),
              style: TextStyle(fontSize: 11),
            ),
            onTap: () => _selectBook(book),
            trailing: isSelected
                ? Icon(Icons.chevron_right, color: Colors.indigo)
                : null,
          ),
        );
      },
    );
  }

  Widget _buildDesktopAddButton() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ElevatedButton.icon(
        onPressed: _createNew,
        icon: Icon(Icons.add_rounded),
        label: Text('Yeni Kitap Tanımla'),
        style: ElevatedButton.styleFrom(
          minimumSize: Size(double.infinity, 50),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileAddFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: FloatingActionButton.extended(
        onPressed: _createNew,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Yeni Kitap',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        elevation: 4,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Icon(
              Icons.touch_app_rounded,
              size: 80,
              color: Colors.indigo.shade100,
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Detayları görmek için soldan bir kitap seçin',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'veya yeni bir kitap tanımlayın.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;

        if (isMobile) {
          if (_selectedAssignmentBook != null) {
            return _buildAssignmentDetailView(isMobile: true);
          }
          return Column(
            children: [
              _buildLeftPanelHeader(),
              Expanded(child: _buildBookList()),
            ],
          );
        }

        // Desktop View
        return Row(
          children: [
            // Left Panel
            Container(
              width: 380,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                children: [
                  _buildLeftPanelHeader(),
                  Expanded(child: _buildBookList()),
                ],
              ),
            ),
            // Right Panel
            Expanded(
              child: _selectedAssignmentBook != null
                  ? _buildAssignmentDetailView(isMobile: false)
                  : _buildAssignmentPlaceholder(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAssignmentPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_ind_rounded,
            size: 80,
            color: Colors.indigo.shade50,
          ),
          const SizedBox(height: 16),
          Text(
            'Atamaları yönetmek için soldan bir kitap seçin',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentDetailView({required bool isMobile}) {
    final book = _selectedAssignmentBook!;
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          _buildAssignmentDetailHeader(book, isMobile),
          Expanded(child: _buildAssignmentListForBook(book.id)),
        ],
      ),
    );
  }

  Widget _buildAssignmentDetailHeader(Book book, bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selectedAssignmentBook = null),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  book.type == BookType.questionBank
                      ? (book.branch ?? 'Branşsız')
                      : 'Okuma Kitabı',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _showAssignDialog(preSelectedBook: book),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Atama'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentListForBook(String bookId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('book_assignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('bookId', isEqualTo: bookId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(child: Text('Hata: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());

        final assignments = snapshot.data!.docs
            .map(
              (doc) => BookAssignment.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ),
            )
            .toList();

        if (assignments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_off_rounded,
                  size: 64,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Bu kitaba henüz kimse atanmamış.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        assignments.sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: assignments.length,
          itemBuilder: (context, index) {
            final assignment = assignments[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getTargetColor(
                    assignment.targetType,
                  ).withOpacity(0.1),
                  child: Icon(
                    _getTargetIcon(assignment.targetType),
                    color: _getTargetColor(assignment.targetType),
                    size: 20,
                  ),
                ),
                title: Text(
                  assignment.targetName ?? 'İsimsiz Hedef',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${_getTargetLabel(assignment.targetType)} • ${DateFormat('dd.MM.yyyy HH:mm').format(assignment.assignedAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _deleteAssignment(assignment.id),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getTargetColor(BookAssignmentTarget type) {
    switch (type) {
      case BookAssignmentTarget.schoolType:
        return Colors.purple;
      case BookAssignmentTarget.classLevel:
        return Colors.orange;
      case BookAssignmentTarget.className:
        return Colors.blue;
      case BookAssignmentTarget.student:
        return Colors.green;
    }
  }

  IconData _getTargetIcon(BookAssignmentTarget type) {
    switch (type) {
      case BookAssignmentTarget.schoolType:
        return Icons.school;
      case BookAssignmentTarget.classLevel:
        return Icons.layers;
      case BookAssignmentTarget.className:
        return Icons.meeting_room;
      case BookAssignmentTarget.student:
        return Icons.person;
    }
  }

  String _getTargetLabel(BookAssignmentTarget type) {
    switch (type) {
      case BookAssignmentTarget.schoolType:
        return 'Tüm Okul';
      case BookAssignmentTarget.classLevel:
        return 'Sınıf Seviyesi';
      case BookAssignmentTarget.className:
        return 'Şube';
      case BookAssignmentTarget.student:
        return 'Öğrenci';
    }
  }

  void _showAssignDialog({Book? preSelectedBook}) {
    showDialog(
      context: context,
      builder: (context) => BookAssignmentDialog(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        books: _allBooks,
        initialSelectedBookId: preSelectedBook?.id,
      ),
    );
  }

  Future<void> _deleteAssignment(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Atamayı Sil'),
        content: Text('Bu atamayı kaldırmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Kaldır', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('book_assignments')
          .doc(id)
          .delete();
    }
  }
}

class BookDetailView extends StatefulWidget {
  final Book? book;
  final String institutionId;
  final String schoolTypeId;
  final List<String> branches;
  final List<String> schoolTypeLevels;
  final VoidCallback onSaved;
  final VoidCallback onCancelled;
  final bool isMobile;

  const BookDetailView({
    Key? key,
    this.book,
    required this.institutionId,
    required this.schoolTypeId,
    required this.branches,
    required this.schoolTypeLevels,
    required this.onSaved,
    required this.onCancelled,
    required this.isMobile,
  }) : super(key: key);

  @override
  _BookDetailViewState createState() => _BookDetailViewState();
}

class _BookDetailViewState extends State<BookDetailView> {
  final _formKey = GlobalKey<FormState>();
  late BookType _type;
  late TextEditingController _nameController;
  late TextEditingController _authorController;
  late TextEditingController _pageCountController;

  String? _selectedBranch;
  List<BookTopic> _topics = [];

  @override
  void initState() {
    super.initState();
    _type = widget.book?.type ?? BookType.reading;
    _nameController = TextEditingController(text: widget.book?.name ?? '');
    _authorController = TextEditingController(text: widget.book?.author ?? '');
    _pageCountController = TextEditingController(
      text: widget.book?.pageCount?.toString() ?? '',
    );
    _selectedBranch = widget.book?.branch;
    _topics = widget.book?.topics != null ? List.from(widget.book!.topics) : [];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.isMobile
            ? BorderRadius.zero
            : BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      margin: widget.isMobile ? EdgeInsets.zero : const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: widget.isMobile
            ? BorderRadius.zero
            : BorderRadius.circular(16),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            automaticallyImplyLeading: false,
            leading: widget.isMobile
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.indigo),
                    onPressed: widget.onCancelled,
                  )
                : null,
            title: Text(
              widget.book == null ? 'Yeni Kitap Tanımı' : 'Kitap Detayları',
              style: const TextStyle(
                color: Colors.indigo,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            actions: [
              if (widget.book != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _confirmDelete,
                ),
              const SizedBox(width: 16),
            ],
          ),
          body: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    cacheExtent: 1000, // Optimize rendering
                    children: [
                      // Type Toggle
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTypeToggleItem(
                                'Soru Bankası',
                                BookType.questionBank,
                              ),
                            ),
                            Expanded(
                              child: _buildTypeToggleItem(
                                'Okuma Kitabı',
                                BookType.reading,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                      _buildSectionHeader('Temel Bilgiler'),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Kitap Adı',
                          prefixIcon: Icon(
                            Icons.title,
                            color: Colors.indigo.shade400,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.indigo.shade300,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          labelStyle: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                        validator: (v) => v!.isEmpty ? 'Boş bırakılamaz' : null,
                      ),
                      if (_type == BookType.reading) ...[
                        SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _authorController,
                                decoration: InputDecoration(
                                  labelText: 'Yazar',
                                  prefixIcon: Icon(
                                    Icons.person,
                                    color: Colors.indigo.shade400,
                                    size: 20,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.indigo.shade300,
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  labelStyle: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _pageCountController,
                                decoration: InputDecoration(
                                  labelText: 'Sayfa Sayısı',
                                  prefixIcon: Icon(
                                    Icons.format_list_numbered,
                                    color: Colors.indigo.shade400,
                                    size: 20,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.indigo.shade300,
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  labelStyle: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedBranch,
                          decoration: InputDecoration(
                            labelText: 'Branş',
                            prefixIcon: Icon(Icons.category),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          items: [
                            if (_selectedBranch != null &&
                                !widget.branches.contains(_selectedBranch))
                              DropdownMenuItem(
                                value: _selectedBranch,
                                child: Text(_selectedBranch!),
                              ),
                            ...widget.branches.map(
                              (b) => DropdownMenuItem(value: b, child: Text(b)),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _selectedBranch = val),
                          validator: (v) =>
                              v == null ? 'Branş seçilmeli' : null,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            _buildSectionHeader(
                              'İçerik Detayları (Konu & Test)',
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: _addTopic,
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 18,
                              ),
                              label: const Text('Konu Ekle'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo.shade50,
                                foregroundColor: Colors.indigo,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(height: 12),
                        ..._topics.asMap().entries.map((e) {
                          return _TopicEditorItem(
                            key: ValueKey(e.value.id),
                            topic: e.value,
                            onDelete: () =>
                                setState(() => _topics.removeAt(e.key)),
                            onChanged: () {
                              // Parent update if needed, but the model is mutable
                            },
                          );
                        }).toList(),
                        if (_topics.isEmpty)
                          Container(
                            padding: EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.shade200,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Daha sağlıklı takip için konuları ve test sayılarını ekleyebilirsiniz.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: Offset(0, -4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (!widget.isMobile)
                        TextButton(
                          onPressed: widget.onCancelled,
                          child: Text(
                            'Vazgeç',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      Spacer(),
                      ElevatedButton(
                        onPressed: _save,
                        child: Text('Değişiklikleri Kaydet'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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

  Widget _buildTypeToggleItem(String label, BookType type) {
    final isSelected = _type == type;
    return GestureDetector(
      onTap: () => setState(() => _type = type),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.indigo : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.indigo.shade900,
      ),
    );
  }

  void _addTopic() {
    setState(() {
      _topics.add(
        BookTopic(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: '',
          subtopics: [],
        ),
      );
    });
  }

  // Refactored to external widgets

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final bookData = Book(
      id: widget.book?.id ?? '',
      institutionId: widget.institutionId,
      name: _nameController.text,
      type: _type,
      author: _type == BookType.reading ? _authorController.text : null,
      pageCount: _type == BookType.reading
          ? int.tryParse(_pageCountController.text)
          : null,
      branch: _type == BookType.questionBank ? _selectedBranch : null,
      classLevels: [], // Removed as per request
      topics: _type == BookType.questionBank ? _topics : [],
      createdAt: widget.book?.createdAt ?? DateTime.now(),
    );

    try {
      if (widget.book == null) {
        await FirebaseFirestore.instance
            .collection('books')
            .add(bookData.toMap());
      } else {
        await FirebaseFirestore.instance
            .collection('books')
            .doc(widget.book!.id)
            .update(bookData.toMap());
      }
      widget.onSaved();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Kitabı Sil'),
        content: Text(
          'Bu kitabı kütüphaneden kalıcı olarak silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Kalıcı Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('books')
          .doc(widget.book!.id)
          .delete();
      widget.onSaved();
    }
  }
}

class BookAssignmentDialog extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final List<Book> books;
  final String? initialSelectedBookId;

  const BookAssignmentDialog({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.books,
    this.initialSelectedBookId,
  }) : super(key: key);

  @override
  _BookAssignmentDialogState createState() => _BookAssignmentDialogState();
}

class _BookAssignmentDialogState extends State<BookAssignmentDialog> {
  // Same implementation as before, but with better UI
  BookAssignmentTarget _targetType = BookAssignmentTarget.student;
  List<String> _selectedBookIds = [];
  List<String> _selectedTargetIds = [];
  List<Map<String, dynamic>> _targetOptions = [];
  String _targetSearchQuery = "";
  bool _isLoadingTargets = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedBookId != null) {
      _selectedBookIds = [widget.initialSelectedBookId!];
    }
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    setState(() => _isLoadingTargets = true);
    _targetOptions = [];
    _selectedTargetIds = [];
    _targetSearchQuery = "";

    try {
      if (_targetType == BookAssignmentTarget.schoolType) {
        final doc = await FirebaseFirestore.instance
            .collection('school_types')
            .doc(widget.schoolTypeId)
            .get();
        if (doc.exists)
          _targetOptions = [
            {'id': doc.id, 'name': doc.data()?['name'] ?? 'Okul Türü'},
          ];
      } else if (_targetType == BookAssignmentTarget.classLevel) {
        final doc = await FirebaseFirestore.instance
            .collection('school_types')
            .doc(widget.schoolTypeId)
            .get();
        if (doc.exists && doc.data()?['activeGrades'] != null) {
          final levels = List<String>.from(
            doc.data()!['activeGrades'].map((e) => e.toString()),
          );
          _targetOptions = levels
              .map((l) => {'id': l, 'name': '$l. Sınıf Seviyesi'})
              .toList();
        }
      } else if (_targetType == BookAssignmentTarget.className) {
        final snap = await FirebaseFirestore.instance
            .collection('classes')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .get();
        _targetOptions = snap.docs
            .map((d) => {'id': d.id, 'name': d.data()['className'].toString()})
            .toList();
      } else if (_targetType == BookAssignmentTarget.student) {
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true)
            .limit(100)
            .get();
        _targetOptions = snap.docs
            .map((d) => {'id': d.id, 'name': d.data()['fullName'].toString()})
            .toList();
      }
    } catch (e) {}
    if (mounted) setState(() => _isLoadingTargets = false);
  }

  @override
  Widget build(BuildContext context) {
    final filteredTargets = _targetOptions.where((t) {
      if (_targetSearchQuery.isEmpty) return true;
      return t['name'].toString().toLowerCase().contains(
        _targetSearchQuery.toLowerCase(),
      );
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 700,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.assignment_ind_rounded,
                  color: Colors.indigo,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Kitap Atama Paneli',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _buildLabel('1. Atama Türünü Seçin'),
                  Row(
                    children: BookAssignmentTarget.values.map((t) {
                      final isSelected = _targetType == t;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _targetType = t);
                            _loadTargets();
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.indigo
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.indigo
                                    : Colors.grey.shade200,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colors.indigo.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  _getTargetIcon(t),
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey.shade600,
                                  size: 20,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _getTargetTypeText(t),
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey.shade600,
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  _buildLabel('2. Hedef Seçin (Birden Fazla Seçilebilir)'),
                  if (_targetType != BookAssignmentTarget.schoolType)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: TextFormField(
                        onChanged: (v) =>
                            setState(() => _targetSearchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Ara...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: _isLoadingTargets
                        ? const Center(child: CircularProgressIndicator())
                        : filteredTargets.isEmpty
                        ? const Center(
                            child: Text(
                              'Sonuç bulunamadı.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : Scrollbar(
                            child: ListView.builder(
                              itemCount: filteredTargets.length,
                              itemBuilder: (context, index) {
                                final item = filteredTargets[index];
                                final isSelected = _selectedTargetIds.contains(
                                  item['id'],
                                );
                                return CheckboxListTile(
                                  value: isSelected,
                                  title: Text(
                                    item['name'].toString(),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  dense: true,
                                  activeColor: Colors.indigo,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedTargetIds.add(
                                          item['id'].toString(),
                                        );
                                      } else {
                                        _selectedTargetIds.remove(
                                          item['id'].toString(),
                                        );
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  _buildLabel('3. Atanacak Kitapları Seçin'),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Scrollbar(
                      child: ListView(
                        children: widget.books.map((book) {
                          final isSelected = _selectedBookIds.contains(book.id);
                          return CheckboxListTile(
                            value: isSelected,
                            activeColor: Colors.indigo,
                            title: Text(
                              book.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              book.type == BookType.questionBank
                                  ? (book.branch ?? '')
                                  : 'Okuma Kitabı',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedBookIds.add(book.id);
                                } else {
                                  _selectedBookIds.remove(book.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'İptal',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed:
                      (_selectedBookIds.isEmpty || _selectedTargetIds.isEmpty)
                      ? null
                      : _saveAssignments,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    '${_selectedBookIds.length} Kitabı ${_selectedTargetIds.length} Hedefe Ata',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: Colors.indigo.shade900,
      ),
    ),
  );

  IconData _getTargetIcon(BookAssignmentTarget type) {
    switch (type) {
      case BookAssignmentTarget.schoolType:
        return Icons.school_rounded;
      case BookAssignmentTarget.classLevel:
        return Icons.layers_rounded;
      case BookAssignmentTarget.className:
        return Icons.meeting_room_rounded;
      case BookAssignmentTarget.student:
        return Icons.person_search_rounded;
    }
  }

  String _getTargetTypeText(BookAssignmentTarget type) {
    switch (type) {
      case BookAssignmentTarget.schoolType:
        return 'Tüm Okul';
      case BookAssignmentTarget.classLevel:
        return 'Sınıf Seviyesi';
      case BookAssignmentTarget.className:
        return 'Şubeler';
      case BookAssignmentTarget.student:
        return 'Öğrenciler';
    }
  }

  Future<void> _saveAssignments() async {
    final batch = FirebaseFirestore.instance.batch();
    for (final bookId in _selectedBookIds) {
      for (final targetId in _selectedTargetIds) {
        final targetName = _targetOptions.firstWhere(
          (e) => e['id'] == targetId,
        )['name'];
        final docRef = FirebaseFirestore.instance
            .collection('book_assignments')
            .doc();
        batch.set(
          docRef,
          BookAssignment(
            id: '',
            institutionId: widget.institutionId,
            bookId: bookId,
            targetType: _targetType,
            targetId: targetId,
            targetName: targetName,
            assignedAt: DateTime.now(),
          ).toMap(),
        );
      }
    }
    await batch.commit();
    if (mounted) {
      Navigator.pop(context);
    }
  }
}

class _TopicEditorItem extends StatefulWidget {
  final BookTopic topic;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _TopicEditorItem({
    Key? key,
    required this.topic,
    required this.onDelete,
    required this.onChanged,
  }) : super(key: key);

  @override
  _TopicEditorItemState createState() => _TopicEditorItemState();
}

class _TopicEditorItemState extends State<_TopicEditorItem> {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bookmark_outline,
                  size: 20,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: widget.topic.name,
                    decoration: const InputDecoration(
                      labelText: 'Konu Adı',
                      border: InputBorder.none,
                      isDense: true,
                      labelStyle: TextStyle(
                        color: Colors.indigo,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    onChanged: (v) {
                      widget.topic.name = v;
                      widget.onChanged();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Colors.red,
                    size: 22,
                  ),
                  onPressed: widget.onDelete,
                  tooltip: 'Konuyu Sil',
                ),
              ],
            ),
          ),
          if (widget.topic.subtopics.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue:
                              widget.topic.testCount?.toString() ?? '',
                          decoration: InputDecoration(
                            labelText: 'Toplam Test Sayısı',
                            prefixIcon: const Icon(
                              Icons.format_list_numbered,
                              size: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            setState(() {
                              widget.topic.testCount = int.tryParse(v);
                              if (widget.topic.testCount != null) {
                                widget.topic.questionsPerTestList ??= [];
                                while (widget
                                        .topic
                                        .questionsPerTestList!
                                        .length <
                                    widget.topic.testCount!) {
                                  widget.topic.questionsPerTestList!.add(20);
                                }
                              }
                            });
                            widget.onChanged();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue:
                              widget.topic.questionsPerTest?.toString() ?? '',
                          decoration: InputDecoration(
                            labelText: 'Varsayılan Soru/Test',
                            prefixIcon: const Icon(
                              Icons.question_mark,
                              size: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            widget.topic.questionsPerTest = int.tryParse(v);
                            widget.onChanged();
                          },
                        ),
                      ),
                    ],
                  ),
                  if (widget.topic.testCount != null &&
                      widget.topic.testCount! > 0) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Her Test İçin Soru Sayısı:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(widget.topic.testCount!, (tIdx) {
                        widget.topic.questionsPerTestList ??= List.filled(
                          widget.topic.testCount!,
                          20,
                        );
                        if (widget.topic.questionsPerTestList!.length <= tIdx) {
                          widget.topic.questionsPerTestList!.add(20);
                        }
                        return Container(
                          width: 75,
                          child: TextFormField(
                            initialValue: widget
                                .topic
                                .questionsPerTestList![tIdx]
                                .toString(),
                            decoration: InputDecoration(
                              labelText: '${tIdx + 1}. Test',
                              labelStyle: const TextStyle(fontSize: 10),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              widget.topic.questionsPerTestList![tIdx] =
                                  int.tryParse(v) ?? 0;
                              widget.onChanged();
                            },
                          ),
                        );
                      }),
                    ),
                  ],
                ],
              ),
            ),
          if (widget.topic.subtopics.isNotEmpty)
            ...widget.topic.subtopics.asMap().entries.map((subE) {
              return _SubtopicEditorItem(
                subtopic: subE.value,
                onDelete: () => setState(() {
                  widget.topic.subtopics.removeAt(subE.key);
                  widget.onChanged();
                }),
                onChanged: widget.onChanged,
              );
            }).toList(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  widget.topic.subtopics.add(
                    BookSubtopic(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: '',
                      testCount: 1,
                      questionsPerTestList: [20],
                    ),
                  );
                });
                widget.onChanged();
              },
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text(
                'Alt Konu Ekle',
                style: TextStyle(fontSize: 13),
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.indigo),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtopicEditorItem extends StatefulWidget {
  final BookSubtopic subtopic;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _SubtopicEditorItem({
    Key? key,
    required this.subtopic,
    required this.onDelete,
    required this.onChanged,
  }) : super(key: key);

  @override
  _SubtopicEditorItemState createState() => _SubtopicEditorItemState();
}

class _SubtopicEditorItemState extends State<_SubtopicEditorItem> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.subdirectory_arrow_right,
                  size: 18,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: widget.subtopic.name,
                    decoration: const InputDecoration(
                      hintText: 'Alt Konu Adı',
                      border: InputBorder.none,
                      isDense: true,
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    onChanged: (v) {
                      widget.subtopic.name = v;
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: widget.subtopic.testCount.toString(),
                    decoration: InputDecoration(
                      labelText: 'Test S.',
                      labelStyle: const TextStyle(fontSize: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      setState(() {
                        widget.subtopic.testCount = int.tryParse(v) ?? 1;
                        widget.subtopic.questionsPerTestList ??= [];
                        while (widget.subtopic.questionsPerTestList!.length <
                            widget.subtopic.testCount) {
                          widget.subtopic.questionsPerTestList!.add(20);
                        }
                      });
                      widget.onChanged();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    size: 18,
                    color: Colors.grey,
                  ),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ),
          if (widget.subtopic.testCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(42, 0, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(widget.subtopic.testCount, (tIdx) {
                  widget.subtopic.questionsPerTestList ??= List.filled(
                    widget.subtopic.testCount,
                    20,
                  );
                  if (widget.subtopic.questionsPerTestList!.length <= tIdx) {
                    widget.subtopic.questionsPerTestList!.add(20);
                  }
                  return Container(
                    width: 70,
                    child: TextFormField(
                      initialValue: widget.subtopic.questionsPerTestList![tIdx]
                          .toString(),
                      decoration: InputDecoration(
                        labelText: '${tIdx + 1}. Test',
                        labelStyle: const TextStyle(fontSize: 9),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                      ),
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        widget.subtopic.questionsPerTestList![tIdx] =
                            int.tryParse(v) ?? 0;
                        widget.onChanged();
                      },
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
