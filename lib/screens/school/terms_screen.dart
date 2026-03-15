import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/term_service.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({Key? key}) : super(key: key);

  @override
  _TermsScreenState createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  String? _institutionId;
  List<Map<String, dynamic>> _terms = [];
  bool _isLoading = true;
  String? _selectedTermId; // Seçilen dönem (görüntüleme için)

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email!;
      _institutionId = email.split('@')[1].split('.')[0].toUpperCase();

      final snapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: _institutionId)
          .get();

      final termsList = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Kod içinde sıralama yap
      termsList.sort((a, b) {
        final aYear = a['startYear'] ?? 0;
        final bYear = b['startYear'] ?? 0;
        return bYear.compareTo(aYear); // descending
      });

      // Kaydedilmiş seçili dönemi yükle
      final prefs = await SharedPreferences.getInstance();
      final savedTermId = prefs.getString('selected_term_id');
      
      // Aktif dönemi bul
      final activeTerm = termsList.firstWhere(
        (t) => t['isActive'] == true,
        orElse: () => {},
      );
      final activeTermId = activeTerm.isNotEmpty ? activeTerm['id'] : null;
      
      // Eğer seçili dönem aktif dönemle aynıysa, seçili dönemi temizle
      String? effectiveSelectedTermId = savedTermId;
      if (savedTermId != null && savedTermId == activeTermId) {
        effectiveSelectedTermId = null;
        await prefs.remove('selected_term_id');
        await prefs.remove('selected_term_name');
      }

      setState(() {
        _terms = termsList;
        _selectedTermId = effectiveSelectedTermId;
        _isLoading = false;
      });
    } catch (e) {
      print('Dönemler yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setActiveTerm(String termId) async {
    try {
      // Tüm dönemleri pasif yap
      final batch = FirebaseFirestore.instance.batch();
      for (var term in _terms) {
        final ref = FirebaseFirestore.instance.collection('terms').doc(term['id']);
        batch.update(ref, {'isActive': false});
      }
      
      // Seçilen dönemi aktif yap
      final ref = FirebaseFirestore.instance.collection('terms').doc(termId);
      batch.update(ref, {'isActive': true});
      
      await batch.commit();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ Aktif dönem güncellendi'), backgroundColor: Colors.green),
      );
      
      _loadTerms();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showTermDialog({Map<String, dynamic>? term}) {
    final isEdit = term != null;
    int? startYear = term?['startYear'];
    int? endYear = term?['endYear'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Dönemi Düzenle' : 'Yeni Dönem Ekle'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                    labelText: 'Başlangıç Yılı *',
                    border: OutlineInputBorder(),
                  ),
                  value: startYear,
                  items: List.generate(10, (i) {
                    final year = DateTime.now().year - 2 + i;
                    return DropdownMenuItem(value: year, child: Text('$year'));
                  }),
                  onChanged: (value) {
                    setDialogState(() {
                      startYear = value;
                      if (value != null) endYear = value + 1;
                    });
                  },
                ),
                SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                    labelText: 'Bitiş Yılı *',
                    border: OutlineInputBorder(),
                  ),
                  value: endYear,
                  items: startYear == null
                      ? []
                      : List.generate(2, (i) {
                          final year = startYear! + 1 + i;
                          return DropdownMenuItem(value: year, child: Text('$year'));
                        }),
                  onChanged: (value) {
                    setDialogState(() => endYear = value);
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (startYear == null || endYear == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lütfen tüm alanları doldurun')),
                );
                return;
              }

              try {
                final termName = '$startYear-$endYear';
                final termData = {
                  'institutionId': _institutionId,
                  'name': termName,
                  'startYear': startYear,
                  'endYear': endYear,
                  'isActive': _terms.isEmpty, // İlk dönem otomatik aktif
                  'subTerms': [],
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                if (isEdit) {
                  await FirebaseFirestore.instance
                      .collection('terms')
                      .doc(term['id'])
                      .update(termData);
                } else {
                  await FirebaseFirestore.instance.collection('terms').add(termData);
                }

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isEdit ? '✓ Dönem güncellendi' : '✓ Dönem eklendi'),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadTerms();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: Text(isEdit ? 'Güncelle' : 'Ekle'),
          ),
        ],
      ),
    );
  }

  Future<void> _switchToTerm(Map<String, dynamic> term) async {
    // Aktif döneme tıklandıysa, seçili dönemi temizle
    if (term['isActive'] == true) {
      await _clearSelectedTerm();
      return;
    }
    
    // TermService üzerinden dönem değişikliğini yap (cache'i de günceller)
    await TermService().setSelectedTerm(term['id'], term['name']);
    
    setState(() {
      _selectedTermId = term['id'];
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ ${term['name']} dönemine geçildi. Veriler bu döneme göre gösterilecek.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  
  Future<void> _clearSelectedTerm() async {
    // TermService üzerinden seçili dönemi temizle (cache'i de temizler)
    await TermService().clearSelectedTerm();
    
    setState(() {
      _selectedTermId = null;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Aktif döneme geri dönüldü'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showCopyDataDialog(Map<String, dynamic> sourceTerm) {
    // Aktif dönemi bul
    final activeTerm = _terms.firstWhere(
      (t) => t['isActive'] == true,
      orElse: () => {},
    );
    
    if (activeTerm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aktif dönem bulunamadı'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Kopyalanacak veri türlerini seç
    final selectedTypes = <String>{};
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.copy, color: Colors.purple),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${sourceTerm['name']} → ${activeTerm['name']}',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kopyalanacak verileri seçin:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                _buildCopyOption(
                  'classes',
                  'Sınıflar/Şubeler',
                  Icons.class_,
                  selectedTypes,
                  setDialogState,
                ),
                _buildCopyOption(
                  'lessons',
                  'Dersler',
                  Icons.book,
                  selectedTypes,
                  setDialogState,
                ),
                _buildCopyOption(
                  'classrooms',
                  'Derslikler',
                  Icons.meeting_room,
                  selectedTypes,
                  setDialogState,
                ),
                _buildCopyOption(
                  'students',
                  'Öğrenciler',
                  Icons.people,
                  selectedTypes,
                  setDialogState,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: selectedTypes.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _copyDataToActiveTerm(
                        sourceTerm['id'],
                        activeTerm['id'],
                        selectedTypes.toList(),
                      );
                    },
              icon: Icon(Icons.copy),
              label: Text('Kopyala'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyOption(
    String key,
    String label,
    IconData icon,
    Set<String> selectedTypes,
    StateSetter setDialogState,
  ) {
    return CheckboxListTile(
      value: selectedTypes.contains(key),
      onChanged: (value) {
        setDialogState(() {
          if (value == true) {
            selectedTypes.add(key);
          } else {
            selectedTypes.remove(key);
          }
        });
      },
      title: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 8),
          Text(label),
        ],
      ),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  Future<void> _deleteAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('DİKKAT!', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aşağıdaki TÜM veriler silinecek:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('• Öğrenciler'),
            Text('• Sınıflar/Şubeler'),
            Text('• Dersler'),
            Text('• Derslikler'),
            Text('• Çalışma Takvimi'),
            Text('• Yıllık Planlar'),
            Text('• Ders Saatleri'),
            Text('• Personeller (admin hariç)'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                'Bu işlem GERİ ALINAMAZ!',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(Icons.delete_forever),
            label: Text('TÜMÜNÜ SİL'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // İkinci onay
    final confirmAgain = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Emin misiniz?'),
        content: Text('Tüm veriler kalıcı olarak silinecek. Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Hayır, vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Evet, sil'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmAgain != true) return;

    // Loading dialog göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.red),
            SizedBox(width: 16),
            Text('Veriler siliniyor...'),
          ],
        ),
      ),
    );

    try {
      final count = await TermService().deleteAllData();
      Navigator.pop(context); // Loading dialog kapat

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $count kayıt silindi'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Loading dialog kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _migrateExistingData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.sync, color: Colors.orange),
            SizedBox(width: 12),
            Text('Veri Aktarımı'),
          ],
        ),
        content: Text(
          'Dönem bilgisi olmayan tüm mevcut veriler (öğrenciler, sınıflar, dersler vb.) aktif döneme atanacak.\n\nBu işlem bir kez yapılmalıdır. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(Icons.sync),
            label: Text('Aktar'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Loading dialog göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Veriler aktarılıyor...'),
          ],
        ),
      ),
    );

    try {
      final count = await TermService().migrateDataToActiveTerm();
      Navigator.pop(context); // Loading dialog kapat

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $count kayıt aktif döneme atandı'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Loading dialog kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _copyDataToActiveTerm(
    String sourceTermId,
    String targetTermId,
    List<String> dataTypes,
  ) async {
    // Loading dialog göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Veriler kopyalanıyor...'),
          ],
        ),
      ),
    );

    try {
      int copiedCount = 0;

      for (final dataType in dataTypes) {
        // Kaynak dönemdeki verileri al
        final sourceData = await FirebaseFirestore.instance
            .collection(dataType)
            .where('institutionId', isEqualTo: _institutionId)
            .where('termId', isEqualTo: sourceTermId)
            .where('isActive', isEqualTo: true)
            .get();

        // Her bir veriyi hedef döneme kopyala
        for (final doc in sourceData.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          data.remove('id');
          data['termId'] = targetTermId;
          data['createdAt'] = FieldValue.serverTimestamp();
          data['copiedFrom'] = sourceTermId;

          await FirebaseFirestore.instance.collection(dataType).add(data);
          copiedCount++;
        }
      }

      Navigator.pop(context); // Loading dialog kapat

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $copiedCount kayıt aktif döneme kopyalandı'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Loading dialog kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Dönem Yönetimi'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_forever, color: Colors.red[200]),
            tooltip: 'Tüm verileri sil',
            onPressed: _deleteAllData,
          ),
          IconButton(
            icon: Icon(Icons.sync),
            tooltip: 'Mevcut verileri aktif döneme ata',
            onPressed: _migrateExistingData,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _terms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_today, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Henüz dönem eklenmemiş', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showTermDialog(),
                        icon: Icon(Icons.add),
                        label: Text('İlk Dönemi Ekle'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Seçili dönem bilgisi
                    if (_selectedTermId != null) ...[
                      Container(
                        margin: EdgeInsets.all(16),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange[700]),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Geçmiş dönem görüntüleniyor',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[800],
                                    ),
                                  ),
                                  Text(
                                    'Şu an ${_terms.firstWhere((t) => t['id'] == _selectedTermId, orElse: () => {'name': 'Bilinmeyen'})['name']} dönemini görüntülüyorsunuz',
                                    style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _clearSelectedTerm,
                              child: Text('Aktif Döneme Dön'),
                              style: TextButton.styleFrom(foregroundColor: Colors.orange[800]),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Dönem listesi
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: _selectedTermId != null ? 0 : 16),
                        itemCount: _terms.length,
                        itemBuilder: (context, index) {
                          final term = _terms[index];
                          final isActive = term['isActive'] ?? false;
                          final isSelected = _selectedTermId == term['id'];

                          return Card(
                            margin: EdgeInsets.only(bottom: 12),
                            elevation: isSelected ? 4 : (isActive ? 2 : 1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected ? Colors.orange : (isActive ? Colors.green : Colors.grey.shade300),
                                width: isSelected ? 2 : (isActive ? 2 : 1),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: isSelected ? Colors.orange[100] : (isActive ? Colors.green[100] : Colors.indigo[50]),
                                child: Icon(
                                  isSelected ? Icons.visibility : (isActive ? Icons.check_circle : Icons.calendar_today),
                                  color: isSelected ? Colors.orange : (isActive ? Colors.green : Colors.indigo),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    term['name'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isSelected ? Colors.orange[800] : (isActive ? Colors.green[800] : Colors.black87),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  if (isActive)
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'AKTİF',
                                        style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  if (isSelected)
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'GÖRÜNTÜLENİYOR',
                                        style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                isSelected 
                                    ? 'Bu dönemi görüntülüyorsunuz' 
                                    : (isActive ? 'Şu an bu dönemdesiniz' : 'Geçmiş dönem'),
                                style: TextStyle(
                                  color: isSelected ? Colors.orange[600] : (isActive ? Colors.green[600] : Colors.grey[600]),
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Geçmiş dönemleri incele butonu - doğrudan döneme geç
                                  if (!isActive && !isSelected)
                                    TextButton.icon(
                                      onPressed: () => _switchToTerm(term),
                                      icon: Icon(Icons.visibility, size: 18),
                                      label: Text('İncele'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue,
                                      ),
                                    ),
                                  // Menü
                                  PopupMenuButton(
                                    icon: Icon(Icons.more_vert),
                                    itemBuilder: (context) => [
                                      if (!isActive)
                                        PopupMenuItem(
                                          child: ListTile(
                                            leading: Icon(Icons.check_circle, color: Colors.green),
                                            title: Text('Aktif Dönem Yap'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          onTap: () => _setActiveTerm(term['id']),
                                        ),
                                      PopupMenuItem(
                                        child: ListTile(
                                          leading: Icon(Icons.edit, color: Colors.blue),
                                          title: Text('Düzenle'),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onTap: () => Future.delayed(Duration.zero, () => _showTermDialog(term: term)),
                                      ),
                                      if (!isActive)
                                        PopupMenuItem(
                                          child: ListTile(
                                            leading: Icon(Icons.copy, color: Colors.purple),
                                            title: Text('Verileri Aktif Döneme Kopyala'),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          onTap: () => Future.delayed(Duration.zero, () => _showCopyDataDialog(term)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _terms.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showTermDialog(),
              icon: Icon(Icons.add),
              label: Text('Yeni Dönem'),
              backgroundColor: Colors.indigo,
            )
          : null,
    );
  }
}
