import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/guidance/demand_model.dart';
import '../../../../services/guidance/demand_service.dart';
import '../../../../services/term_service.dart';

class CreateDemandDialog extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String senderUid;
  final String senderName;
  final String senderRole;
  final Map<String, dynamic>? userData;

  const CreateDemandDialog({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.senderUid,
    required this.senderName,
    required this.senderRole,
    this.userData,
  }) : super(key: key);

  @override
  State<CreateDemandDialog> createState() => _CreateDemandDialogState();
}

class _CreateDemandDialogState extends State<CreateDemandDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  
  String _category = 'Rehberlik';
  DemandPriority _priority = DemandPriority.medium;
  
  String? _selectedStudentId;
  String? _selectedStudentName;
  String? _selectedStudentClassName;
  
  final List<Map<String, String>> _selectedReceivers = []; 

  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 600;

    if (isMobile) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          leading: IconButton(icon: const Icon(Icons.close, color: Color(0xFF1E293B)), onPressed: () => Navigator.pop(context)),
          title: Text('Yeni Talep', style: GoogleFonts.inter(color: const Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 18)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Oluştur', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16)),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: _buildContent())),
      );
    }

    return Dialog(
      backgroundColor: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 600,
        constraints: BoxConstraints(maxHeight: size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Yeni Talep Oluştur', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF111827))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.grey)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: _buildContent())),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context), 
                    child: Text('İptal', style: TextStyle(color: Colors.blueGrey.shade600))
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      child: _isSaving 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Text('Talebi Gönder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('MUHATAP KİŞİLER', Icons.people_outline),
          _buildReceiverMultiSelect(),
          const SizedBox(height: 28),
          
          _buildSectionHeader('İLGİLİ ÖĞRENCİ', Icons.person_outline),
          _buildStudentSearchSelect(),
          const SizedBox(height: 28),
          
          _buildSectionHeader('TALEP DETAYLARI', Icons.description_outlined),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _category,
                  isExpanded: true,
                  decoration: _inputDecoration('Kategori'),
                  items: ['Akademik', 'Disiplin', 'Rehberlik', 'Sosyal', 'Diğer']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14))))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<DemandPriority>(
                  value: _priority,
                  isExpanded: true,
                  decoration: _inputDecoration('Aciliyet'),
                  items: [
                    DropdownMenuItem(value: DemandPriority.low, child: const Text('Düşük', style: TextStyle(fontSize: 14))),
                    DropdownMenuItem(value: DemandPriority.medium, child: const Text('Normal', style: TextStyle(fontSize: 14))),
                    DropdownMenuItem(value: DemandPriority.high, child: const Text('Yüksek', style: TextStyle(fontSize: 14))),
                    DropdownMenuItem(value: DemandPriority.urgent, child: const Text('Acil 🚨', style: TextStyle(fontSize: 14))),
                  ],
                  onChanged: (v) => setState(() => _priority = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _titleController,
            style: const TextStyle(fontSize: 15),
            decoration: _inputDecoration('Başlık / Konu Özeti'),
            validator: (v) => v!.isEmpty ? 'Lütfen bir başlık girin' : null,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _descController,
            style: const TextStyle(fontSize: 15),
            decoration: _inputDecoration('Açıklama / Notlar'),
            maxLines: 5,
            validator: (v) => v!.isEmpty ? 'Lütfen detayları belirtin' : null,
          ),
          const SizedBox(height: 48), // Padding bottom
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.indigo),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade800, letterSpacing: 1.1)),
        ],
      ),
    );
  }

  Widget _buildReceiverMultiSelect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedReceivers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedReceivers.map((r) => Chip(
                label: Text(r['name']!, style: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.w500)),
                backgroundColor: Colors.indigo.shade50.withOpacity(0.5),
                deleteIcon: const Icon(Icons.close, size: 14, color: Colors.indigo),
                onDeleted: () => setState(() => _selectedReceivers.remove(r)),
                side: BorderSide(color: Colors.indigo.withOpacity(0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              )).toList(),
            ),
          ),
        InkWell(
          onTap: _showReceiverSearchModal,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300), 
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_selectedReceivers.isEmpty ? 'Kişi Seçin...' : 'Daha Fazla Kişi Ekle...', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14)),
                Icon(Icons.search, color: Colors.indigo.shade300, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentSearchSelect() {
    return InkWell(
      onTap: _showStudentSearchModal,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300), 
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_selectedStudentName ?? 'Öğrenci Seçin (Opsiyonel)', style: TextStyle(color: _selectedStudentName == null ? Colors.blueGrey.shade400 : Colors.black, fontSize: 14)),
            Icon(Icons.person_search, color: Colors.indigo.shade300, size: 20),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.blueGrey, fontSize: 13),
      floatingLabelStyle: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      filled: true,
      fillColor: Colors.white,
    );
  }

  void _showReceiverSearchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchSelectorModal(
        title: 'Kişi Seç',
        stream: FirebaseFirestore.instance.collection('users').where('institutionId', isEqualTo: widget.institutionId).snapshots(),
        onSelect: (id, name, data) {
          if (!_selectedReceivers.any((r) => r['id'] == id)) {
            setState(() => _selectedReceivers.add({'id': id, 'name': name}));
          }
        },
      ),
    );
  }

  void _showStudentSearchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchSelectorModal(
        title: 'Öğrenci Seç',
        stream: FirebaseFirestore.instance.collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true).snapshots(),
        onSelect: (id, name, data) {
          setState(() {
            _selectedStudentId = id;
            _selectedStudentName = name;
            _selectedStudentClassName = data['className'];
          });
        },
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedReceivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen en az bir muhatap kişi seçin.')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final termId = await TermService().getActiveTermId() ?? 'N/A';
      
      final demand = DemandModel(
        id: '',
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        termId: termId,
        senderUid: widget.senderUid,
        senderName: widget.senderName,
        senderRole: widget.senderRole,
        receiverUids: _selectedReceivers.map((r) => r['id']!).toList(),
        receiverNames: _selectedReceivers.map((r) => r['name']!).toList(),
        studentUid: _selectedStudentId,
        studentName: _selectedStudentName,
        studentClassName: _selectedStudentClassName,
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        category: _category,
        priority: _priority,
        status: DemandStatus.open,
        createdAt: DateTime.now(),
      );

      await DemandService().createDemand(demand);
      Navigator.pop(context);
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilirken hata oluştu: $e')));
    }
  }
}

class _SearchSelectorModal extends StatefulWidget {
  final String title;
  final Stream<QuerySnapshot> stream;
  final Function(String id, String name, Map<String, dynamic> data) onSelect;

  const _SearchSelectorModal({required this.title, required this.stream, required this.onSelect});

  @override
  State<_SearchSelectorModal> createState() => _SearchSelectorModalState();
}

class _SearchSelectorModalState extends State<_SearchSelectorModal> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'İsim ile ara...',
              prefixIcon: const Icon(Icons.search, color: Colors.indigo),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: widget.stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData) return const Center(child: Text('Veri bulunamadı.'));
                
                final docs = snapshot.data!.docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final name = (data['fullName'] ?? '').toString().toLowerCase();
                  return name.contains(_search);
                }).toList();

                if (docs.isEmpty) return const Center(child: Text('Bulunamadı.'));

                return ListView.separated(
                  itemCount: docs.length,
                  padding: const EdgeInsets.only(bottom: 40),
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final d = docs[index];
                    final data = d.data() as Map<String, dynamic>;
                    final name = data['fullName'] ?? 'İsimsiz';
                    final sub = data['className'] ?? data['role'] ?? '';
                    
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: CircleAvatar(backgroundColor: Colors.indigo.shade50, child: Text(name[0], style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold))),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      subtitle: Text(sub, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400)),
                      trailing: const Icon(Icons.add_circle_outline, color: Colors.indigo, size: 20),
                      onTap: () {
                        widget.onSelect(d.id, name, data);
                        if (widget.title.contains('Öğrenci')) Navigator.pop(context); 
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
