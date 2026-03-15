import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'alici_secimi.dart';

class RecipientSelectorField extends StatefulWidget {
  final List<String> selectedRecipients;
  final Map<String, String> recipientNames;
  final String? schoolTypeId;
  final Function(List<String>, Map<String, String>) onChanged;
  final String title;
  final String hint;

  const RecipientSelectorField({
    Key? key,
    required this.selectedRecipients,
    required this.recipientNames,
    this.schoolTypeId,
    required this.onChanged,
    this.title = 'Hedef Kitle',
    this.hint = 'Öğrenci, şube veya sınıf seçin',
  }) : super(key: key);

  @override
  State<RecipientSelectorField> createState() => _RecipientSelectorFieldState();
}

class _RecipientSelectorFieldState extends State<RecipientSelectorField> {
  void _openRecipientDialog() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => AliciSecimi(
            selectedRecipients: widget.selectedRecipients,
            initialRecipientNames: widget.recipientNames,
            savedGroups: [],
            schoolTypeId: widget.schoolTypeId,
            isPage: true,
            onConfirmed: (list, names) {
              widget.onChanged(list, names);
            },
            onSaveGroup: (name) {},
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AliciSecimi(
          selectedRecipients: widget.selectedRecipients,
          initialRecipientNames: widget.recipientNames,
          savedGroups: [],
          schoolTypeId: widget.schoolTypeId,
          onConfirmed: (list, names) {
            widget.onChanged(list, names);
          },
          onSaveGroup: (name) {},
        ),
      );
    }
  }

  String _formatRecipientId(String id) {
    if (id.startsWith('user:')) {
      return 'Kullanıcı';
    } else if (id.startsWith('class:')) {
      final parts = id.split(':');
      if (parts.length >= 3) return parts[2];
      return 'Sınıf';
    } else if (id.startsWith('branch:')) {
      final parts = id.split(':');
      if (parts.length >= 3) return parts[2];
      return 'Şube';
    } else if (id.startsWith('school:')) {
      return 'Okul Geneli';
    } else if (id.startsWith('unit:')) {
      return 'Birim';
    }
    return id.length > 15 ? id.substring(0, 15) + '...' : id;
  }

  Widget _buildRecipientChip(String recipientId, String displayName) {
    Color chipColor;
    Color textColor;
    IconData? icon;

    if (recipientId.startsWith('user:')) {
      chipColor = Colors.blue.shade50;
      textColor = Colors.blue.shade700;
      icon = Icons.person;
    } else if (recipientId.startsWith('branch:')) {
      chipColor = Colors.green.shade50;
      textColor = Colors.green.shade700;
      icon = Icons.class_;
    } else if (recipientId.startsWith('class:')) {
      chipColor = Colors.orange.shade50;
      textColor = Colors.orange.shade700;
      icon = Icons.school;
    } else if (recipientId.startsWith('school:')) {
      chipColor = Colors.purple.shade50;
      textColor = Colors.purple.shade700;
      icon = Icons.account_balance;
    } else {
      chipColor = Colors.grey.shade100;
      textColor = Colors.grey.shade700;
      icon = Icons.group;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: textColor),
      label: Text(
        displayName.length > 20
            ? displayName.substring(0, 20) + '...'
            : displayName,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      backgroundColor: chipColor,
      side: BorderSide(color: textColor.withOpacity(0.3)),
      deleteIcon: Icon(Icons.close, size: 16, color: textColor),
      onDeleted: () {
        final newList = List<String>.from(widget.selectedRecipients);
        newList.remove(recipientId);
        final newNames = Map<String, String>.from(widget.recipientNames);
        newNames.remove(recipientId);
        widget.onChanged(newList, newNames);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.selectedRecipients.isEmpty
                  ? [Colors.grey.shade50, Colors.grey.shade100]
                  : [Colors.indigo.shade50, Colors.purple.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selectedRecipients.isEmpty
                  ? Colors.grey.shade300
                  : Colors.indigo.shade200,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openRecipientDialog,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.selectedRecipients.isEmpty
                            ? Colors.grey.shade200
                            : Colors.indigo.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.people_alt_rounded,
                        color: widget.selectedRecipients.isEmpty
                            ? Colors.grey.shade600
                            : Colors.indigo.shade700,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.selectedRecipients.isEmpty
                                ? 'Alıcıları Seçiniz'
                                : '${widget.selectedRecipients.length} Alıcı/Grup Seçildi',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: widget.selectedRecipients.isEmpty
                                  ? Colors.grey.shade600
                                  : Colors.indigo.shade800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            widget.selectedRecipients.isEmpty
                                ? widget.hint
                                : 'Düzenlemek için tıklayın',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.selectedRecipients.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: widget.selectedRecipients.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final recipientId = widget.selectedRecipients[index];
                  final displayName =
                      widget.recipientNames[recipientId] ??
                      _formatRecipientId(recipientId);
                  return _buildRecipientChip(recipientId, displayName);
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
