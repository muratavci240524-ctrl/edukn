import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

class LibraryScreen extends StatefulWidget {
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;

  const LibraryScreen({
    Key? key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
  }) : super(key: key);

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  String? _institutionId;
  String? _schoolDocId;
  bool _isLoading = true;
  late TabController _tabController;

  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _lendings = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final email = user.email!;
      _institutionId = email.split('@')[1].split('.')[0].toUpperCase();

      final snap = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: _institutionId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        _schoolDocId = snap.docs.first.id;
      }

      await _loadBooks();
      await _loadLendings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBooks() async {
    if (_schoolDocId == null) return;
    Query query = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('libraryBooks');

    if (widget.fixedSchoolTypeId != null) {
      query = query.where('schoolTypeId', isEqualTo: widget.fixedSchoolTypeId);
    }

    final snap = await query.orderBy('title').get();

    setState(() {
      _books = snap.docs.map<Map<String, dynamic>>((d) {
        final data = d.data() as Map<String, dynamic>?;
        return {'id': d.id, if (data != null) ...data};
      }).toList();
    });
  }

  Future<void> _loadLendings() async {
    if (_schoolDocId == null) return;
    Query query = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('bookLendings');

    if (widget.fixedSchoolTypeId != null) {
      query = query.where('schoolTypeId', isEqualTo: widget.fixedSchoolTypeId);
    }

    final snap = await query.orderBy('lendDate', descending: true).get();
    setState(() {
      _lendings = snap.docs.map<Map<String, dynamic>>((d) {
        final data = d.data() as Map<String, dynamic>?;
        return {'id': d.id, if (data != null) ...data};
      }).toList();
    });
  }

  // ─── Book CRUD ───

  Future<void> _addBook() async {
    final titleCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    final isbnCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final quantityCtrl = TextEditingController(text: '1');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.menu_book, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Yeni Kitap Ekle'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Kitap Adı *',
                  prefixIcon: Icon(Icons.book),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              SizedBox(height: 12),
              TextField(
                controller: authorCtrl,
                decoration: InputDecoration(
                  labelText: 'Yazar *',
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              SizedBox(height: 12),
              TextField(
                controller: isbnCtrl,
                decoration: InputDecoration(
                  labelText: 'ISBN (isteğe bağlı)',
                  prefixIcon: Icon(Icons.qr_code),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: categoryCtrl,
                decoration: InputDecoration(
                  labelText: 'Kategori',
                  prefixIcon: Icon(Icons.category),
                  hintText: 'Örn: Roman, Bilim, Tarih',
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: quantityCtrl,
                decoration: InputDecoration(
                  labelText: 'Adet',
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: Text('Ekle'),
          ),
        ],
      ),
    );

    if (result != true) return;
    if (titleCtrl.text.trim().isEmpty || authorCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kitap adı ve yazar zorunludur!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('libraryBooks')
        .add({
          'title': titleCtrl.text.trim(),
          'author': authorCtrl.text.trim(),
          'isbn': isbnCtrl.text.trim(),
          'category': categoryCtrl.text.trim(),
          'quantity': int.tryParse(quantityCtrl.text.trim()) ?? 1,
          'available': int.tryParse(quantityCtrl.text.trim()) ?? 1,
          'createdAt': FieldValue.serverTimestamp(),
          if (widget.fixedSchoolTypeId != null)
            'schoolTypeId': widget.fixedSchoolTypeId,
        });

    await _loadBooks();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Kitap eklendi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteBook(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kitap Sil'),
        content: Text('Bu kitabı silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('libraryBooks')
        .doc(id)
        .delete();

    await _loadBooks();
  }

  Future<void> _uploadBooksExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;

      final content = utf8.decode(file.bytes!);
      final lines = content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      if (lines.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya boş veya hatalı format!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Kitaplar yükleniyor...'),
            ],
          ),
        ),
      );

      int count = 0;
      // Skip header: KitapAdi;Yazar;ISBN;Kategori;Adet
      for (int i = 1; i < lines.length; i++) {
        final parts = lines[i].split(';');
        if (parts.length < 2) continue;

        final title = parts[0].trim();
        final author = parts[1].trim();
        final isbn = parts.length > 2 ? parts[2].trim() : '';
        final category = parts.length > 3 ? parts[3].trim() : '';
        final quantity = parts.length > 4
            ? (int.tryParse(parts[4].trim()) ?? 1)
            : 1;

        if (title.isEmpty) continue;

        await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolDocId)
            .collection('libraryBooks')
            .add({
              'title': title,
              'author': author,
              'isbn': isbn,
              'category': category,
              'quantity': quantity,
              'available': quantity,
              'createdAt': FieldValue.serverTimestamp(),
            });
        count++;
      }

      Navigator.pop(context);
      await _loadBooks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ $count kitap yüklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ─── Lending ───

  Future<void> _lendBook(Map<String, dynamic> book) async {
    final studentNameCtrl = TextEditingController();
    DateTime? dueDate;
    final dueDateCtrl = TextEditingController();
    int lendDays = 14;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.book_online, color: Colors.deepPurple),
              SizedBox(width: 8),
              Expanded(
                child: Text('Kitap Ver', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Book info
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.menu_book, color: Colors.deepPurple),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          book['title'],
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: studentNameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Öğrenci Adı Soyadı *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                SizedBox(height: 12),
                TextField(
                  controller: dueDateCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Teslim Tarihi *',
                    prefixIcon: Icon(Icons.calendar_today),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(Duration(days: lendDays)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(Duration(days: 365)),
                      locale: Locale('tr', 'TR'),
                    );
                    if (date != null) {
                      dueDate = date;
                      dueDateCtrl.text =
                          '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
                      setDialogState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
              ),
              child: Text('Kitap Ver'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    if (studentNameCtrl.text.trim().isEmpty || dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Öğrenci adı ve teslim tarihi zorunludur!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Create lending record
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('bookLendings')
        .add({
          'bookId': book['id'],
          'bookTitle': book['title'],
          'studentName': studentNameCtrl.text.trim(),
          'lendDate': Timestamp.fromDate(DateTime.now()),
          'dueDate': Timestamp.fromDate(dueDate!),
          'returned': false,
          'returnDate': null,
          'createdAt': FieldValue.serverTimestamp(),
          if (widget.fixedSchoolTypeId != null)
            'schoolTypeId': widget.fixedSchoolTypeId,
        });

    // Decrease available count
    final available = (book['available'] ?? 1) - 1;
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('libraryBooks')
        .doc(book['id'])
        .update({'available': available < 0 ? 0 : available});

    await _loadBooks();
    await _loadLendings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Kitap verildi'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _returnBook(Map<String, dynamic> lending) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kitap Teslim Al'),
        content: Text('"${lending['bookTitle']}" kitabı teslim alınsın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Teslim Al'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Mark as returned
    await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('bookLendings')
        .doc(lending['id'])
        .update({
          'returned': true,
          'returnDate': Timestamp.fromDate(DateTime.now()),
        });

    // Increase available count
    final bookDoc = await FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolDocId)
        .collection('libraryBooks')
        .doc(lending['bookId'])
        .get();

    if (bookDoc.exists) {
      final available = (bookDoc.data()?['available'] ?? 0) + 1;
      final quantity = bookDoc.data()?['quantity'] ?? 1;
      await bookDoc.reference.update({
        'available': available > quantity ? quantity : available,
      });
    }

    await _loadBooks();
    await _loadLendings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Kitap teslim alındı'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Kütüphane İşlemleri')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Kütüphane İşlemleri'),
        elevation: 1,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'upload') _uploadBooksExcel();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'upload',
                child: Row(
                  children: [
                    Icon(Icons.upload_file, color: Colors.deepPurple, size: 20),
                    SizedBox(width: 12),
                    Text('Toplu Kitap Yükle (CSV)'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: [
            Tab(icon: Icon(Icons.menu_book), text: 'Kitaplar'),
            Tab(icon: Icon(Icons.swap_horiz), text: 'Ödünç'),
            Tab(icon: Icon(Icons.bar_chart), text: 'İstatistik'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _addBook,
              icon: Icon(Icons.add),
              label: Text('Kitap Ekle'),
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [_buildBooksList(), _buildLendingsList(), _buildStatistics()],
      ),
    );
  }

  Widget _buildBooksList() {
    final filteredBooks = _searchQuery.isEmpty
        ? _books
        : _books.where((b) {
            final search = _searchQuery.toLowerCase();
            return (b['title'] ?? '').toLowerCase().contains(search) ||
                (b['author'] ?? '').toLowerCase().contains(search);
          }).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Kitap Ara...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        // Count
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.library_books, size: 18, color: Colors.deepPurple),
              SizedBox(width: 8),
              Text(
                '${filteredBooks.length} kitap',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 4),
        Expanded(
          child: filteredBooks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.menu_book,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Henüz kitap eklenmemiş',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: 900),
                    child: ListView.builder(
                      padding: EdgeInsets.all(12),
                      itemCount: filteredBooks.length,
                      itemBuilder: (context, index) {
                        final book = filteredBooks[index];
                        final available = book['available'] ?? 0;
                        final quantity = book['quantity'] ?? 1;
                        final isAvailable = available > 0;

                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isAvailable
                                  ? Colors.deepPurple.shade50
                                  : Colors.red.shade50,
                              child: Icon(
                                Icons.menu_book,
                                color: isAvailable
                                    ? Colors.deepPurple
                                    : Colors.red,
                              ),
                            ),
                            title: Text(
                              book['title'] ?? '',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book['author'] ?? '',
                                  style: TextStyle(fontSize: 13),
                                ),
                                Row(
                                  children: [
                                    if (book['category'] != null &&
                                        (book['category'] as String).isNotEmpty)
                                      Chip(
                                        label: Text(
                                          book['category'],
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Mevcut: $available/$quantity',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isAvailable
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAvailable)
                                  IconButton(
                                    icon: Icon(
                                      Icons.book_online,
                                      color: Colors.deepPurple,
                                    ),
                                    tooltip: 'Kitap Ver',
                                    onPressed: () => _lendBook(book),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red.shade300,
                                  ),
                                  onPressed: () => _deleteBook(book['id']),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLendingsList() {
    final activeLendings = _lendings
        .where((l) => l['returned'] != true)
        .toList();
    final returnedLendings = _lendings
        .where((l) => l['returned'] == true)
        .toList();
    final now = DateTime.now();

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active lendings
              Text(
                'Teslim Edilmemiş (${activeLendings.length})',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              SizedBox(height: 8),
              if (activeLendings.isEmpty)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Teslim edilmemiş kitap yok')),
                  ),
                ),
              ...activeLendings.map((lending) {
                final dueDate = (lending['dueDate'] as Timestamp?)?.toDate();
                final isOverdue = dueDate != null && dueDate.isBefore(now);
                final dueDateStr = dueDate != null
                    ? DateFormat('dd.MM.yyyy').format(dueDate)
                    : '-';

                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  color: isOverdue ? Colors.red.shade50 : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: isOverdue
                        ? BorderSide(color: Colors.red, width: 1)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isOverdue
                          ? Colors.red.shade100
                          : Colors.deepPurple.shade50,
                      child: Icon(
                        isOverdue ? Icons.warning : Icons.book,
                        color: isOverdue ? Colors.red : Colors.deepPurple,
                      ),
                    ),
                    title: Text(
                      lending['bookTitle'] ?? '',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Öğrenci: ${lending['studentName']}',
                          style: TextStyle(fontSize: 13),
                        ),
                        Text(
                          'Teslim: $dueDateStr${isOverdue ? ' (GECİKMİŞ!)' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isOverdue ? Colors.red : Colors.grey,
                            fontWeight: isOverdue
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: ElevatedButton.icon(
                      icon: Icon(Icons.check, size: 18),
                      label: Text('Teslim Al', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () => _returnBook(lending),
                    ),
                  ),
                );
              }),

              SizedBox(height: 24),
              // Returned
              if (returnedLendings.isNotEmpty) ...[
                Text(
                  'Teslim Edilenler (${returnedLendings.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                SizedBox(height: 8),
                ...returnedLendings.take(20).map((lending) {
                  final returnDate = (lending['returnDate'] as Timestamp?)
                      ?.toDate();
                  final returnDateStr = returnDate != null
                      ? DateFormat('dd.MM.yyyy').format(returnDate)
                      : '-';
                  return Card(
                    margin: EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.shade50,
                        child: Icon(Icons.check_circle, color: Colors.green),
                      ),
                      title: Text(lending['bookTitle'] ?? ''),
                      subtitle: Text(
                        '${lending['studentName']} • Teslim: $returnDateStr',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    final totalBooks = _books.length;
    final totalQuantity = _books.fold<int>(
      0,
      (sum, b) => sum + ((b['quantity'] as int?) ?? 0),
    );
    final totalAvailable = _books.fold<int>(
      0,
      (sum, b) => sum + ((b['available'] as int?) ?? 0),
    );
    final activeLendings = _lendings.where((l) => l['returned'] != true).length;
    final overdue = _lendings.where((l) {
      if (l['returned'] == true) return false;
      final dueDate = (l['dueDate'] as Timestamp?)?.toDate();
      return dueDate != null && dueDate.isBefore(DateTime.now());
    }).length;

    // Category distribution
    final categoryMap = <String, int>{};
    for (final book in _books) {
      final cat = (book['category'] ?? 'Kategorisiz') as String;
      categoryMap[cat.isEmpty ? 'Kategorisiz' : cat] =
          (categoryMap[cat.isEmpty ? 'Kategorisiz' : cat] ?? 0) + 1;
    }
    final sortedCategories = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Most borrowed
    final borrowMap = <String, int>{};
    for (final l in _lendings) {
      final title = l['bookTitle'] as String? ?? '';
      borrowMap[title] = (borrowMap[title] ?? 0) + 1;
    }
    final topBorrowed = borrowMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatCard(
                    'Toplam Kitap Türü',
                    '$totalBooks',
                    Icons.menu_book,
                    Colors.deepPurple,
                  ),
                  _buildStatCard(
                    'Toplam Adet',
                    '$totalQuantity',
                    Icons.numbers,
                    Colors.blue,
                  ),
                  _buildStatCard(
                    'Mevcut',
                    '$totalAvailable',
                    Icons.check_circle,
                    Colors.green,
                  ),
                  _buildStatCard(
                    'Ödünçte',
                    '$activeLendings',
                    Icons.swap_horiz,
                    Colors.orange,
                  ),
                  if (overdue > 0)
                    _buildStatCard(
                      'Gecikmiş',
                      '$overdue',
                      Icons.warning,
                      Colors.red,
                    ),
                ],
              ),

              SizedBox(height: 24),
              Text(
                'Kategori Dağılımı',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              ...sortedCategories.map(
                (e) => ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.category,
                    color: Colors.deepPurple.shade300,
                  ),
                  title: Text(e.key),
                  trailing: Chip(
                    label: Text('${e.value}'),
                    backgroundColor: Colors.deepPurple.shade50,
                  ),
                ),
              ),

              SizedBox(height: 24),
              Text(
                'En Çok Ödünç Alınan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              ...topBorrowed
                  .take(10)
                  .map(
                    (e) => ListTile(
                      dense: true,
                      leading: Icon(Icons.trending_up, color: Colors.orange),
                      title: Text(e.key),
                      trailing: Chip(
                        label: Text('${e.value}'),
                        backgroundColor: Colors.orange.shade50,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return SizedBox(
      width: 160,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 28, color: color),
              SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
