import 'package:flutter/material.dart';

class StudentDetailViewScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  const StudentDetailViewScreen({Key? key, required this.student})
      : super(key: key);

  @override
  _StudentDetailViewScreenState createState() =>
      _StudentDetailViewScreenState();
}

class _StudentDetailViewScreenState extends State<StudentDetailViewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, dynamic> _student;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _student = widget.student;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: Colors.grey.shade800),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Öğrenci Detayı',
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          tabs: const [
            Tab(text: 'Kişisel Bilgiler'),
            Tab(text: 'Okul Bilgileri'),
            Tab(text: 'Veli Bilgileri'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPersonalInfoTab(),
          _buildSchoolInfoTab(),
          _buildParentInfoTab(),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoTab() {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 16, vertical: 10),
      child: Column(
        children: [
          _buildInfoCard(
            title: 'Genel Bilgiler',
            icon: Icons.person,
            children: [
              _buildStudentPhotoAndName(),
              const Divider(height: 32),
              _buildInfoRow('TC:', _student['tcNo'] ?? '-'),
              _buildInfoRow('Doğum Tarihi:', _student['birthDate'] ?? '-'),
              _buildInfoRow('Doğum Yeri:', _student['birthPlace'] ?? '-'),
              _buildInfoRow('Cinsiyet:', _student['gender'] ?? '-'),
              _buildInfoRow('Uyruk:', _student['nationality'] ?? 'T.C.'),
              _buildInfoRow('Kan Grubu:', _student['bloodType'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: 'İletişim Bilgileri',
            icon: Icons.contact_phone,
            children: [
              _buildInfoRow('E-posta (Kurumsal):', _student['email'] ?? '-'),
              _buildInfoRow(
                'E-posta (Kişisel):',
                _student['personalEmail'] ?? '-',
              ),
              _buildInfoRow('Telefon (Cep):', _student['phone'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: 'Adres Bilgileri',
            icon: Icons.location_on,
            children: [
              _buildInfoRow(
                'İl / İlçe:',
                '${_student['city'] ?? '-'} / ${_student['district'] ?? '-'}',
              ),
              _buildInfoRow('Açık Adres:', _student['address'] ?? '-'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolInfoTab() {
    final isMobile = MediaQuery.of(context).size.width <= 900;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 16, vertical: 10),
      child: Column(
        children: [
          _buildInfoCard(
            title: 'Kayıt Bilgileri',
            icon: Icons.how_to_reg,
            children: [
              _buildInfoRow('Öğrenci No:', _student['studentNo'] ?? '-'),
              _buildInfoRow('Okul Türü:', _student['schoolTypeName'] ?? '-'),
              _buildInfoRow(
                'Sınıf / Şube:',
                '${_student['classLevel'] ?? '-'}. Sınıf / ${_student['className'] ?? '-'}',
              ),
              _buildInfoRow(
                'Kayıt Tarihi:',
                _student['registrationDate'] ?? '-',
              ),
              _buildInfoRow('Giriş Türü:', _student['entryType'] ?? '-'),
              _buildInfoRow('Kayıt Türü:', _student['registrationType'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            title: 'Eğitim Bilgileri',
            icon: Icons.history_edu,
            children: [
              _buildInfoRow('Geldiği Okul:', _student['previousSchool'] ?? '-'),
              _buildInfoRow('Eğitim Şekli:', _student['educationType'] ?? '-'),
              _buildInfoRow(
                '1. Yabancı Dil:',
                _student['foreignLanguage'] ?? '-',
              ),
              _buildInfoRow('Referans:', _student['reference'] ?? '-'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParentInfoTab() {
    final parents = _student['parents'] as List? ?? [];
    if (parents.isEmpty) {
      return const Center(child: Text('Veli bilgisi bulunamadı.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: parents.length,
      itemBuilder: (context, index) {
        final parent = parents[index];
        return _buildParentCard(parent);
      },
    );
  }

  Widget _buildParentCard(Map<String, dynamic> parent) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.indigo),
                const SizedBox(width: 12),
                Text(
                  parent['fullName'] ?? '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  parent['relation'] ?? 'Veli',
                  style: const TextStyle(
                    color: Colors.indigo,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow('TC No:', parent['tcNo'] ?? '-'),
                _buildInfoRow('Telefon:', parent['phone'] ?? '-'),
                _buildInfoRow('E-posta:', parent['email'] ?? '-'),
                _buildInfoRow('Meslek:', parent['occupation'] ?? '-'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentPhotoAndName() {
    return Row(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: Colors.grey.shade200,
          child: Icon(Icons.person, size: 40, color: Colors.grey.shade400),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _student['fullName'] ?? '-',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'ÖĞRENCİ ${_student['studentNo'] ?? ''} - ${_student['className'] ?? ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.indigo),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final cleanLabel = label.endsWith(':') ? label.substring(0, label.length - 1) : label;
    final showValue = value.isNotEmpty ? value : '-';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cleanLabel,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            showValue,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}
