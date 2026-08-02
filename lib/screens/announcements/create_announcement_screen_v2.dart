import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/announcement_service.dart';
import '../../services/user_permission_service.dart';
import '../../widgets/recipient_selector_field.dart';
import 'package:edukn/widgets/custom_date_range_picker.dart';
import 'package:edukn/widgets/custom_time_picker.dart';

class CreateAnnouncementScreenV2 extends StatefulWidget {
  final String? announcementId;
  final Map<String, dynamic>? announcementData;
  final String? schoolTypeId;
  final String? schoolTypeName;
  final String? institutionId;

  const CreateAnnouncementScreenV2({
    Key? key,
    this.announcementId,
    this.announcementData,
    this.schoolTypeId,
    this.schoolTypeName,
    this.institutionId,
  }) : super(key: key);

  @override
  State<CreateAnnouncementScreenV2> createState() =>
      _CreateAnnouncementScreenV2State();
}

class _CreateAnnouncementScreenV2State extends State<CreateAnnouncementScreenV2>
    with TickerProviderStateMixin {
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

  late AnimationController _saveAnimController;
  late Animation<double> _saveScaleAnim;

  // Premium color palette
  static const _primaryBlue = Color(0xFF1565C0);
  static const _accentCyan = Color(0xFF00ACC1);
  static const _surfaceColor = Color(0xFFF8F9FD);

  @override
  void initState() {
    super.initState();
    _saveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _saveScaleAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _saveAnimController, curve: Curves.easeInOut),
    );
    _loadData();
    _loadExistingData();
  }

  void _loadExistingData() {
    if (widget.announcementData != null) {
      final data = widget.announcementData!;
      _title.text = data['title'] ?? '';
      _content.text = data['content'] ?? '';
      _selectedRecipients = List<String>.from(data['recipients'] ?? []);
      _recipientNames =
          Map<String, String>.from(data['recipientNames'] ?? {});
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

  Future<void> _loadData() async {}

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _searchController.dispose();
    _saveAnimController.dispose();
    for (var controller in _links) {
      controller.dispose();
    }
    for (var controller in _linkNames) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(BuildContext btnContext) async {
    final now = DateTime.now();
    final picked = await CustomDateRangePicker.showSingle(context,
        sourceContext: btnContext, initialDate: _publishDate.isBefore(now) ? now : _publishDate);
    if (picked != null && !picked.isBefore(DateTime(now.year, now.month, now.day))) {
      setState(() => _publishDate = picked);
    }
  }

  Future<void> _pickTime(BuildContext btnContext) async {
    final picked = await CustomTimePicker.show(
      context,
      initialTime: _publishTime,
      sourceContext: btnContext,
    );
    if (picked != null) {
      setState(() => _publishTime = picked);
    }
  }

  Future<void> _saveAnnouncement() async {
    if (_formKey.currentState?.validate() != true) return;
    if (_selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Lütfen en az bir alıcı ekleyin'),
            ],
          ),
          backgroundColor: Colors.orange[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
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
              DateTime(
                  date.year, date.month, date.day, time.hour, time.minute),
            ),
            'sent': r['sent'] ?? false,
          };
        }).toList();

        await _announcementService
            .updateAnnouncement(widget.announcementId!, {
          'title': finalTitle,
          'content': _content.text.trim(),
          'recipients': _selectedRecipients,
          'publishDate': Timestamp.fromDate(
            DateTime(_publishDate.year, _publishDate.month, _publishDate.day,
                _publishTime.hour, _publishTime.minute),
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
          publishDate: DateTime(_publishDate.year, _publishDate.month,
              _publishDate.day, _publishTime.hour, _publishTime.minute),
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
      final userRoleData = await UserPermissionService.loadUserData();
      final userRole = (userRoleData?['role'] ?? '').toString().toLowerCase();
      final isTeacher = userRole.contains('ogretmen') || userRole.contains('öğretmen') || userRole.contains('teacher');
      final isManager = userRole == 'admin' || userRole == 'manager' || userRole == 'genel_mudur' || userRole == 'mudur' || userRole == 'mudur_yardimcisi';

      String msg = widget.announcementId != null ? 'Duyuru güncellendi' : 'Duyuru başarıyla yayınlandı';
      if (isTeacher && !isManager && widget.announcementId == null) {
        final schoolId = await _announcementService.getSchoolId();
        if (schoolId != null) {
          final mode = await _announcementService.getTeacherAnnouncementMode(schoolId);
          if (mode == 'approval_required') {
            msg = 'Duyuru oluşturuldu ve yönetim onayına sunuldu.';
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(msg)),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    return Scaffold(
      backgroundColor: _surfaceColor,
      appBar: AppBar(
        title: Text(isEditing ? 'Duyuru Düzenle' : 'Yeni Duyuru'),
      ),
      floatingActionButton: isWide
          ? ScaleTransition(
              scale: _saveScaleAnim,
              child: FloatingActionButton.extended(
                onPressed: _isSaving ? null : () {
                  _saveAnimController.forward().then((_) => _saveAnimController.reverse());
                  _saveAnnouncement();
                },
                backgroundColor: _primaryBlue,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(
                  _isSaving ? 'Kaydediliyor...' : 'Kaydet ve Gönder',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            )
          : null,
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 860),
              child: isWide
                  ? _buildWideLayout()
                  : _buildNarrowLayout(),
            ),
          ),
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  LAYOUTS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildWideLayout() {
    return Column(
      children: [
        // Row 1: Recipients full width
        _buildRecipientSection(),
        const SizedBox(height: 20),
        // Row 2: Title + Content side by side? No, better stacked for readability
        _buildTitleField(),
        const SizedBox(height: 16),
        _buildContentField(),
        const SizedBox(height: 20),
        // Row 3: Toggles in a row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildAnonymousToggle()),
            const SizedBox(width: 12),
            Expanded(child: _buildScheduleToggle()),
            const SizedBox(width: 12),
            Expanded(child: _buildSmsToggle()),
          ],
        ),
        const SizedBox(height: 20),
        // Row 4: Reminders + Links side by side
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildRemindersSection()),
            const SizedBox(width: 12),
            Expanded(child: _buildLinksSection()),
          ],
        ),
        const SizedBox(height: 80), // FAB space
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildRecipientSection(),
        const SizedBox(height: 16),
        _buildTitleField(),
        const SizedBox(height: 12),
        _buildContentField(),
        const SizedBox(height: 16),
        _buildAnonymousToggle(),
        const SizedBox(height: 10),
        _buildScheduleToggle(),
        const SizedBox(height: 10),
        _buildSmsToggle(),
        const SizedBox(height: 16),
        _buildRemindersSection(),
        const SizedBox(height: 12),
        _buildLinksSection(),
        const SizedBox(height: 24),
        _buildSaveButton(),
      ],
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  SECTION: RECIPIENTS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildRecipientSection() {
    return RecipientSelectorField(
      selectedRecipients: _selectedRecipients,
      recipientNames: _recipientNames,
      schoolTypeId: widget.schoolTypeId,
      onChanged: (list, names) {
        setState(() {
          _selectedRecipients = list;
          _recipientNames = names;
        });
      },
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  SECTION: TITLE FIELD
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildTitleField() {
    return _PremiumCard(
      accentColor: _primaryBlue,
      child: TextFormField(
        controller: _title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: Color(0xFF1A237E),
        ),
        decoration: InputDecoration(
          labelText: 'Duyuru Başlığı',
          labelStyle: TextStyle(
            color: _primaryBlue.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          hintText: 'Örn: Veli Toplantısı Duyurusu',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: Container(
            margin: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(Icons.edit_note_rounded, color: _primaryBlue, size: 22),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Lütfen başlık giriniz' : null,
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  SECTION: CONTENT FIELD
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildContentField() {
    return _PremiumCard(
      accentColor: _accentCyan,
      child: Column(
        children: [
          TextFormField(
            controller: _content,
            maxLines: 6,
            style: const TextStyle(fontSize: 15, height: 1.5),
            decoration: InputDecoration(
              labelText: 'Duyuru İçeriği',
              labelStyle: TextStyle(
                color: _accentCyan.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              hintText: 'Duyurunuzun detaylı açıklamasını buraya yazın...',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              alignLabelWithHint: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Lütfen içerik giriniz' : null,
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  SECTION: TOGGLES
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildAnonymousToggle() {
    return _ToggleCard(
      icon: Icons.visibility_off_rounded,
      title: 'Anonim Paylaşım',
      subtitle: _isAnonymous ? 'Kurum adıyla paylaşılacak' : 'Adınızla paylaşılacak',
      value: _isAnonymous,
      activeColor: _primaryBlue,
      onChanged: (v) => setState(() => _isAnonymous = v),
    );
  }

  Widget _buildScheduleToggle() {
    return Column(
      children: [
        _ToggleCard(
          icon: Icons.schedule_rounded,
          title: 'Yayını Planla',
          subtitle:
              _schedulePublish ? 'Planlı yayınlanacak' : 'Hemen yayınlanacak',
          value: _schedulePublish,
          activeColor: const Color(0xFF5E35B1),
          onChanged: (v) => setState(() => _schedulePublish = v),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildDateTimeRow(),
          ),
          crossFadeState: _schedulePublish
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }

  Widget _buildSmsToggle() {
    return Column(
      children: [
        _ToggleCard(
          icon: Icons.sms_rounded,
          title: 'SMS Gönderimi',
          subtitle: _sendSms ? 'SMS gönderilecek' : null,
          value: _sendSms,
          activeColor: const Color(0xFF2E7D32),
          onChanged: (v) => setState(() => _sendSms = v),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hedef kitlenin kayıtlı telefonlarına SMS gönderilecektir.',
                    style: TextStyle(fontSize: 12, color: Colors.green[800]),
                  ),
                ),
              ],
            ),
          ),
          crossFadeState:
              _sendSms ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  DATE/TIME ROW
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildDateTimeRow() {
    return Row(
      children: [
        Expanded(child: _buildDateTimePill(
          icon: Icons.calendar_month_rounded,
          label: 'Tarih',
          value: '${_publishDate.day.toString().padLeft(2, '0')}.${_publishDate.month.toString().padLeft(2, '0')}.${_publishDate.year}',
          color: const Color(0xFF5E35B1),
          onTap: _pickDate,
        )),
        const SizedBox(width: 8),
        Expanded(child: _buildDateTimePill(
          icon: Icons.access_time_rounded,
          label: 'Saat',
          value: _publishTime.format(context),
          color: const Color(0xFF5E35B1),
          onTap: _pickTime,
        )),
      ],
    );
  }

  Widget _buildDateTimePill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Future<void> Function(BuildContext) onTap,
  }) {
    return Builder(
      builder: (btnContext) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(btnContext),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 10, color: color.withValues(alpha: 0.6))),
                      Text(value,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: color),
                          overflow: TextOverflow.ellipsis),
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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  SECTION: REMINDERS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildRemindersSection() {
    return _PremiumCard(
      accentColor: const Color(0xFFF9A825),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.notifications_active_rounded,
                      color: Color(0xFFF9A825), size: 18),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Hatırlatmalar',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF5D4037),
                  ),
                ),
                if (_reminders.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9A825),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_reminders.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                const Spacer(),
                Builder(
                  builder: (btnContext) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        // Hatırlatma tarihi yayın tarihinden önce olamaz
                        final minDate = _publishDate.isBefore(DateTime.now())
                            ? DateTime.now()
                            : _publishDate;
                        final date = await CustomDateRangePicker.showSingle(
                          context,
                          sourceContext: btnContext,
                          initialDate: minDate,
                        );
                        if (date == null || !mounted) return;
                        // Geçmiş tarih kontrolü
                        if (date.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))) return;
                        // Yayın tarihinden önce olamaz
                        if (date.isBefore(DateTime(_publishDate.year, _publishDate.month, _publishDate.day))) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Hatırlatma yayın tarihinden önce olamaz'),
                                backgroundColor: Colors.orange[700],
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                          return;
                        }
                        // Saat seçimi — aynı gün ise minimum saat kısıtla
                        TimeOfDay? minTime;
                        final isSameDay = date.year == _publishDate.year &&
                            date.month == _publishDate.month &&
                            date.day == _publishDate.day;
                        if (isSameDay) {
                          minTime = _publishTime;
                        }
                        final time = await CustomTimePicker.show(
                          context,
                          initialTime: minTime ?? TimeOfDay.now(),
                          sourceContext: btnContext,
                          minTime: minTime,
                        );
                        if (time == null || !mounted) return;
                        setState(() {
                          _reminders.add({'date': date, 'time': time});
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_alarm_rounded,
                                size: 16, color: Color(0xFFF9A825)),
                            SizedBox(width: 4),
                            Text(
                              'Ekle',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFF9A825)),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDE7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFECB3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9A825),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.alarm_rounded,
                          size: 16, color: Colors.amber[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}  •  ${time.format(context)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      InkWell(
                        onTap: () =>
                            setState(() => _reminders.removeAt(index)),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: Colors.red[300]),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  SECTION: LINKS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildLinksSection() {
    return _PremiumCard(
      accentColor: const Color(0xFFEF6C00),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.link_rounded,
                      color: Color(0xFFEF6C00), size: 18),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ekler ve Bağlantılar',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF4E342E),
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() {
                      _links.add(TextEditingController());
                      _linkNames.add(TextEditingController());
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFCC80)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_link_rounded,
                              size: 16, color: Color(0xFFEF6C00)),
                          SizedBox(width: 4),
                          Text(
                            'Ekle',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFEF6C00)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_links.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._links.asMap().entries.map((e) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8F0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFE0B2)),
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller:
                            _linkNames.length > e.key ? _linkNames[e.key] : null,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Bağlantı Adı',
                          hintText: 'Örn: Ders Programı',
                          labelStyle: const TextStyle(fontSize: 12),
                          hintStyle: TextStyle(
                              color: Colors.grey[400], fontSize: 12),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: Colors.grey[200]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: Colors.grey[200]!),
                          ),
                          prefixIcon: const Icon(Icons.label_outline_rounded,
                              size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: e.value,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'URL',
                          hintText: 'https://ornek.com',
                          labelStyle: const TextStyle(fontSize: 12),
                          hintStyle: TextStyle(
                              color: Colors.grey[400], fontSize: 12),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: Colors.grey[200]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: Colors.grey[200]!),
                          ),
                          prefixIcon:
                              const Icon(Icons.link_rounded, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          suffixIcon: InkWell(
                            onTap: () => setState(() {
                              _links[e.key].dispose();
                              _links.removeAt(e.key);
                              if (_linkNames.length > e.key) {
                                _linkNames[e.key].dispose();
                                _linkNames.removeAt(e.key);
                              }
                            }),
                            borderRadius: BorderRadius.circular(6),
                            child: Icon(Icons.delete_outline_rounded,
                                color: Colors.red[300], size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  SAVE BUTTON
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildSaveButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSaving ? null : _saveAnnouncement,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isSaving
                  ? [Colors.grey[400]!, Colors.grey[500]!]
                  : [const Color(0xFF1565C0), const Color(0xFF0D47A1)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: _isSaving
                ? []
                : [
                    BoxShadow(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSaving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              else
                const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                _isSaving ? 'Kaydediliyor...' : 'Kaydet ve Gönder',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  REUSABLE WIDGETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Premium card with colored left accent bar
class _PremiumCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;

  const _PremiumCard({required this.child, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accentColor, width: 3),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Toggle card with icon, title, subtitle and switch
class _ToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: value ? activeColor.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? activeColor.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.12),
          width: value ? 1.5 : 1,
        ),
        boxShadow: [
          if (value)
            BoxShadow(
              color: activeColor.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: value
                        ? activeColor.withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      size: 18,
                      color: value ? activeColor : Colors.grey[500]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: value ? activeColor : Colors.grey[700],
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: activeColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
