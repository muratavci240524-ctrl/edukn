import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../services/user_permission_service.dart';

class AccountingDashboardScreen extends StatefulWidget {
  const AccountingDashboardScreen({Key? key}) : super(key: key);

  @override
  _AccountingDashboardScreenState createState() =>
      _AccountingDashboardScreenState();
}

class _AccountingDashboardScreenState extends State<AccountingDashboardScreen> {
  bool _isLoading = true;
  String? _institutionId;
  Map<String, dynamic>? userData;
  
  // Dashboard stats
  double _totalBalance = 0.0;
  double _dailyIn = 0.0;
  double _dailyOut = 0.0;
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _cashes = []; // Kasalar

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email!;
      _institutionId = email.split('@')[1].split('.')[0].toUpperCase();

      final data = await UserPermissionService.loadUserData();
      setState(() => userData = data);

      await _refreshData();
    } catch (e) {
      print('Accounting Dashboard Init Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshData() async {
    if (_institutionId == null) return;

    // Load Kasalar
    final cashQuery = await FirebaseFirestore.instance
        .collection('cashes')
        .where('institutionId', isEqualTo: _institutionId)
        .get();

    // Default cash if none exists
    if (cashQuery.docs.isEmpty) {
      await FirebaseFirestore.instance.collection('cashes').add({
        'institutionId': _institutionId,
        'name': 'Ana Kasa',
        'balance': 0.0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _refreshData();
      return;
    }

    // Load recent transactions (last 20)
    final transQuery = await FirebaseFirestore.instance
        .collection('transactions')
        .where('institutionId', isEqualTo: _institutionId)
        .orderBy('date', descending: true)
        .limit(20)
        .get();

    // Calculate daily in/out (from today)
    DateTime now = DateTime.now();
    DateTime startOfDay = DateTime(now.year, now.month, now.day);
    final dailyQuery = await FirebaseFirestore.instance
        .collection('transactions')
        .where('institutionId', isEqualTo: _institutionId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .get();

    double di = 0;
    double do_ = 0;
    for (var doc in dailyQuery.docs) {
      final amount = (doc['amount'] as num).toDouble();
      if (doc['type'] == 'income') {
        di += amount;
      } else {
        do_ += amount;
      }
    }

    double total = 0;
    for (var doc in cashQuery.docs) {
      total += (doc['balance'] as num).toDouble();
    }

    setState(() {
      _cashes = cashQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _recentTransactions = transQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      _totalBalance = total;
      _dailyIn = di;
      _dailyOut = do_;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ön Muhasebe / Mali İşler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshData(),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildQuickStatCards(),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildRecentTransactions()),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: _buildRightPanel()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatCards() {
    return Row(
      children: [
        _buildStatCard('Genel Bakiye (Tüm Kasalar)', _totalBalance, Colors.indigo, Icons.account_balance_wallet),
        const SizedBox(width: 16),
        _buildStatCard('Bugünkü Gelir', _dailyIn, Colors.green, Icons.trending_up),
        const SizedBox(width: 16),
        _buildStatCard('Bugünkü Gider', _dailyOut, Colors.red, Icons.trending_down),
      ],
    );
  }

  Widget _buildStatCard(String title, double amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(amount),
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransactions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Son İşlemler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton(onPressed: () {}, child: const Text('Tümünü Gör')),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: _recentTransactions.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Henüz işlem kaydı yok.')))
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentTransactions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final trans = _recentTransactions[index];
                    final isIncome = trans['type'] == 'income';
                    final date = (trans['date'] as Timestamp).toDate();
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isIncome ? Colors.green.shade50 : Colors.red.shade50,
                        child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: isIncome ? Colors.green : Colors.red, size: 18),
                      ),
                      title: Text(trans['description'] ?? 'Açıklamasız İşlem', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('${DateFormat('dd.MM.yyyy HH:mm').format(date)} | ${trans['kasaName']}'),
                      trailing: Text(
                        (isIncome ? '+ ' : '- ') + NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(trans['amount']),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isIncome ? Colors.green : Colors.red),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRightPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hızlı İşlemler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildQuickButton('Gelir Kaydı', Icons.add_circle, Colors.green, () => _showTransactionDialog('income')),
            _buildQuickButton('Gider Kaydı', Icons.remove_circle, Colors.red, () => _showTransactionDialog('expense')),
            _buildQuickButton('Veli Tahsilat', Icons.person_add, Colors.blue, () {}),
            _buildQuickButton('Makbuz Al', Icons.receipt_long, Colors.purple, () {}),
          ],
        ),
        const SizedBox(height: 32),
        const Text('Kasa Durumları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: _cashes.map((kasa) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(kasa['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(kasa['balance']),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 32),
        const Text('Raporlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: const Icon(Icons.calendar_month, color: Colors.indigo),
          title: const Text('Geciken Taksitler Raporu'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildQuickButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _showTransactionDialog(String type) {
    final descController = TextEditingController();
    final amController = TextEditingController();
    String? selectedKasaId = _cashes.isNotEmpty ? _cashes.first['id'] : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(type == 'income' ? 'Gelir Kaydı' : 'Gider Kaydı'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'Açıklama')),
              const SizedBox(height: 12),
              TextField(controller: amController, decoration: const InputDecoration(labelText: 'Tutar', suffixText: '₺'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedKasaId,
                decoration: const InputDecoration(labelText: 'Kasa'),
                items: _cashes.map((k) => DropdownMenuItem(value: k['id'] as String, child: Text(k['name']))).toList(),
                onChanged: (v) => setState(() => selectedKasaId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amController.text) ?? 0;
                if (amount <= 0 || selectedKasaId == null) return;

                final transData = {
                  'institutionId': _institutionId,
                  'type': type,
                  'description': descController.text,
                  'amount': amount,
                  'kasaId': selectedKasaId,
                  'kasaName': _cashes.firstWhere((k) => k['id'] == selectedKasaId)['name'],
                  'date': FieldValue.serverTimestamp(),
                  'userId': FirebaseAuth.instance.currentUser?.uid,
                };

                // Add transaction
                await FirebaseFirestore.instance.collection('transactions').add(transData);

                // Update kasa balance
                final kasaRef = FirebaseFirestore.instance.collection('cashes').doc(selectedKasaId);
                await FirebaseFirestore.instance.runTransaction((tx) async {
                  final snap = await tx.get(kasaRef);
                  final oldBal = (snap['balance'] as num).toDouble();
                  tx.update(kasaRef, {'balance': type == 'income' ? oldBal + amount : oldBal - amount});
                });

                Navigator.pop(context);
                _refreshData();
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}
