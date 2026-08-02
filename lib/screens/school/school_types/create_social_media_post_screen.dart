import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;
import '../../../widgets/recipient_selector_field.dart';

class CreateSocialMediaPostScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const CreateSocialMediaPostScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<CreateSocialMediaPostScreen> createState() =>
      _CreateSocialMediaPostScreenState();
}

class _CreateSocialMediaPostScreenState
    extends State<CreateSocialMediaPostScreen> {
  final _captionController = TextEditingController();
  final _videoUrlController = TextEditingController();

  bool _isUploading = false;
  List<PlatformFile> _selectedFiles = [];

  // Recipient Logic
  List<String> _selectedRecipients = [];
  Map<String, String> _recipientNames = {};
  String _mediaType = 'image'; // 'image' or 'video'

  @override
  void dispose() {
    _captionController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFiles.addAll(result.files);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _sharePost() async {
    final videoUrl = _videoUrlController.text.trim();
    final captionText = _captionController.text.trim();

    if (_selectedFiles.isEmpty && videoUrl.isEmpty && captionText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen paylaşım içeriği yazın veya bir medya ekleyin'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isUploading) return;
    setState(() => _isUploading = true);

    final ValueNotifier<String> statusNotifier = ValueNotifier(
      "Hazırlanıyor...",
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ValueListenableBuilder<String>(
              valueListenable: statusNotifier,
              builder: (context, value, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      value,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo.shade900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Oturum açılmamış');

      statusNotifier.value = "Kullanıcı bilgileri alınıyor...";

      String creatorName = (user.email ?? 'unknown').split('@')[0];
      String? creatorPhotoUrl;

      try {
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 5));

        if (userQuery.docs.isNotEmpty) {
          final userData = userQuery.docs.first.data();
          creatorName = userData['fullName'] ?? userData['name'] ?? creatorName;
          creatorPhotoUrl = userData['photoUrl'];
        }
      } catch (e) {
        debugPrint("Kullanıcı detay hatası: $e");
      }

      // Upload / Process images
      List<String> mediaItems = [];
      int currentIndex = 0;
      int total = _selectedFiles.length;

      for (var file in _selectedFiles) {
        currentIndex++;
        final Uint8List dataToUpload = file.bytes!;

        try {
          statusNotifier.value = "$currentIndex / $total Görsel İşleniyor...";

          final img.Image? originalImage = img.decodeImage(dataToUpload);
          String? base64Image;

          if (originalImage != null) {
            img.Image resizedImage = originalImage;
            if (originalImage.width > 800) {
              resizedImage = img.copyResize(originalImage, width: 800);
            }
            final compressedBytes = img.encodeJpg(resizedImage, quality: 60);
            base64Image = base64Encode(compressedBytes);
          } else {
            base64Image = base64Encode(dataToUpload);
          }

          if (base64Image != null) {
            mediaItems.add(base64Image);
          }
        } catch (e) {
          debugPrint("Resim işleme hatası: $e");
        }
      }

      if (mediaItems.isEmpty && videoUrl.isEmpty && captionText.isEmpty) {
        throw Exception("İçerik metni, görseller veya video linki girilmelidir.");
      }

      statusNotifier.value = "Veritabanına Kaydedildiği...";

      final currentUserEmail = user.email ?? '';

      await FirebaseFirestore.instance
          .collection('social_media_posts')
          .add({
            'schoolTypeId': widget.schoolTypeId,
            'institutionId': widget.institutionId,
            'imageUrl': '',
            'imageBase64': mediaItems.isNotEmpty ? mediaItems.first : '',
            'mediaItems': mediaItems,
            'videoUrl': videoUrl,
            'caption': captionText,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': currentUserEmail,
            'creatorName': creatorName,
            'creatorPhotoUrl': creatorPhotoUrl,
            'likes': [],
            'likeCount': 0,
            'commentCount': 0,
            'recipients': _selectedRecipients,
            'recipientNames': _recipientNames,
            'isPublic': _selectedRecipients.isEmpty,
            'isPinned': false,
            'readBy': [currentUserEmail], // Paylaşımı yapan otomatik okudu sayılır
          })
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () =>
                throw Exception('Veritabanı kaydı zaman aşımına uğradı.'),
          );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        Navigator.pop(context); // Close create screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  'Paylaşım başarıyla yayınlandı!',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Paylaşım Hatası: $e");
      if (mounted) {
        Navigator.pop(context); // Close dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Hata"),
            content: Text("Paylaşım sırasında bir hata oluştu:\n$e"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Tamam"),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Yeni Paylaşım Oluştur',
          style: GoogleFonts.inter(
            color: Colors.indigo.shade900,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.blueGrey),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _sharePost,
                icon: _isUploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                label: Text(
                  "Paylaş",
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  elevation: 2,
                  shadowColor: Colors.indigo.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ==================== 1. HEDEF KİTLE SEÇİMİ (EN ÜSTTE) ====================
                _buildCardSection(
                  stepNumber: '1',
                  title: 'Hedef Kitle (Alıcı Seçimi)',
                  subtitle:
                      'Paylaşımın gösterileceği okul türü, sınıf veya kullanıcı gruplarını belirleyin.',
                  icon: Icons.groups_rounded,
                  iconColor: Colors.indigo,
                  child: RecipientSelectorField(
                    selectedRecipients: _selectedRecipients,
                    recipientNames: _recipientNames,
                    schoolTypeId: widget.schoolTypeId.isNotEmpty ? widget.schoolTypeId : null,
                    institutionId: widget.institutionId,
                    onChanged: (list, names) {
                      setState(() {
                        _selectedRecipients = list;
                        _recipientNames = names;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // ==================== 2. İÇERİK METNİ ====================
                _buildCardSection(
                  stepNumber: '2',
                  title: 'İçerik Metni',
                  subtitle:
                      'Sosyal medya paylaşımınız için metin içeriğini giriniz.',
                  icon: Icons.article_rounded,
                  iconColor: Colors.blue.shade600,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      controller: _captionController,
                      maxLines: 5,
                      minLines: 3,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.grey.shade900,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Paylaşım içeriğini ve detayları buraya giriniz...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 15,
                          color: Colors.blueGrey.shade400,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ==================== 3. MEDYA EKLENTİSİ ====================
                _buildCardSection(
                  stepNumber: '3',
                  title: 'Medya Ekle',
                  subtitle:
                      'Paylaşımınıza fotoğraf galerisi veya YouTube video bağlantısı ekleyin.',
                  icon: Icons.perm_media_rounded,
                  iconColor: Colors.purple.shade600,
                  child: Column(
                    children: [
                      // Toggle Segmented Control
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildMediaTabButton(
                                label: 'Görsel Galeri',
                                icon: Icons.photo_library_rounded,
                                isSelected: _mediaType == 'image',
                                onTap: () {
                                  setState(() {
                                    _mediaType = 'image';
                                    _videoUrlController.clear();
                                  });
                                },
                              ),
                            ),
                            Expanded(
                              child: _buildMediaTabButton(
                                label: 'Video Linki',
                                icon: Icons.video_collection_rounded,
                                isSelected: _mediaType == 'video',
                                onTap: () {
                                  setState(() {
                                    _mediaType = 'video';
                                    _selectedFiles.clear();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (_mediaType == 'video')
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.purple.shade100),
                          ),
                          child: TextField(
                            controller: _videoUrlController,
                            style: GoogleFonts.inter(fontSize: 14),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                Icons.link_rounded,
                                color: Colors.purple,
                              ),
                              labelText: "Video Bağlantısı (YouTube / Drive)",
                              labelStyle: GoogleFonts.inter(
                                color: Colors.purple.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                              hintText: "https://www.youtube.com/watch?v=...",
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.purple.shade200),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.purple.shade200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.purple, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),

                      if (_mediaType == 'image')
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Seçilen Görseller (${_selectedFiles.length})",
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                    fontSize: 14,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _pickImages,
                                  icon: const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    "Görsel Ekle",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (_selectedFiles.isEmpty)
                              InkWell(
                                onTap: _pickImages,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  height: 140,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.indigo.shade100,
                                      style: BorderStyle.solid,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade100,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.add_a_photo_rounded,
                                          size: 28,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        "Fotoğraf veya Görsel Yükleyin",
                                        style: GoogleFonts.inter(
                                          color: Colors.indigo.shade900,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Birden fazla dosya seçebilirsiniz",
                                        style: GoogleFonts.inter(
                                          color: Colors.blueGrey.shade400,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                height: 160,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: _selectedFiles.length,
                                  separatorBuilder: (c, i) =>
                                      const SizedBox(width: 12),
                                  itemBuilder: (context, index) {
                                    final file = _selectedFiles[index];
                                    if (file.bytes == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: Image.memory(
                                            file.bytes!,
                                            height: 160,
                                            width: 160,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                _selectedFiles.removeAt(index);
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.65),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close_rounded,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardSection({
    required String stepNumber,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.blueGrey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildMediaTabButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.indigo : Colors.blueGrey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.indigo : Colors.blueGrey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
