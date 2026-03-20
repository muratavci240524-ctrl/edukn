import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
    'prices': {}, // { 'schoolTypeId_grade': { 'education': 0, 'food': 0 } }
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
      if (_schoolTypes.isNotEmpty) _selectedSchoolTypeId = _schoolTypes.first['id'];

      final settingsDoc = await FirebaseFirestore.instance
          .collection('preRegistrationSettings')
          .doc(widget.institutionId)
          .get();

      if (settingsDoc.exists) {
        setState(() {
          _settings = settingsDoc.data()!;
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
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Fiyat ve İndirim Ayarları'),
        actions: [
          TextButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('KAYDET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildMonthSelector(),
            _buildSchoolTypeTabs(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Sınıf Fiyatları', Icons.school_outlined),
                  _buildGradePriceList(),
                  const SizedBox(height: 32),
                  _buildSectionHeader('İndirim Tanımları', Icons.percent),
                  _buildDiscountList(),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Ödeme Yöntemi İndirimleri', Icons.payments_outlined),
                  _buildPaymentMethodList(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      height: 60,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _months.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedMonth == index + 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: ChoiceChip(
              label: Text(_months[index]),
              selected: isSelected,
              onSelected: (val) => setState(() => _selectedMonth = index + 1),
              selectedColor: Colors.indigo,
              labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSchoolTypeTabs() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: _schoolTypes.map((type) {
            final isSelected = _selectedSchoolTypeId == type['id'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton(
                onPressed: () => setState(() => _selectedSchoolTypeId = type['id']),
                style: OutlinedButton.styleFrom(
                  backgroundColor: isSelected ? Colors.indigo.shade50 : null,
                  side: BorderSide(color: isSelected ? Colors.indigo : Colors.grey.shade300),
                ),
                child: Text(type['schoolType'] ?? '', style: TextStyle(color: isSelected ? Colors.indigo : Colors.grey.shade700)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.indigo, size: 22),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
        ],
      ),
    );
  }

  Widget _buildGradePriceList() {
    if (_selectedSchoolTypeId == null) return const SizedBox();
    final type = _schoolTypes.firstWhere((t) => t['id'] == _selectedSchoolTypeId);
    final grades = type['activeGrades'] as List<dynamic>? ?? [];
    
    return Column(
      children: grades.map((grade) {
        final key = '${_selectedMonth}_${_selectedSchoolTypeId}_$grade';
        final priceData = _settings['prices'][key] ?? {'education': 0.0, 'food': 0.0};
        
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: ListTile(
            title: Text('$grade. Sınıf', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Row(
              children: [
                _priceLabel('Eğitim', priceData['education']),
                const SizedBox(width: 16),
                _priceLabel('Yemek', priceData['food']),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editPrice(key, grade.toString()),
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

  void _editPrice(String key, String gradeName) {
    final priceData = _settings['prices'][key] ?? {'education': 0.0, 'food': 0.0};
    final eduController = TextEditingController(text: (priceData['education'] ?? 0.0).toString());
    final foodController = TextEditingController(text: (priceData['food'] ?? 0.0).toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$gradeName Fiyatlarını Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: eduController, decoration: const InputDecoration(labelText: 'Eğitim Fiyatı'), keyboardType: TextInputType.number),
            TextField(controller: foodController, decoration: const InputDecoration(labelText: 'Yemek Fiyatı'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _settings['prices'][key] = {
                  'education': double.tryParse(eduController.text) ?? 0.0,
                  'food': double.tryParse(foodController.text) ?? 0.0,
                };
              });
              Navigator.pop(context);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountList() {
    final discounts = _settings['discounts'] as List<dynamic>;
    return Column(
      children: discounts.map((d) {
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: SwitchListTile(
            title: Text(d['name']),
            subtitle: Text('% ${d['percentage']}'),
            secondary: const Icon(Icons.sell_outlined),
            value: d['enabled'] ?? true,
            onChanged: (val) => setState(() => d['enabled'] = val),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentMethodList() {
    final methods = _settings['paymentMethods'] as List<dynamic>;
    return Column(
      children: methods.map((m) {
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
          child: ListTile(
            leading: const Icon(Icons.payment),
            title: Text(m['name']),
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: TextFormField(
                initialValue: m['discount'].toString(),
                decoration: const InputDecoration(suffixText: '%'),
                keyboardType: TextInputType.number,
                onChanged: (v) => m['discount'] = int.tryParse(v) ?? 0,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
