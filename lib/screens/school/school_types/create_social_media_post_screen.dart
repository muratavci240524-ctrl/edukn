import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
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
    if (_selectedFiles.isEmpty && videoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen en az bir görsel seçin veya video linki girin'),
        ),
      );
      return;
    }

    if (_isUploading) return;

    setState(() => _isUploading = true);

    // Progress State
    // Dialog state'ini güncellemek için StatefulBuilder veya ValueNotifier kullanılabilir
    // Basit olması adına _statusNotifier kullanacağız
    final ValueNotifier<String> statusNotifier = ValueNotifier(
      "Hazırlanıyor...",
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (context, value, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(value, textAlign: TextAlign.center),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Oturum açılmamış');

      // User Details
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
        print("Kullanıcı detay hatası (önemsiz): $e");
      }

      // 2. Upload Logic: Aggregate images
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
            // 800px genişlik limiti
            if (originalImage.width > 800) {
              resizedImage = img.copyResize(originalImage, width: 800);
            }
            // %60 Kalite JPEG
            final compressedBytes = img.encodeJpg(resizedImage, quality: 60);
            base64Image = base64Encode(compressedBytes);
          } else {
            base64Image = base64Encode(dataToUpload);
          }

          if (base64Image != null) {
            mediaItems.add(base64Image);
          }
        } catch (e) {
          print("Resim işleme hatası: $e");
        }
      }

      if (mediaItems.isEmpty && videoUrl.isEmpty) {
        throw Exception("Görseller işlenemedi ve video linki bulunamadı.");
      }

      statusNotifier.value = "Veritabanına Kaydediliyor...";

      // 3. Save as Single Document
      await FirebaseFirestore.instance
          .collection('social_media_posts')
          .add({
            'schoolTypeId': widget.schoolTypeId,
            'institutionId': widget.institutionId,
            'imageUrl': '',
            'imageBase64': mediaItems.isNotEmpty ? mediaItems.first : '',
            // Support for multiple images
            'mediaItems': mediaItems,
            'videoUrl': videoUrl,
            'caption': _captionController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': user.email,
            'creatorName': creatorName,
            'creatorPhotoUrl': creatorPhotoUrl,
            'likes': [],
            'likeCount': 0,
            'commentCount': 0,
            'recipients': _selectedRecipients,
            'isPublic': _selectedRecipients.isEmpty,
            'isPinned': false,
          })
          .timeout(
            const Duration(
              seconds: 45,
            ), // Increased timeout slightly for larger doc
            onTimeout: () =>
                throw Exception('Veritabanı kaydı zaman aşımına uğradı.'),
          );

      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pop(context); // Close screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paylaşım başarılı!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("Paylaşım Hatası: $e");
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
      backgroundColor: Colors.grey[50], // Modern light bg
      appBar: AppBar(
        title: const Text(
          'Yeni Paylaşım',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: ElevatedButton(
                onPressed: _isUploading ? null : _sharePost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  elevation: 0,
                ),
                child: const Text("Paylaş"),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            child: Column(
              children: [
                // --- Caption Input Section ---
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.indigo.shade100,
                            child: Icon(Icons.person, color: Colors.indigo),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _captionController,
                              maxLines: null,
                              decoration: const InputDecoration(
                                hintText: 'Ne hakkında konuşmak istersin?',
                                border: InputBorder.none,
                                hintStyle: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // --- Media Type Toggle ---
                Center(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'image',
                        label: Text('Görsel'),
                        icon: Icon(Icons.image),
                      ),
                      ButtonSegment(
                        value: 'video',
                        label: Text('Video Linki'),
                        icon: Icon(Icons.video_library),
                      ),
                    ],
                    selected: {_mediaType},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() {
                        _mediaType = newSelection.first;
                        if (_mediaType == 'image') _videoUrlController.clear();
                        if (_mediaType == 'video') _selectedFiles.clear();
                      });
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                          if (states.contains(MaterialState.selected)) {
                            return Colors.indigo.shade100;
                          }
                          return Colors.white;
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                if (_mediaType == 'video')
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: TextField(
                      controller: _videoUrlController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.link, color: Colors.indigo),
                        labelText: "Video Bağlantısı (YouTube)",
                        hintText: "https://www.youtube.com/watch?v=...",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                if (_mediaType == 'image')
                  // --- Media Section ---
                  Container(
                    color: Colors.white,
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Medya (${_selectedFiles.length})",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _pickImages,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: const Text("Ekle"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_selectedFiles.isEmpty)
                          InkWell(
                            onTap: _pickImages,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 150,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey[300]!,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo,
                                    size: 40,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Fotoğraf Seç",
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 180,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedFiles.length,
                              separatorBuilder: (c, i) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final file = _selectedFiles[index];
                                if (file.bytes == null)
                                  return const SizedBox.shrink();
                                return Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        file.bytes!,
                                        height: 180,
                                        width: 180,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: InkWell(
                                        onTap: () {
                                          setState(
                                            () =>
                                                _selectedFiles.removeAt(index),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
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
                  ),

                const SizedBox(height: 12),

                // --- Recipient Selector Section ---
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: RecipientSelectorField(
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
                ),

                // Bottom Padding
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
