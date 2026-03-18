import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:edukn/screens/school/guidance/guidance_statistics_screen.dart';

class GuidanceInterviewScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool isTeacher;
  final String? teacherId;

  const GuidanceInterviewScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isTeacher = false,
    this.teacherId,
  }) : super(key: key);

  @override
  State<GuidanceInterviewScreen> createState() =>
      _GuidanceInterviewScreenState();
}

class _GuidanceInterviewScreenState extends State<GuidanceInterviewScreen> {
  // State
  String _selectedTab = 'ogrenci'; // 'personel', 'ogrenci', 'veli'
  List<Map<String, dynamic>> _dataList = []; // Gelen veriler
  List<Map<String, dynamic>> _filteredList = []; // Filtrelenmiş veriler
  Set<String> _selectedIds = {}; // Seçili kişi ID'leri
  Map<String, String> _selectedNames = {}; // Seçili kişi İsimleri (ID -> Name)

  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Dialog / Selection State for Mobile
  bool _showFormMobile = false;

  // Form Fields
  final _formKey = GlobalKey<FormState>();
  String _interviewType = 'Yüz Yüze'; // Varsayılan
  String? _interviewTitle = 'Akademik Görüşme';
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _otherTitleController = TextEditingController();
  bool _isPrivate = true; // Default locked
  bool _isSaving = false;

  // File Upload State
  PlatformFile? _attachedFile;

  // History Detail State
  Map<String, dynamic>? _selectedHistoryItem;

  // Date Filter State
  DateTime? _startDate;
  DateTime? _endDate;

  // Interviewer Filter State
  String? _selectedInterviewerFilter;
  List<String> _availableInterviewers = [];

  // Constants
  final List<String> _interviewTypes = [
    'Yüz Yüze',
    'Telefon',
    'Online',
    'Diğer',
  ];

  final Map<String, IconData> _interviewTypeIcons = {
    'Yüz Yüze': Icons.people_alt,
    'Telefon': Icons.phone,
    'Online': Icons.video_call,
    'Diğer': Icons.more_horiz,
  };

  final List<String> _interviewTitles = [
    'Akademik Görüşme',
    'Davranışsal Görüşme',
    'Motivasyon Görüşmesi',
    'Bilgilendirme Görüşmesi',
    'Diğer',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    _otherTitleController.dispose();
    super.dispose();
  }

  // Veri Çekme
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _selectedNames.clear();
      // Tab değişince listeye dön (mobil için)
      _showFormMobile = false;
    });

    try {
      List<Map<String, dynamic>> rawData = [];

      if (_selectedTab == 'personel') {
        // Personel verilerini çek
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('type', isEqualTo: 'staff') // Personel filtresi
            .get();

        rawData = query.docs.map((doc) {
          final data = doc.data();
          final fullName =
              data['fullName'] ??
              data['name'] ??
              'İsimsiz'; // staff_form'da fullName var

          // Alt başlık belirleme - Öğretmense branş, değilse ünvan
          String subtitle = data['title'] ?? 'Personel';
          if (subtitle.toLowerCase() == 'ogretmen' ||
              subtitle.toLowerCase() == 'öğretmen') {
            if (data['branch'] != null &&
                data['branch'].toString().isNotEmpty) {
              subtitle = data['branch'];
            } else {
              subtitle = 'Öğretmen';
            }
          }

          return {
            'id': doc.id,
            'name': fullName,
            'sub': subtitle,
            'tag': 'P',
            'color': Colors.orange,
            'type': 'personel',
          };
        }).toList();
      } else if (_selectedTab == 'ogrenci') {
        // Öğrenci verilerini çek
        final query = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true)
            .get();

        rawData = query.docs.map((doc) {
          final data = doc.data();
          final name =
              data['fullName'] ??
              '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim();
          return {
            'id': doc.id,
            'name': name.isEmpty ? 'İsimsiz Öğrenci' : name,
            'sub':
                '${data['className'] ?? 'Sınıfsız'} - ${data['studentNo'] ?? ''}',
            'tag': 'Ö',
            'color': Colors.blue,
            'type': 'ogrenci',
          };
        }).toList();
      } else if (_selectedTab == 'veli') {
        // Veli verilerini çek
        final query = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true)
            .get();

        rawData = [];
        for (var doc in query.docs) {
          final data = doc.data();
          final studentName =
              data['fullName'] ??
              '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim();
          final parents = data['parents'] as List<dynamic>? ?? [];

          for (var p in parents) {
            final String parentId = 'P_${doc.id}_${p['tcNo'] ?? p['name']}';
            final parentName = p['name'] ?? 'İsimsiz Veli';
            final relation = p['relation'] ?? 'Veli';

            // KULLANICl İSTEĞİ: Öğrenci adı ana başlık, veli adı alt başlık
            rawData.add({
              'id': parentId,
              'realId': parentId,
              'name': studentName, // Listede görünen ana isim (Öğrenci)
              'sub':
                  '$parentName (Veli) - $relation', // Alt bilgi (Kimle görüşülüyor)
              'tag': 'V',
              'color': Colors.purple,
              'type': 'veli',
              'studentId': doc.id,
              'phone': p['phone'],
              'actualParticipantName':
                  parentName, // Kaydederken kullanılacak asıl kişi ismi
            });
          }
        }
      } else if (_selectedTab == 'gecmis') {
        // Geçmiş Görüşmeler
        Query queryRef = FirebaseFirestore.instance
            .collection('guidance_interviews')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId);

        if (widget.isTeacher && widget.teacherId != null) {
          queryRef = queryRef.where(Filter.or(
            Filter('interviewerId', isEqualTo: widget.teacherId),
            Filter('participants', arrayContains: widget.teacherId),
          ));
        }

        final query = await queryRef.orderBy('date', descending: true).get();

        rawData = query.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final timestamp = data['date'] as Timestamp?;
          final dateStr = timestamp != null
              ? DateFormat('dd.MM.yyyy HH:mm').format(timestamp.toDate())
              : 'Tarihsiz';

          String displayName = 'İsimsiz';
          String subTitle = '$dateStr - ${data['title'] ?? ''}';

          // Logic to show Student Name in List for 'veli' category
          if (data['category'] == 'veli') {
            // Try to find student name from participantDetails
            final details = data['participantDetails'] as List<dynamic>?;
            if (details != null && details.isNotEmpty) {
              // Assuming single participant for now or join them
              final studentNames = details
                  .map((d) => d['name'] ?? '')
                  .join(', ');
              if (studentNames.isNotEmpty) {
                displayName = studentNames;
                // Add parent name to subtitle to differentiate
                final parentNames =
                    (data['participantNames'] as List<dynamic>?)?.join(', ') ??
                    '';
                subTitle =
                    '$dateStr - ${data['title'] ?? ''} (Veli: $parentNames)';
              } else {
                displayName =
                    (data['participantNames'] as List<dynamic>?)?.join(', ') ??
                    'İsimsiz Veli';
              }
            } else {
              displayName =
                  (data['participantNames'] as List<dynamic>?)?.join(', ') ??
                  'İsimsiz Veli';
            }
          } else {
            displayName =
                (data['participantNames'] as List<dynamic>?)?.join(', ') ??
                'İsimsiz';
          }

          return {
            'id': doc.id,
            'docData': data,
            'name': displayName,
            'sub': subTitle,
            'tag': 'G',
            'color': Colors.grey,
            'type': 'history',
          };
        }).toList();
      }

      if (mounted) {
        setState(() {
          _dataList = rawData;
          _isLoading = false;
          _dataList = rawData;
          _isLoading = false;

          // Extract unique interviewers for filter
          if (_selectedTab == 'gecmis') {
            final names = rawData
                .map((e) {
                  final d = e['docData'] as Map<String, dynamic>?;
                  return d?['interviewerName'] as String?;
                })
                .where((n) => n != null && n.isNotEmpty)
                .map((n) => n!)
                .toSet()
                .toList();
            names.sort();
            _availableInterviewers = names;
          } else {
            _availableInterviewers = [];
            _selectedInterviewerFilter = null;
          }

          _filterData();
        });
      }
    } catch (e) {
      print('Veri çekme hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterData() {
    if (_searchQuery.isEmpty) {
      setState(() {
        _filteredList = List.from(_dataList);
      });
    } else {
      setState(() {
        _filteredList = _dataList.where((item) {
          final name = item['name'].toString().toLowerCase();
          final sub = item['sub'].toString().toLowerCase();
          final query = _searchQuery.toLowerCase();
          final matchesSearch = name.contains(query) || sub.contains(query);
          final matchesDate = _matchesDateFilter(item);
          final matchesInterviewer = _matchesInterviewerFilter(item);

          return matchesSearch && matchesDate && matchesInterviewer;
        }).toList();
      });
    }
  }

  bool _matchesDateFilter(Map<String, dynamic> item) {
    if (_startDate == null && _endDate == null) return true;
    if (item['type'] != 'history') return true; // Only filter history items

    final data = item['docData'] as Map<String, dynamic>?;
    if (data == null) return false;

    final timestamp = data['date'] as Timestamp?;
    if (timestamp == null) return false;

    final date = timestamp.toDate();

    if (_startDate != null && date.isBefore(_startDate!)) return false;
    if (_endDate != null && date.isAfter(_endDate!.add(Duration(days: 1))))
      return false;

    return true;
  }

  bool _matchesInterviewerFilter(Map<String, dynamic> item) {
    if (_selectedInterviewerFilter == null) return true;
    if (item['type'] != 'history') return true;

    final data = item['docData'] as Map<String, dynamic>?;
    if (data == null) return false;

    final interviewer = data['interviewerName'] as String?;
    return interviewer == _selectedInterviewerFilter;
  }

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _filterData();
  }

  void _onTabChanged(String tab) {
    if (_selectedTab != tab) {
      setState(() {
        _selectedTab = tab;
        _selectedInterviewerFilter = null; // Reset filter on tab change
      });
      _loadData();
    }
  }

  void _toggleSelection(String id, String name) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectedNames.remove(id);
      } else {
        _selectedIds.add(id);
        _selectedNames[id] = name;
      }
    });
  }

  Future<String> _fetchCurrentUserName(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          return data['fullName'] ??
              data['name'] ??
              user.displayName ??
              user.email!.split('@')[0];
        }
      }
    } catch (e) {
      debugPrint('Error fetching user name: $e');
    }
    return user.displayName ?? user.email?.split('@')[0] ?? 'Bilinmiyor';
  }

  Future<void> _initiateSave() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lütfen en az bir kişi seçiniz.')));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final finalTitle = _interviewTitle == 'Diğer'
        ? _otherTitleController.text
        : _interviewTitle;

    if ((finalTitle == null || finalTitle.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lütfen görüşme başlığını giriniz.')),
      );
      return;
    }

    if (_selectedIds.length > 1) {
      // Toplu seçim var, sor
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Toplu Görüşme Kaydı'),
          content: Text(
            'Seçili ${_selectedIds.length} kişi için bu görüşmeyi nasıl kaydetmek istersiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _saveInterview(finalTitle, isBatchSeparate: true);
              },
              child: Text('Her Biri İçin Ayrı Ayrı'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _saveInterview(finalTitle, isBatchSeparate: false);
              },
              child: Text('Tek Bir Grup Görüşmesi Olarak'),
            ),
          ],
        ),
      );
    } else {
      // Tek kişi
      _saveInterview(finalTitle, isBatchSeparate: false);
    }
  }

  Future<void> _saveInterview(
    String title, {
    required bool isBatchSeparate,
  }) async {
    setState(() => _isSaving = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final batch = FirebaseFirestore.instance.batch();
      final collection = FirebaseFirestore.instance.collection(
        'guidance_interviews',
      );
      final now = DateTime.now();

      // Upload File if exists
      String? fileUrl;
      if (_attachedFile != null) {
        fileUrl = await _uploadFile();
      }

      // Get Interviewer Name
      String interviewerName = await _fetchCurrentUserName(currentUser!);

      if (isBatchSeparate) {
        // Her katılımcı için ayrı döküman
        for (var id in _selectedIds) {
          final docRef = collection.doc();
          final person = _dataList.firstWhere(
            (e) => e['id'] == id,
            orElse: () => {},
          );

          final interviewData = {
            'institutionId': widget.institutionId,
            'schoolTypeId': widget.schoolTypeId,
            'interviewerId': currentUser?.uid,
            'interviewerEmail': currentUser?.email,

            'participants': [id], // Tek kişi
            'participantNames': [
              person['actualParticipantName'] ?? person['name'],
            ], // Veli ise asıl veli ismini, değilse görünen ismi al
            'participantDetails': [
              {
                'id': person['id'],
                'name': person['name'],
                'sub': person['sub'],
                'type': person['type'],
                'studentId': person['studentId'],
                'phone': person['phone'],
                'actualParticipantName': person['actualParticipantName'],
              },
            ],
            'date': Timestamp.fromDate(now),
            'category': _selectedTab,
            'type': _interviewType,
            'title': title,
            'notes': _notesController.text,
            'isPrivate': _isPrivate,
            'createdAt': FieldValue.serverTimestamp(),
            'isBatchCreated': true,
            'fileUrl': fileUrl,
            'fileName': _attachedFile?.name,
            'interviewerName': interviewerName,
          };
          batch.set(docRef, interviewData);
        }
      } else {
        // Tek döküman
        final docRef = collection.doc();
        final interviewData = {
          'institutionId': widget.institutionId,
          'schoolTypeId': widget.schoolTypeId,
          'interviewerId': currentUser?.uid,
          'interviewerEmail': currentUser?.email,
          'participants': _selectedIds.toList(),
          'participantNames': _selectedIds.map((id) {
            final person = _dataList.firstWhere(
              (e) => e['id'] == id,
              orElse: () => {},
            );
            return person['actualParticipantName'] ?? person['name'];
          }).toList(),
          'participantDetails': _selectedIds.map((id) {
            final person = _dataList.firstWhere(
              (e) => e['id'] == id,
              orElse: () => {},
            );
            // Sanitize: Remove UI objects like Color/Icon
            return {
              'id': person['id'],
              'name': person['name'],
              'sub': person['sub'],
              'type': person['type'],
              'studentId': person['studentId'],
              'phone': person['phone'],
              'actualParticipantName': person['actualParticipantName'],
            };
          }).toList(),
          'date': Timestamp.fromDate(now),
          'category': _selectedTab,
          'type': _interviewType,
          'title': title,
          'notes': _notesController.text,
          'isPrivate': _isPrivate,
          'createdAt': FieldValue.serverTimestamp(),
          'isBatchCreated': false,
          'fileUrl': fileUrl,
          'fileName': _attachedFile?.name,
          'interviewerName': interviewerName,
        };
        batch.set(docRef, interviewData);
      }

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Görüşme(ler) başarıyla kaydedildi!'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        _notesController.clear();
        _otherTitleController.clear();
        _selectedIds.clear();
        _selectedNames.clear();
        _interviewTitle = _interviewTitles.first;
        _interviewTitle = _interviewTitles.first;
        _interviewType = 'Yüz Yüze';
        _isPrivate = true;
        _isSaving = false;
        _attachedFile = null;

        // Eğer mobildeysek listeye dön
        _showFormMobile = false;
      });
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _uploadFile() async {
    if (_attachedFile == null) return null;
    try {
      // File path or bytes depending on platform
      final ref = FirebaseStorage.instance
          .ref()
          .child('guidance_docs')
          .child(
            '${DateTime.now().millisecondsSinceEpoch}_${_attachedFile!.name}',
          );

      if (kIsWeb) {
        if (_attachedFile!.bytes != null) {
          await ref.putData(_attachedFile!.bytes!);
        } else {
          return null;
        }
      } else {
        if (_attachedFile!.path != null) {
          await ref.putFile(File(_attachedFile!.path!));
        } else {
          return null;
        }
      }

      return await ref.getDownloadURL();
    } catch (e) {
      print("Upload Error: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Responsive Layout
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;

        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            title: Text(
              _showFormMobile ? 'Görüşme Detayları' : 'Rehberlik Görüşmeleri',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.indigo),
              onPressed: () {
                if (_showFormMobile) {
                  setState(() => _showFormMobile = false);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            actions: [
              IconButton(
                onPressed: _showStatisticsDialog,
                icon: Icon(Icons.bar_chart, color: Colors.indigo),
                tooltip: 'İstatistikler',
              ),
            ],
          ),
          body: isMobile ? _buildMobileBody() : _buildDesktopBody(),

          floatingActionButton:
              (isMobile && !_showFormMobile && _selectedIds.isNotEmpty)
              ? FloatingActionButton.extended(
                  onPressed: () {
                    setState(() {
                      _showFormMobile = true;
                    });
                  },
                  icon: Icon(Icons.arrow_forward),
                  label: Text('İlerle (${_selectedIds.length})'),
                  backgroundColor: Colors.indigo,
                )
              : null,
        );
      },
    );
  }

  // DESKTOP SPLIT VIEW
  Widget _buildDesktopBody() {
    return Row(
      children: [
        // SOL PANEL (LİSTE) - Sabit genişlik
        Container(
          width: 380,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: _buildListContent(isMobile: false),
        ),

        // SAĞ PANEL (FORM veya DETAY)
        Expanded(
          child: _selectedTab == 'gecmis'
              ? _buildHistoryDetailPanel()
              : SingleChildScrollView(
                  padding: EdgeInsets.all(32),
                  child: _buildFormContent(),
                ),
        ),
      ],
    );
  }

  // Right Panel for History Details
  Widget _buildHistoryDetailPanel() {
    if (_selectedHistoryItem == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey.shade300),
            SizedBox(height: 16),
            Text(
              "Detaylarını görmek için listeden bir görüşme seçiniz.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(32),
      child: _buildHistoryDetailContent(_selectedHistoryItem!),
    );
  }

  // MOBILE VIEW (ONE AT A TIME)
  Widget _buildMobileBody() {
    if (_showFormMobile) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: _buildFormContent(),
      );
    } else {
      return _buildListContent(isMobile: true);
    }
  }

  // LIST CONTENT (Used in both Desktop Left Panel and Mobile Main Screen)
  // LIST CONTENT (Used in both Desktop Left Panel and Mobile Main Screen)
  Widget _buildListContent({required bool isMobile}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            padding: EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(child: _buildTabButton('Öğrenci', 'ogrenci')),
                Expanded(child: _buildTabButton('Veli', 'veli')),
                Expanded(child: _buildTabButton('Personel', 'personel')),
                Expanded(child: _buildTabButton('Geçmiş', 'gecmis')),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Kişi Ara...',
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
              isDense: true,
            ),
          ),
        ),

        // DATE FILTER (Visible only in History tab)
        if (_selectedTab == 'gecmis')
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final pickedStart = await showDatePicker(
                              context: context,
                              initialDate: _startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                              locale: const Locale('tr', 'TR'),
                            );
                            if (pickedStart != null) {
                              setState(() {
                                _startDate = pickedStart;
                                // Auto-reset end date if it's before new start date
                                if (_endDate != null &&
                                    _endDate!.isBefore(_startDate!)) {
                                  _endDate = null;
                                }
                              });
                              // Auto-open end date picker
                              if (context.mounted) {
                                final pickedEnd = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _endDate ?? _startDate ?? DateTime.now(),
                                  firstDate: _startDate ?? DateTime(2020),
                                  lastDate: DateTime(2030),
                                  locale: const Locale('tr', 'TR'),
                                );
                                if (pickedEnd != null) {
                                  setState(() {
                                    _endDate = pickedEnd;
                                    _filterData();
                                  });
                                }
                              } else {
                                _filterData();
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Text(
                              _startDate == null
                                  ? 'Başlangıç'
                                  : DateFormat(
                                      'dd.MM.yyyy',
                                    ).format(_startDate!),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_right_alt,
                        color: Colors.grey.shade400,
                        size: 16,
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _endDate ?? _startDate ?? DateTime.now(),
                              firstDate: _startDate ?? DateTime(2020),
                              lastDate: DateTime(2030),
                              locale: const Locale('tr', 'TR'),
                            );
                            if (picked != null) {
                              setState(() {
                                _endDate = picked;
                                _filterData();
                              });
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Text(
                              _endDate == null
                                  ? 'Bitiş'
                                  : DateFormat('dd.MM.yyyy').format(_endDate!),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Icon(
                          Icons.calendar_today,
                          color: Colors.grey.shade400,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                if (_availableInterviewers.isNotEmpty)
                  Container(
                    width: double.infinity,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedInterviewerFilter,
                                hint: Text(
                                  "Görüşmeyi Yapan Seçiniz",
                                  style: TextStyle(fontSize: 13),
                                ),
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem<String>(
                                    value: null,
                                    child: Text(
                                      "Tümü",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ..._availableInterviewers.map(
                                    (name) => DropdownMenuItem(
                                      value: name,
                                      child: Text(name),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedInterviewerFilter = val;
                                    _filterData();
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              color: Colors.grey.shade700,
                            ),
                            onSelected: (value) {
                              if (value == 'excel') {
                                _exportToExcel();
                              } else if (value == 'pdf') {
                                _printInterviews(); // PDF İndir (Printing usually handles download/print)
                              } else if (value == 'print') {
                                _printInterviews(); // Yazdır
                              }
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'excel',
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.table_chart,
                                        color: Colors.green,
                                      ),
                                      title: Text('Excel İndir'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'pdf',
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.picture_as_pdf,
                                        color: Colors.red,
                                      ),
                                      title: Text('PDF İndir'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'print',
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.print,
                                        color: Colors.blue,
                                      ),
                                      title: Text('Yazdır'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_startDate != null ||
                    _endDate != null ||
                    _selectedInterviewerFilter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            icon: Icon(
                              Icons.clear,
                              color: Colors.red,
                              size: 16,
                            ),
                            label: Text(
                              'Filtreleri Temizle',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                            onPressed: () {
                              setState(() {
                                _startDate = null;
                                _endDate = null;
                                _selectedInterviewerFilter = null;
                                _filterData();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

        SizedBox(height: 12),

        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : _filteredList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Kayıt bulunamadı',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _filteredList.length,
                  itemBuilder: (context, index) {
                    final item = _filteredList[index];

                    if (_selectedTab == 'gecmis') {
                      return _buildHistoryListItem(item, isMobile);
                    }

                    final isSelected = _selectedIds.contains(item['id']);
                    return _buildPersonCard(item, isSelected);
                  },
                ),
        ),
      ],
    );
  }

  // FORM CONTENT (Used in both Desktop Right Panel and Mobile Detail Screen)
  Widget _buildFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedIds.isEmpty)
          Center(
            child: Container(
              padding: EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.indigo.shade50),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 64,
                    color: Colors.indigo.shade200,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Görüşme Kaydına Başla',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Listeden kişi seçerek ilerleyiniz.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Seçili Kişiler Kısmı
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.group, color: Colors.indigo),
                          SizedBox(width: 8),
                          Text(
                            'Görüşülen Kişiler',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_selectedIds.length} Kişi',
                              style: TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedNames.entries.map((entry) {
                          return Chip(
                            avatar: CircleAvatar(
                              backgroundColor: Colors.indigo.shade100,
                              child: Text(
                                entry.value.isNotEmpty
                                    ? entry.value[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                            ),
                            label: Text(entry.value),
                            backgroundColor: Colors.white,
                            side: BorderSide(color: Colors.grey.shade300),
                            onDeleted: () {
                              // Formdayken seçimi kaldırırsak ve liste boşalırsa geri dönülmeli mi?
                              // Tasarım tercihi: Boşalırsa boş ekran gösterir.
                              _toggleSelection(entry.key, entry.value);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),

                // Form Kartı
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Görüşme Detayları',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      SizedBox(height: 24),

                      // Görüşme Şekli
                      Text(
                        'Görüşme Şekli',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Mobile Layout (Use Row with Expanded)
                          // Assuming mobile threshold around 600 or check constraints
                          // Use Expanded for full width distribution as requested
                          return Row(
                            children: _interviewTypes.map((type) {
                              return Expanded(child: _buildTypeCard(type));
                            }).toList(),
                          );
                        },
                      ),
                      SizedBox(height: 24),

                      // Başlık
                      Text(
                        'Görüşme Konusu',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _interviewTitle,
                            isExpanded: true,
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: Colors.grey.shade600,
                            ),
                            items: _interviewTitles.map((title) {
                              return DropdownMenuItem(
                                value: title,
                                child: Text(title),
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => _interviewTitle = value),
                          ),
                        ),
                      ),
                      if (_interviewTitle == 'Diğer') ...[
                        SizedBox(height: 12),
                        TextFormField(
                          controller: _otherTitleController,
                          decoration: InputDecoration(
                            hintText: 'Konu başlığı giriniz',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 24),

                      // Notlar
                      Text(
                        'Görüşme Notları',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 8,
                        decoration: InputDecoration(
                          hintText:
                              'Görüşme detaylarını buraya yazabilirsiniz...',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        validator: (val) => val == null || val.isEmpty
                            ? 'Lütfen not giriniz'
                            : null,
                      ),
                      SizedBox(height: 24),

                      // Gizlilik
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isPrivate
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isPrivate
                                ? Colors.red.shade200
                                : Colors.green.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isPrivate ? Icons.lock : Icons.lock_open,
                              color: _isPrivate ? Colors.red : Colors.green,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isPrivate
                                        ? 'Gizli Görüşme'
                                        : 'Açık Görüşme',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _isPrivate
                                          ? Colors.red.shade900
                                          : Colors.green.shade900,
                                    ),
                                  ),
                                  Text(
                                    _isPrivate
                                        ? 'Sadece yetkili kişiler görebilir.'
                                        : 'İlgili kişiler erişebilir.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _isPrivate
                                          ? Colors.red.shade700
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isPrivate,
                              activeColor: Colors.red,
                              onChanged: (val) =>
                                  setState(() => _isPrivate = val),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 32),

                      // Kaydet Butonu
                      SizedBox(height: 24),

                      // DOSYA YÜKLEME ALANI
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Dosya Ekle (İsteğe Bağlı)",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            SizedBox(height: 12),
                            if (_attachedFile != null)
                              Row(
                                children: [
                                  Icon(
                                    Icons.insert_drive_file,
                                    color: Colors.indigo,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _attachedFile!.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close, color: Colors.red),
                                    onPressed: _clearFile,
                                  ),
                                ],
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: _pickFile,
                                icon: Icon(Icons.upload_file),
                                label: Text("Dosya Seç"),
                              ),
                          ],
                        ),
                      ),

                      SizedBox(height: 32),

                      // Kaydet Butonu (Updated)
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _initiateSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isSaving
                              ? CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  'Görüşmeyi Kaydet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // HISTORY LIST ITEM (Left Panel)
  Widget _buildHistoryListItem(Map<String, dynamic> item, bool isMobile) {
    if (item['docData'] == null || (item['docData'] as Map).isEmpty) {
      // Corrupt data item
      return ListTile(
        leading: Icon(Icons.error, color: Colors.red),
        title: Text("Hatalı Kayıt"),
        trailing: IconButton(
          icon: Icon(Icons.delete, color: Colors.red, size: 20),
          onPressed: () => _deleteInterview(item['id']),
        ),
      );
    }

    final isSelected =
        _selectedHistoryItem != null &&
        _selectedHistoryItem!['id'] == item['id'];

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.indigo.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? Colors.indigo.shade200 : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: () {
          if (isMobile) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => Scaffold(
                  appBar: AppBar(
                    title: Text('Görüşme Detayı'),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 1,
                  ),
                  body: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: _buildHistoryDetailContent(item),
                  ),
                ),
              ),
            );
          } else {
            setState(() {
              _selectedHistoryItem = item;
            });
          }
        },
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade100,
          child: Text(
            item['dateDay'] ?? '?',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
        ),
        title: Text(
          item['name'],
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          item['sub'],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.grey.shade400,
          size: 18,
        ),
      ),
    );
  }

  // HISTORY DETAIL CONTENT (Right Panel)
  Widget _buildHistoryDetailContent(Map<String, dynamic> item) {
    final data = item['docData'] as Map<String, dynamic>;
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = data['interviewerId'] == currentUser?.uid;
    final isPrivate = data['isPrivate'] == true;
    final canViewContent = isOwner || !isPrivate;

    final date = (data['date'] as Timestamp?)?.toDate();
    final dateStr = date != null
        ? DateFormat('dd MMMM yyyy HH:mm', 'tr_TR').format(date)
        : 'Tarih Yok';

    // Interviewer Name Logic
    // We try to use 'interviewerName' if saved, otherwise fall back to email or 'Bilinmiyor'.
    final interviewerInfo =
        data['interviewerName'] ?? data['interviewerEmail'] ?? 'Bilinmiyor';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.history_edu, color: Colors.indigo, size: 32),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['title'] ?? 'Başlıksız Görüşme',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (isOwner)
              IconButton(
                onPressed: () => _deleteInterview(item['id']),
                icon: Icon(Icons.delete, color: Colors.red),
                tooltip: 'Görüşmeyi Sil',
              ),
          ],
        ),
        Divider(height: 40),

        // Info Grid
        Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _buildInfoBadge(
              Icons.person,
              data['category'] == 'veli'
                  ? "Görüşülen (Veli)"
                  : "Görüşen (Öğrenci/Veli)",
              data['category'] == 'veli'
                  ? ((data['participantNames'] as List<dynamic>?)?.join(', ') ??
                        item['name'])
                  : item['name'],
            ),
            _buildInfoBadge(
              Icons.badge,
              "Görüşmeyi Yapan",
              interviewerInfo,
            ), // Showing Name/Email
            _buildInfoBadge(Icons.category, "Tür", data['type'] ?? '-'),
            _buildInfoBadge(
              isPrivate ? Icons.lock : Icons.lock_open,
              "Gizlilik",
              isPrivate ? "Gizli" : "Açık",
              color: isPrivate ? Colors.red : Colors.green,
            ),
          ],
        ),

        SizedBox(height: 32),

        // Content
        Text(
          "Görüşme Notları",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: canViewContent ? Colors.white : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10),
            ],
          ),
          child: canViewContent
              ? Text(
                  data['notes'] ?? 'Not girilmemiş.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Colors.grey.shade800,
                  ),
                )
              : Row(
                  children: [
                    Icon(Icons.lock, color: Colors.grey),
                    SizedBox(width: 12),
                    Text(
                      "Bu görüşme notları gizlidir.",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
        ),

        // File Attachment if exists
        if (canViewContent && data['fileUrl'] != null) ...[
          SizedBox(height: 24),
          Text(
            "Ekli Dosya",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(height: 12),
          InkWell(
            onTap: () {
              // TODO: Implement file open/download logic or use url_launcher
              // For now just show snackbar
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Dosya açma henüz aktif değil: ${data['fileUrl']}',
                  ),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_file, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    data['fileName'] ?? 'Dosya',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoBadge(
    IconData icon,
    String label,
    String value, {
    Color color = Colors.indigo,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _attachedFile = result.files.first;
      });
    }
  }

  void _clearFile() {
    setState(() {
      _attachedFile = null;
    });
  }

  Widget _buildTabButton(String label, String tabKey) {
    final isSelected = _selectedTab == tabKey;
    return GestureDetector(
      onTap: () => _onTabChanged(tabKey),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.indigo : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildPersonCard(Map<String, dynamic> item, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleSelection(item['id'], item['name']),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 6),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.indigo.shade200 : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: isSelected
                  ? Colors.indigo
                  : item['color'].withOpacity(0.1),
              child: Text(
                item['tag'],
                style: TextStyle(
                  color: isSelected ? Colors.white : item['color'],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    item['sub'],
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: Colors.indigo, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard(String type) {
    final isSelected = _interviewType == type;
    return GestureDetector(
      onTap: () => setState(() => _interviewType = type),
      child: Container(
        // width: 100, // Removed fixed width
        margin: EdgeInsets.symmetric(horizontal: 4), // Adjusted margin
        padding: EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.indigo : Colors.grey.shade300,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.indigo.withOpacity(0.3),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(
              _interviewTypeIcons[type],
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            SizedBox(height: 8),
            Text(
              type,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteInterview(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Görüşmeyi Sil'),
        content: Text('Bu görüşme kaydını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('guidance_interviews')
          .doc(docId)
          .delete();
      _loadData(); // Refresh list
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Görüşme silindi.')));
    }
  }

  // STATISTICS
  void _showStatisticsDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GuidanceStatisticsScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
        ),
      ),
    );
  }

  Future<void> _printInterviews() async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                "Rehberlik Görüşme Raporu",
                style: pw.TextStyle(font: boldFont, fontSize: 18),
              ),
            ),
            pw.Table.fromTextArray(
              context: context,
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(font: boldFont, fontSize: 10),
              cellStyle: pw.TextStyle(font: font, fontSize: 9),
              headers: <String>[
                'Görüşülen Kişi',
                'Görüşen Kişi',
                'Tarih',
                'Tür / Konu',
                'Görüşme Notları',
              ],
              data: _filteredList.map((item) {
                final data = item['docData'] as Map<String, dynamic>? ?? {};
                final timestamp = data['date'] as Timestamp?;
                final dateStr = timestamp != null
                    ? DateFormat('dd.MM.yyyy HH:mm').format(timestamp.toDate())
                    : '-';

                final interviewer =
                    data['interviewerName'] ?? data['interviewerEmail'] ?? '-';
                final notes = data['notes'] ?? '';
                final title = data['title'] ?? '';
                final category = data['category'] ?? ''; // ogrenci, veli etc.

                String typeTopic = '';
                if (category.isNotEmpty)
                  typeTopic += '${category.toUpperCase()} - ';
                typeTopic += title;

                // Participant Names logic same as display
                String pNames = item['name'] ?? '-';
                if (data['category'] == 'veli') {
                  // Try to find if parent name is stored directly or join details
                  final details = data['participantDetails'] as List<dynamic>?;
                  if (details != null) {
                    final parentNames = details
                        .where((d) => d['type'] == 'veli')
                        .map((d) => d['name'])
                        .join(', ');
                    if (parentNames.isNotEmpty) pNames = parentNames;
                  }
                }

                return [pNames, interviewer, dateStr, typeTopic, notes];
              }).toList(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
    );
  }

  Future<void> _exportToExcel() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Sheet1'];

      // Add Headers
      sheetObject.appendRow([
        TextCellValue('Görüşülen Kişi'),
        TextCellValue('Görüşen Kişi (Öğretmen)'),
        TextCellValue('Tarih'),
        TextCellValue('Konu / Tür'),
        TextCellValue('Notlar'),
      ]);

      // Add Data
      for (var item in _filteredList) {
        final data = item['docData'] as Map<String, dynamic>? ?? {};
        final timestamp = data['date'] as Timestamp?;
        final dateStr = timestamp != null
            ? DateFormat('dd.MM.yyyy HH:mm').format(timestamp.toDate())
            : '-';

        final interviewer =
            data['interviewerName'] ?? data['interviewerEmail'] ?? '-';
        final notes = data['notes'] ?? '';
        final title = data['title'] ?? '';
        final category = data['category'] ?? ''; // ogrenci, veli etc.

        String typeTopic = '';
        if (category.isNotEmpty) typeTopic += '${category.toUpperCase()} - ';
        typeTopic += title;

        // Participant Names logic
        String pNames = item['name'] ?? '-';
        if (data['category'] == 'veli') {
          final details = data['participantDetails'] as List<dynamic>?;
          if (details != null) {
            final parentNames = details
                .where((d) => d['type'] == 'veli')
                .map((d) => d['name'])
                .join(', ');
            if (parentNames.isNotEmpty) pNames = parentNames;
          }
        }

        sheetObject.appendRow([
          TextCellValue(pNames),
          TextCellValue(interviewer),
          TextCellValue(dateStr),
          TextCellValue(typeTopic),
          TextCellValue(notes),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        final now = DateTime.now();
        final fileName =
            'Rehberlik_Gorusmeleri_${DateFormat('yyyyMMdd_HHmm').format(now)}';

        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: Uint8List.fromList(fileBytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel raporu indirildi.')));
      }
    } catch (e) {
      debugPrint('Excel Export Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rapor oluşturulurken hata oluştu: $e')),
      );
    }
  }
} // End of _GuidanceInterviewScreenState
