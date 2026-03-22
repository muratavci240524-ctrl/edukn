import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:edukn/widgets/edukn_logo.dart';
import 'package:google_fonts/google_fonts.dart';

class PreRegistrationSettingsScreen extends StatefulWidget {
  final String institutionId;

  const PreRegistrationSettingsScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  _PreRegistrationSettingsScreenState createState() => _PreRegistrationSettingsScreenState();
}

class _PreRegistrationSettingsScreenState extends State<PreRegistrationSettingsScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _schoolTypes = [];
  String? _selectedSchoolTypeId;
  int _selectedMonth = DateTime.now().month;
  
  Map<String, dynamic> _settings = {
    'priceTypes': ['Eğitim', 'Yemek'],
    'prices': {}, // { 'month_schoolTypeId_grade': { 'priceType': amount } }
    'discounts': [
      {'id': 'early', 'name': 'Erken Kayıt', 'percentage': 10, 'enabled': true, 'applyTo': ['education']},
      {'id': 'sibling', 'name': 'Kardeş', 'percentage': 12, 'enabled': true, 'applyTo': ['education']},
      {'id': 'transfer', 'name': 'Geçiş', 'percentage': 20, 'enabled': true, 'applyTo': ['education']},
      {'id': 'teacher', 'name': 'Öğretmen', 'percentage': 5, 'enabled': true, 'applyTo': ['education']},
    ],
    'paymentMethods': [
      {'id': 'cash', 'name': 'Peşin', 'discount': 12},
      {'id': 'credit_card', 'name': 'Tek Çekim', 'discount': 10},
      {'id': 'installments', 'name': 'Taksit', 'discount': 0},
      {'id': 'credit_card_installments', 'name': 'Taksitli Tek Çekim', 'discount': 8},
    ]
  };

  final List<String> _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final typesQuery = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      
      _schoolTypes = typesQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      
      // Sort school types: Anaokulu first
      _schoolTypes.sort((a, b) {
        final order = ['anaokulu', 'kreş', 'ilkokul', 'ortaokul', 'lise'];
        final aType = (a['schoolType'] ?? '').toString().toLowerCase();
        final bType = (b['schoolType'] ?? '').toString().toLowerCase();
        int aIdx = order.indexWhere((e) => aType.contains(e));
        int bIdx = order.indexWhere((e) => bType.contains(e));
        if (aIdx == -1) aIdx = 99;
        if (bIdx == -1) bIdx = 99;
        return aIdx.compareTo(bIdx);
      });

      if (_schoolTypes.isNotEmpty) _selectedSchoolTypeId = _schoolTypes.first['id'];

      final settingsDoc = await FirebaseFirestore.instance
          .collection('preRegistrationSettings')
          .doc(widget.institutionId)
          .get();

      if (settingsDoc.exists) {
        final data = settingsDoc.data()!;
        // Ensure priceTypes exists
        if (data['priceTypes'] == null) data['priceTypes'] = ['Eğitim', 'Yemek'];
        setState(() {
          _settings = data;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading settings: $e');
      setState(() => _isLoading = false);
    }
  }

  void _copySettingsToOthers() {
    showDialog(
      context: context,
      builder: (context) {
        List<int> targetMonths = [];
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ayarları Diğer Aylara Kopyala'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_months[_selectedMonth - 1]} ayı ayarlarını hangi aylara kopyalamak istersiniz?'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 400,
                    child: Wrap(
                      spacing: 8,
                      children: List.generate(12, (index) {
                        final monthIndex = index + 1;
                        if (monthIndex == _selectedMonth) return const SizedBox();
                        final isSelected = targetMonths.contains(monthIndex);
                        return FilterChip(
                          label: Text(_months[index]),
                          selected: isSelected,
                          onSelected: (val) {
                            setDialogState(() {
                              if (val) targetMonths.add(monthIndex);
                              else targetMonths.remove(monthIndex);
                            });
                          },
                        );
                      }),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('İPTAL')),
                ElevatedButton(
                  onPressed: targetMonths.isEmpty ? null : () {
                    setState(() {
                      final currentMonthPrefix = '${_selectedMonth}_';
                      Map<String, dynamic> newPrices = Map.from(_settings['prices']);
                      
                      // Find all keys for current month
                      final sourceKeys = _settings['prices'].keys.where((k) => k.toString().startsWith(currentMonthPrefix)).toList();
                      
                      for (var targetMonth in targetMonths) {
                        final targetPrefix = '${targetMonth}_';
                        for (var sourceKey in sourceKeys) {
                          final newKey = sourceKey.toString().replaceFirst(currentMonthPrefix, targetPrefix);
                          newPrices[newKey] = _settings['prices'][sourceKey];
                        }
                      }
                      _settings['prices'] = newPrices;
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ayarlar başarıyla kopyalandı.')));
                  },
                  child: const Text('KOPYALA'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _saveSettings() async {
    try {
      await FirebaseFirestore.instance
          .collection('preRegistrationSettings')
          .doc(widget.institutionId)
          .set(_settings);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Ayarlar kaydedildi'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: EduKnLoader(size: 100)));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Fiyat ve İndirim Ayarları', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        actions: [
          IconButton(
            onPressed: _copySettingsToOthers,
            icon: const Icon(Icons.copy_all, color: Colors.indigo),
            tooltip: 'Aylara Kopyala',
          ),
          const SizedBox(width: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = MediaQuery.of(context).size.width < 600;
              if (isMobile) {
                return IconButton(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save, color: Colors.indigo),
                  tooltip: 'Kaydet',
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: ElevatedButton.icon(
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('KAYDET', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            }
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1800),
          child: Column(
            children: [
              _buildMonthSelector(),
              const Divider(height: 1),
              _buildSchoolTypeTabs(),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(
                        'Sınıf Fiyatları', 
                        Icons.school_outlined,
                        onEdit: _editPriceTitles,
                      ),
                      _buildGradePriceList(),
                      const SizedBox(height: 48),
                      _buildSectionHeader(
                        'İndirim Tanımları', 
                        Icons.percent,
                        onEdit: () => _manageDiscounts(),
                      ),
                      _buildInfoBanner('İndirimler yukarıdan aşağıya doğru sırasıyla uygulanacaktır. Yüzde alanını boş bırakırsanız kayıt esnasında manuel (Serbest Metin) giriş yapılabilecektir.'),
                      _buildDiscountList(),
                      const SizedBox(height: 48),
                      _buildSectionHeader(
                        'Ödeme Yöntemleri', 
                        Icons.payments_outlined,
                        onEdit: () => _managePaymentMethods(),
                      ),
                      _buildPaymentMethodList(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editPriceTitles() {
    List<String> tempPriceTypes = List.from(_settings['priceTypes'] ?? []);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Fiyat Başlıklarını Düzenle'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...tempPriceTypes.asMap().entries.map((entry) {
                  int idx = entry.key;
                  String val = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: val,
                            onChanged: (newVal) => tempPriceTypes[idx] = newVal,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () {
                            setDialogState(() => tempPriceTypes.removeAt(idx));
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    setDialogState(() => tempPriceTypes.add('Yeni Başlık'));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Fiyat Türü Ekle'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _settings['priceTypes'] = tempPriceTypes;
                });
                Navigator.pop(context);
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      height: 64,
      color: Colors.white,
      child: Center(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
            },
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _months.length,
            itemBuilder: (context, index) {
              final isSelected = _selectedMonth == index + 1;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: ChoiceChip(
                  label: Text(_months[index]),
                  selected: isSelected,
                  showCheckmark: false,
                  onSelected: (val) => setState(() => _selectedMonth = index + 1),
                  selectedColor: Colors.indigo,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: isSelected ? Colors.indigo : const Color(0xFFE2E8F0)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolTypeTabs() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
            },
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _schoolTypes.map((type) {
                final isSelected = _selectedSchoolTypeId == type['id'];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: OutlinedButton(
                      onPressed: () => setState(() => _selectedSchoolTypeId = type['id']),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.indigo.shade50 : Colors.transparent,
                        foregroundColor: isSelected ? Colors.indigo : const Color(0xFF64748B),
                        side: BorderSide(color: isSelected ? Colors.indigo : const Color(0xFFE2E8F0)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        type['schoolType'] ?? '',
                        style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {VoidCallback? onEdit}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.indigo, size: 24),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          if (onEdit != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = MediaQuery.of(context).size.width < 600;
                final label = title.contains('Sınıf') ? 'DÜZENLE' : 'YÖNET';
                final iconData = title.contains('Sınıf') ? Icons.settings_outlined : Icons.edit_note_outlined;
                
                if (isMobile) {
                  return IconButton(
                    onPressed: onEdit,
                    icon: Icon(iconData, color: Colors.indigo),
                    tooltip: label,
                  );
                }
                
                return TextButton.icon(
                  onPressed: onEdit,
                  icon: Icon(iconData, size: 18),
                  label: Text(label),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                );
              }
            ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.blue.shade900, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatGradeName(dynamic grade) {
    if (_selectedSchoolTypeId == null) return grade.toString();
    final typeDoc = _schoolTypes.firstWhere((t) => t['id'] == _selectedSchoolTypeId, orElse: () => {});
    final schoolType = (typeDoc['schoolType'] ?? '').toString().toLowerCase();
    
    String gradeStr = grade.toString().replaceAll('. Sınıf', '').replaceAll(' Yaş', '').trim();
    
    if (schoolType.contains('anaokulu') || schoolType.contains('kreş')) {
      return '$gradeStr Yaş';
    } else {
      return '$gradeStr. Sınıf';
    }
  }

  Widget _buildGradePriceList() {
    if (_selectedSchoolTypeId == null) return const Center(child: Text('Lütfen bir okul türü seçin'));
    final type = _schoolTypes.firstWhere((t) => t['id'] == _selectedSchoolTypeId, orElse: () => {});
    if (type.isEmpty) return const SizedBox();
    final grades = type['activeGrades'] as List<dynamic>? ?? [];
    if (grades.isEmpty) return const Center(child: Text('Bu okul türü için aktif sınıf bulunamadı'));

    final List<String> priceTypes = List<String>.from(_settings['priceTypes'] ?? ['Eğitim', 'Yemek']);

    return Column(
      children: grades.map((grade) {
        final key = '${_selectedMonth}_${_selectedSchoolTypeId}_$grade';
        final priceData = _settings['prices'][key] ?? {};

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: InkWell(
            onTap: () => _editPrice(key, _formatGradeName(grade)),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                   Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(Icons.class_outlined, color: Colors.indigo, size: 24),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatGradeName(grade),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: priceTypes.map((type) => _priceLabel(type, priceData[type])).toList(),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 22, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _priceLabel(String label, dynamic value) {
    final amount = value ?? 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),
      child: Text('$label: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(amount)}', style: const TextStyle(fontSize: 12, color: Colors.indigo)),
    );
  }

  void _showBottomSheet({required Widget child}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
          ],
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 12, left: 20, right: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48, height: 5,
                margin: const EdgeInsets.only(bottom: 24, top: 8),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
              ),
              child,
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _editPrice(String key, String gradeName) {
    final priceData = Map<String, dynamic>.from(_settings['prices'][key] ?? {});
    final List<String> priceTypes = List<String>.from(_settings['priceTypes'] ?? ['Eğitim', 'Yemek']);
    final Map<String, TextEditingController> controllers = {
      for (var type in priceTypes) type: TextEditingController(text: (priceData[type] ?? 0.0).toString())
    };

    _showBottomSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$gradeName Sınıf Fiyatları', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text('Bu sınıf için eğitim ve ek hizmet bedellerini belirleyin.', style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B))),
          const SizedBox(height: 24),
          ...controllers.entries.map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: TextField(
                controller: entry.value,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                decoration: InputDecoration(
                  labelText: entry.key,
                  labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                  suffixText: '₺',
                  suffixStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.indigo),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            );
          }).toList(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  final Map<String, double> updatedValues = {};
                  controllers.forEach((type, ctrl) {
                    updatedValues[type] = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0.0;
                  });
                  _settings['prices'][key] = updatedValues;
                  _saveSettings();
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4C59BC),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text('FİYATLARI GÜNCELLE', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountList() {
    final List<dynamic> discounts = _settings['discounts'] ?? [];
    return Column(
      children: discounts.map((d) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.sell_outlined, color: Colors.orange, size: 20),
            ),
            title: Text(d['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF334155), fontSize: 16)),
            subtitle: Text(
              d['percentage'] == null || d['percentage'] == 0 
                ? 'Manuel Giriş' 
                : '% ${d['percentage']}', 
              style: GoogleFonts.inter(
                color: d['percentage'] == null || d['percentage'] == 0 ? Colors.orange.shade700 : Colors.indigo.shade600, 
                fontWeight: FontWeight.w600,
                fontSize: 13
              )
            ),
            trailing: Transform.scale(
              scale: 0.85,
              child: Switch(
                value: d['enabled'] ?? true,
                onChanged: (val) => setState(() => d['enabled'] = val),
                activeColor: Colors.indigo,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _manageDiscounts() {
    _showBottomSheet(
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('İndirimleri Yönet', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
              const SizedBox(height: 6),
              Text('Sıralamayı değiştirmek için satırlara basılı tutup sürükleyin.', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
              const SizedBox(height: 24),
              SizedBox(
                height: 450,
                child: ReorderableListView(
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.1), blurRadius: 20)],
                        ),
                        child: child,
                      ),
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _settings['discounts'].removeAt(oldIndex);
                      _settings['discounts'].insert(newIndex, item);
                    });
                    setDialogState(() {});
                  },
                  children: [
                    for (int i = 0; i < _settings['discounts'].length; i++)
                      ReorderableDragStartListener(
                        key: ValueKey(_settings['discounts'][i]['id']),
                        index: i,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            title: Text(_settings['discounts'][i]['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF334155), fontSize: 15)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _settings['discounts'][i]['percentage'] == null || _settings['discounts'][i]['percentage'] == 0 ? ' Manuel Giriş' : '% ${_settings['discounts'][i]['percentage']} İndirim',
                                style: GoogleFonts.inter(
                                  color: _settings['discounts'][i]['percentage'] == null || _settings['discounts'][i]['percentage'] == 0 ? Colors.orange.shade700 : Colors.indigo.shade600,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13
                                ),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_note_outlined, color: Color(0xFF94A3B8), size: 22), 
                                  onPressed: () => _showDiscountDialog(_settings['discounts'][i], onUpdate: () => setDialogState(() {}))
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22), 
                                  onPressed: () => _deleteDiscount(_settings['discounts'][i], onDeleted: () => setDialogState(() {}))
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.drag_indicator_rounded, color: Color(0xFFCBD5E1), size: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () => _showDiscountDialog(null, onUpdate: () => setDialogState(() {})),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text('YENİ İNDİRİM TANIMLA', style: GoogleFonts.inter(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C59BC), 
                    foregroundColor: Colors.white, 
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showDiscountDialog(Map<String, dynamic>? discount, {VoidCallback? onUpdate}) {
    final nameCtrl = TextEditingController(text: discount?['name'] ?? '');
    final percentCtrl = TextEditingController(text: discount?['percentage'] == null ? '' : (discount?['percentage'] ?? 0).toString());
    final List<String> priceTypes = List<String>.from(_settings['priceTypes'] ?? ['Eğitim', 'Yemek']);
    List<String> selectedApplyTo = List<String>.from(discount?['applyTo'] ?? []);

    _showBottomSheet(
      child: StatefulBuilder(builder: (context, setModalState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(discount == null ? 'Yeni İndirim Ekle' : 'İndirimi Düzenle', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: TextField(
                controller: nameCtrl, 
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                decoration: InputDecoration(
                  labelText: 'İndirim Adı (Örn: Burs)', 
                  labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), 
                  filled: true, 
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                )
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: TextField(
                controller: percentCtrl, 
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                decoration: InputDecoration(
                  labelText: 'Yüzde (%)', 
                  labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                  hintText: 'Boş bırakılırsa manuel giriş olur',
                  hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), 
                  filled: true, 
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                ), 
                keyboardType: TextInputType.number
              ),
            ),
            const SizedBox(height: 24),
            Text('Uygulanacak Ücret Türleri', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Text('Seçim yapılmazsa tüm toplama uygulanır.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: priceTypes.map((type) {
                final isSelected = selectedApplyTo.contains(type);
                return FilterChip(
                  label: Text(type),
                  selected: isSelected,
                  onSelected: (val) {
                    setModalState(() {
                      if (val) selectedApplyTo.add(type);
                      else selectedApplyTo.remove(type);
                    });
                  },
                  selectedColor: const Color(0xFF4C59BC).withOpacity(0.2),
                  checkmarkColor: const Color(0xFF4C59BC),
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12, 
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? const Color(0xFF4C59BC) : const Color(0xFF64748B)
                  ),
                  backgroundColor: const Color(0xFFF1F5F9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? const Color(0xFF4C59BC) : Colors.transparent)),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    final percentage = percentCtrl.text.isEmpty ? null : int.tryParse(percentCtrl.text);
                    if (discount == null) {
                      _settings['discounts'].add({
                        'id': DateTime.now().millisecondsSinceEpoch.toString(),
                        'name': nameCtrl.text,
                        'percentage': percentage,
                        'applyTo': selectedApplyTo,
                        'enabled': true,
                      });
                    } else {
                      discount['name'] = nameCtrl.text;
                      discount['percentage'] = percentage;
                      discount['applyTo'] = selectedApplyTo;
                    }
                    _saveSettings();
                  });
                  if (onUpdate != null) onUpdate();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4C59BC), 
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(discount == null ? 'İNDİRİMİ EKLE' : 'GÜNCELLE', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _deleteDiscount(Map<String, dynamic> discount, {VoidCallback? onDeleted}) {
    _showBottomSheet(
      child: Column(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 56),
          const SizedBox(height: 16),
          Text('İndirimi Sil', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
          const SizedBox(height: 12),
          Text('${discount['name']} indirimini silmek istediğinize emin misiniz?', textAlign: TextAlign.center, style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 15)),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('İPTAL', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _settings['discounts'].remove(discount);
                      _saveSettings();
                    });
                    if (onDeleted != null) onDeleted();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: Text('SİL', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _managePaymentMethods() {
    _showBottomSheet(
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ödeme Yöntemlerini Yönet', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
              const SizedBox(height: 8),
              Text('Mevcut ödeme yöntemlerini düzenleyebilir veya silebilirsiniz.', style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B))),
              const SizedBox(height: 24),
              SizedBox(
                height: 350,
                child: ListView(
                  children: [
                    for (var m in _settings['paymentMethods'])
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          title: Text(m['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF334155), fontSize: 15)),
                          subtitle: Text('İndirim Oranı: % ${m['discount']}', style: GoogleFonts.inter(color: Colors.indigo, fontWeight: FontWeight.w600, fontSize: 13)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_note_outlined, color: Color(0xFF94A3B8), size: 22), 
                                onPressed: () => _showPaymentMethodDialog(m, onUpdate: () => setDialogState(() {}))
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22), 
                                onPressed: () => _deletePaymentMethod(m, onDeleted: () => setDialogState(() {}))
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () => _showPaymentMethodDialog(null, onUpdate: () => setDialogState(() {})),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text('YENİ ÖDEME YÖNTEMİ EKLE', style: GoogleFonts.inter(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C59BC), 
                    foregroundColor: Colors.white, 
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showPaymentMethodDialog(Map<String, dynamic>? method, {VoidCallback? onUpdate}) {
    final nameCtrl = TextEditingController(text: method?['name'] ?? '');
    final discountCtrl = TextEditingController(text: (method?['discount'] ?? 0).toString());

    _showBottomSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(method == null ? 'Yeni Ödeme Yöntemi Ekle' : 'Ödeme Yöntemini Düzenle', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: TextField(
              controller: nameCtrl, 
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
              decoration: InputDecoration(
                labelText: 'Yöntem Adı', 
                labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), 
                filled: true, 
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              )
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: TextField(
              controller: discountCtrl, 
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
              decoration: InputDecoration(
                labelText: 'İndirim/Vade Oranı (%)', 
                labelStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), 
                filled: true, 
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              ), 
              keyboardType: TextInputType.number
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  if (method == null) {
                    _settings['paymentMethods'].add({
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'name': nameCtrl.text,
                      'discount': int.tryParse(discountCtrl.text) ?? 0,
                    });
                  } else {
                    method['name'] = nameCtrl.text;
                    method['discount'] = int.tryParse(discountCtrl.text) ?? 0;
                  }
                  _saveSettings();
                });
                if (onUpdate != null) onUpdate();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4C59BC), 
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text('KAYDET', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _deletePaymentMethod(Map<String, dynamic> method, {VoidCallback? onDeleted}) {
    _showBottomSheet(
      child: Column(
        children: [
          const Icon(Icons.delete_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          const Text('Ödeme Yöntemini Sil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('${method['name']} yöntemini silmek istediğinize emin misiniz?', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İPTAL'),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _settings['paymentMethods'].remove(method);
                      _saveSettings();
                    });
                    if (onDeleted != null) onDeleted();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('SİL'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodList() {
    final List<dynamic> methods = _settings['paymentMethods'] ?? [];
    return Column(
      children: methods.map((m) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.payment, color: Colors.blue, size: 20),
            ),
            title: Text(m['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF334155), fontSize: 16)),
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: TextFormField(
                initialValue: (m['discount'] ?? 0).toString(),
                decoration: InputDecoration(
                  suffixText: '%', 
                  suffixStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13),
                  isDense: true, 
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.indigo, width: 2),
                  ),
                ),
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.indigo, fontSize: 15),
                keyboardType: TextInputType.number,
                onChanged: (v) => m['discount'] = int.tryParse(v) ?? 0,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// Global scroll behavior for mouse dragging on web
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}
