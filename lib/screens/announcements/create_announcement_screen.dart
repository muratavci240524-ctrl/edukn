import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/announcement_service.dart';
import '../../widgets/recipient_selector_field.dart';

class CreateAnnouncementScreen extends StatefulWidget {
  final String? announcementId;
  final Map<String, dynamic>? announcementData;
  final String? schoolTypeId;
  final String? schoolTypeName;

  const CreateAnnouncementScreen({
    Key? key,
    this.announcementId,
    this.announcementData,
    this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  State<CreateAnnouncementScreen> createState() =>
      _CreateAnnouncementScreenState();
}

class _CreateAnnouncementScreenState extends State<CreateAnnouncementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _searchController = TextEditingController();
  final AnnouncementService _announcementService = AnnouncementService();

  List<String> _selectedRecipients = [];
  Map<String, String> _recipientNames = {};
  DateTime _publishDate = DateTime.now();
  TimeOfDay _publishTime = TimeOfDay.now();
  final List<TextEditingController> _links = [];
  final List<TextEditingController> _linkNames = [];
  bool _sendSms = false;
  bool _isAnonymous = false;
  bool _schedulePublish = false;
  List<Map<String, dynamic>> _reminders = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadExistingData();
  }

  void _loadExistingData() {
    if (widget.announcementData != null) {
      final data = widget.announcementData!;
      _title.text = data['title'] ?? '';
      _content.text = data['content'] ?? '';
      _selectedRecipients = List<String>.from(data['recipients'] ?? []);
      _recipientNames = Map<String, String>.from(data['recipientNames'] ?? {});
      _sendSms = data['sendSms'] ?? false;
      _isAnonymous = data['isAnonymous'] ?? false;
      _schedulePublish = data['schedulePublish'] ?? false;

      if (data['publishDate'] != null) {
        final publishDate = (data['publishDate'] as Timestamp).toDate();
        _publishDate = publishDate;
        _publishTime = TimeOfDay(
          hour: publishDate.hour,
          minute: publishDate.minute,
        );
      }

      final links = data['links'] as List<dynamic>? ?? [];
      for (var link in links) {
        if (link is Map) {
          _linkNames.add(TextEditingController(text: link['name'] ?? ''));
          _links.add(TextEditingController(text: link['url'] ?? ''));
        } else {
          _linkNames.add(TextEditingController());
          _links.add(TextEditingController(text: link.toString()));
        }
      }

      final reminders = data['reminders'] as List<dynamic>? ?? [];
      for (var reminder in reminders) {
        final date = (reminder['date'] as Timestamp).toDate();
        _reminders.add({
          'date': DateTime(date.year, date.month, date.day),
          'time': TimeOfDay(hour: date.hour, minute: date.minute),
          'sent': reminder['sent'] ?? false,
        });
      }
    }
  }

  Future<void> _loadData() async {
    // Veriler artık RecipientSelectorField içindeki AliciSecimi bileşeni tarafından yönetiliyor.
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _searchController.dispose();
    for (var controller in _links) {
      controller.dispose();
    }
    for (var controller in _linkNames) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _publishDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _publishDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _publishTime,
    );
    if (picked != null) {
      setState(() {
        _publishTime = picked;
      });
    }
  }

  Future<void> _saveAnnouncement() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir alıcı ekleyin')),
      );
      return;
    }

    try {
      setState(() => _isSaving = true);

      final links = List.generate(_links.length, (i) {
        final url = _links[i].text.trim();
        final name = _linkNames.length > i ? _linkNames[i].text.trim() : '';
        if (url.isEmpty) return null;
        return {'name': name.isEmpty ? 'Bağlantı ${i + 1}' : name, 'url': url};
      }).where((l) => l != null).toList();

      final publishTimeStr =
          '${_publishTime.hour.toString().padLeft(2, '0')}:${_publishTime.minute.toString().padLeft(2, '0')}';

      final finalTitle = _title.text.trim();

      if (widget.announcementId != null) {
        final remindersList = _reminders.map((r) {
          final date = r['date'] as DateTime;
          final time = r['time'] as TimeOfDay;
          return {
            'date': Timestamp.fromDate(
              DateTime(date.year, date.month, date.day, time.hour, time.minute),
            ),
            'sent': r['sent'] ?? false,
          };
        }).toList();

        await _announcementService.updateAnnouncement(widget.announcementId!, {
          'title': finalTitle,
          'content': _content.text.trim(),
          'recipients': _selectedRecipients,
          'publishDate': Timestamp.fromDate(
            DateTime(
              _publishDate.year,
              _publishDate.month,
              _publishDate.day,
              _publishTime.hour,
              _publishTime.minute,
            ),
          ),
          'publishTime': publishTimeStr,
          'sendSms': _sendSms,
          'links': links,
          'isAnonymous': _isAnonymous,
          'schedulePublish': _schedulePublish,
          'status': _schedulePublish ? 'scheduled' : 'published',
          'reminders': remindersList,
          'isReminder': false,
          'recipientNames': _recipientNames,
        });
      } else {
        await _announcementService.saveAnnouncement(
          title: finalTitle,
          content: _content.text.trim(),
          recipients: _selectedRecipients,
          publishDate: DateTime(
            _publishDate.year,
            _publishDate.month,
            _publishDate.day,
            _publishTime.hour,
            _publishTime.minute,
          ),
          publishTime: publishTimeStr,
          sendSms: _sendSms,
          links: links,
          isAnonymous: _isAnonymous,
          schedulePublish: _schedulePublish,
          reminders: _reminders,
          schoolTypeId: widget.schoolTypeId,
          recipientNames: _recipientNames,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.announcementId != null
                ? 'Duyuru güncellendi'
                : 'Duyuru başarıyla kaydedildi',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.announcementId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Duyuru Düzenle' : 'Yeni Duyuru'),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _saveAnnouncement,
              icon: const Icon(Icons.send),
              label: const Text('Kaydet'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Alıcı Seçimi
                  RecipientSelectorField(
                    selectedRecipients: _selectedRecipients,
                    recipientNames: _recipientNames,
                    schoolTypeId: widget.schoolTypeId,
                    onChanged: (list, names) {
                      setState(() {
                        _selectedRecipients = list;
                        _recipientNames = names;
                      });
                    },
                  ),

                  const SizedBox(height: 24),

                  // Başlık Giriş Alanı
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.indigo,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Duyuru Başlığı',
                        labelStyle: TextStyle(
                          color: Colors.indigo.withOpacity(0.6),
                          fontWeight: FontWeight.normal,
                        ),
                        hintText: 'Örn: Veli Toplantısı Duyurusu',
                        prefixIcon: const Icon(
                          Icons.title_rounded,
                          color: Colors.indigo,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Lütfen başlık giriniz'
                          : null,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // İçerik Giriş Alanı
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _content,
                      maxLines: 8,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Duyuru İçeriği',
                        labelStyle: TextStyle(
                          color: Colors.indigo.withOpacity(0.6),
                        ),
                        hintText:
                            'Duyurunuzun detaylı açıklamasını buraya yazın...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.all(20),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Lütfen içerik giriniz'
                          : null,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Anonim Paylaşım
                  Card(
                    elevation: 0,
                    color: Colors.blue[50],
                    child: SwitchListTile(
                      value: _isAnonymous,
                      onChanged: (value) =>
                          setState(() => _isAnonymous = value),
                      title: Row(
                        children: [
                          Icon(
                            Icons.visibility_off,
                            color: Colors.blue[700],
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Anonim Paylaşım',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        _isAnonymous
                            ? 'Kurum adıyla paylaşılacak'
                            : 'Adınızla paylaşılacak',
                        style: const TextStyle(fontSize: 12),
                      ),
                      activeThumbColor: Colors.blue[700],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Yayın Zamanı Planla - Yeni Şık Tasarım
                  Card(
                    elevation: 0,
                    color: Colors.purple[50],
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _schedulePublish,
                          onChanged: (value) =>
                              setState(() => _schedulePublish = value),
                          title: Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                color: Colors.purple[700],
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Yayını Planla',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            _schedulePublish
                                ? 'Planlı yayınlanacak'
                                : 'Hemen yayınlanacak',
                            style: const TextStyle(fontSize: 12),
                          ),
                          activeThumbColor: Colors.purple[700],
                        ),
                        if (_schedulePublish) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isNarrow = constraints.maxWidth < 300;
                                if (isNarrow) {
                                  return Column(
                                    children: [
                                      _buildCompactDateTimeCard(
                                        icon: Icons.calendar_month,
                                        label: 'Tarih',
                                        value:
                                            '${_publishDate.day.toString().padLeft(2, '0')}/${_publishDate.month.toString().padLeft(2, '0')}/${_publishDate.year}',
                                        onTap: _pickDate,
                                        color: Colors.purple,
                                      ),
                                      const SizedBox(height: 8),
                                      _buildCompactDateTimeCard(
                                        icon: Icons.access_time_rounded,
                                        label: 'Saat',
                                        value: _publishTime.format(context),
                                        onTap: _pickTime,
                                        color: Colors.purple,
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(
                                      child: _buildCompactDateTimeCard(
                                        icon: Icons.calendar_month,
                                        label: 'Tarih',
                                        value:
                                            '${_publishDate.day.toString().padLeft(2, '0')}/${_publishDate.month.toString().padLeft(2, '0')}/${_publishDate.year}',
                                        onTap: _pickDate,
                                        color: Colors.purple,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildCompactDateTimeCard(
                                        icon: Icons.access_time_rounded,
                                        label: 'Saat',
                                        value: _publishTime.format(context),
                                        onTap: _pickTime,
                                        color: Colors.purple,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Hatırlatmalar
                  Card(
                    elevation: 0,
                    color: Colors.amber[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.notifications_active,
                                color: Colors.amber[700],
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Hatırlatmalar',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.amber[900],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime(DateTime.now().year + 2),
                                    initialDate: DateTime.now().add(
                                      const Duration(days: 1),
                                    ),
                                  );
                                  if (date == null || !mounted) return;

                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.now(),
                                  );
                                  if (time == null || !mounted) return;

                                  setState(() {
                                    _reminders.add({
                                      'date': date,
                                      'time': time,
                                    });
                                  });
                                },
                                icon: Icon(
                                  Icons.add_alarm,
                                  color: Colors.amber[700],
                                  size: 22,
                                ),
                                tooltip: 'Hatırlatma Ekle',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.amber[100],
                                ),
                              ),
                            ],
                          ),
                          if (_reminders.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ..._reminders.asMap().entries.map((entry) {
                              final index = entry.key;
                              final reminder = entry.value;
                              final date = reminder['date'] as DateTime;
                              final time = reminder['time'] as TimeOfDay;
                              return Card(
                                color: Colors.white,
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Icon(
                                    Icons.alarm,
                                    color: Colors.amber[700],
                                  ),
                                  title: Text(
                                    '${date.day}/${date.month}/${date.year} - ${time.format(context)}',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, size: 20),
                                    onPressed: () => setState(
                                      () => _reminders.removeAt(index),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // SMS
                  Card(
                    elevation: 0,
                    color: Colors.green[50],
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _sendSms,
                          onChanged: (value) =>
                              setState(() => _sendSms = value),
                          title: Row(
                            children: [
                              Icon(
                                Icons.sms,
                                color: Colors.green[700],
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'SMS Gönderimi',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          subtitle: _sendSms
                              ? const Text(
                                  'SMS gönderilecek',
                                  style: TextStyle(fontSize: 12),
                                )
                              : null,
                          activeThumbColor: Colors.green[700],
                        ),
                        if (_sendSms)
                          Container(
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.green[800],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Hedef kitlenin kayıtlı telefonlarına SMS gönderilecektir.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green[900],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Bağlantılar
                  Card(
                    elevation: 0,
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.attachment,
                                color: Colors.orange[700],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Ekler ve Bağlantılar',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[900],
                                ),
                              ),
                              const Spacer(),
                              IconButton.outlined(
                                onPressed: () => setState(() {
                                  _links.add(TextEditingController());
                                  _linkNames.add(TextEditingController());
                                }),
                                icon: const Icon(Icons.add_link, size: 20),
                                tooltip: 'Bağlantı Ekle',
                                color: Colors.orange[700],
                              ),
                            ],
                          ),
                          if (_links.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ..._links.asMap().entries.map(
                              (e) => Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      TextFormField(
                                        controller: _linkNames.length > e.key
                                            ? _linkNames[e.key]
                                            : null,
                                        decoration: const InputDecoration(
                                          labelText: 'Bağlantı Adı',
                                          hintText: 'Örn: Ders Programı',
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(
                                            Icons.label,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        controller: e.value,
                                        decoration: InputDecoration(
                                          labelText: 'URL',
                                          hintText: 'https://ornek.com',
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: const OutlineInputBorder(),
                                          prefixIcon: const Icon(
                                            Icons.link,
                                            size: 20,
                                          ),
                                          suffixIcon: IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                            onPressed: () => setState(() {
                                              _links.removeAt(e.key);
                                              if (_linkNames.length > e.key) {
                                                _linkNames[e.key].dispose();
                                                _linkNames.removeAt(e.key);
                                              }
                                            }),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Kaydet Butonu
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveAnnouncement,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      _isSaving ? 'Kaydediliyor...' : 'Kaydet ve Gönder',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactDateTimeCard({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    required MaterialColor color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color[600], size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
