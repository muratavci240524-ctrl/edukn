import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'create_social_media_post_screen.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../../../services/announcement_service.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui;

class SchoolTypeSocialMediaScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const SchoolTypeSocialMediaScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<SchoolTypeSocialMediaScreen> createState() =>
      _SchoolTypeSocialMediaScreenState();
}

class _SchoolTypeSocialMediaScreenState
    extends State<SchoolTypeSocialMediaScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- Actions ---


  void _openCreatePost() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateSocialMediaPostScreen(
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          institutionId: widget.institutionId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.indigo,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.schoolTypeName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Sosyal Medya',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: _openCreatePost,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  tooltip: 'Yeni Medya Ekle',
                ),
              ],
            ),
          ],
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('social_media_posts')
                .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Hata: ${snapshot.error}'));
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('Henüz gönderi yok'));
              }

              List<QueryDocumentSnapshot> posts = List.from(snapshot.data!.docs);

              posts.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final isPinnedA = dataA['isPinned'] ?? false;
                final isPinnedB = dataB['isPinned'] ?? false;

                if (isPinnedA != isPinnedB) {
                  return isPinnedA ? -1 : 1;
                }
                final timeA = dataA['createdAt'] as Timestamp?;
                final timeB = dataB['createdAt'] as Timestamp?;
                if (timeA != null && timeB != null) {
                  return timeB.compareTo(timeA);
                }
                return 0;
              });


              return Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      int crossAxisCount = constraints.maxWidth > 700 ? 2 : 1;

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: posts.length,
                        itemBuilder: (context, index) {
                          final post = posts[index];
                          final data = post.data() as Map<String, dynamic>;
                          return PostCard(
                            postId: post.id,
                            data: data,
                            currentUserId: _auth.currentUser?.uid,
                            currentUserEmail: _auth.currentUser?.email,
                            schoolTypeId: widget.schoolTypeId,
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: MediaQuery.of(context).size.width > 700
          ? FloatingActionButton.extended(
              onPressed: _openCreatePost,
              label: const Text(
                'Yeni Medya Ekle',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              icon: const Icon(Icons.add_photo_alternate, color: Colors.white),
              backgroundColor: Colors.indigo,
            )
          : null,
    );
  }

}

class PostCard extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> data;
  final String? currentUserId;
  final String? currentUserEmail;
  final String schoolTypeId;

  const PostCard({
    Key? key,
    required this.postId,
    required this.data,
    this.currentUserId,
    this.currentUserEmail,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;
  bool _isPlaying = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _toggleLike(List<dynamic> likes) async {
    if (widget.currentUserId == null) return;
    final userIdentifier = widget.currentUserEmail ?? widget.currentUserId;
    final docRef = FirebaseFirestore.instance
        .collection('social_media_posts')
        .doc(widget.postId);

    if (likes.contains(userIdentifier)) {
      await docRef.update({
        'likes': FieldValue.arrayRemove([userIdentifier]),
        'likeCount': FieldValue.increment(-1),
      });
    } else {
      await docRef.update({
        'likes': FieldValue.arrayUnion([userIdentifier]),
        'likeCount': FieldValue.increment(1),
      });
    }
  }

  Future<void> _togglePin(bool currentStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('social_media_posts')
          .doc(widget.postId)
          .update({'isPinned': !currentStatus});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentStatus ? 'Sabitleme kaldırıldı' : 'Gönderi sabitlendi',
          ),
        ),
      );
    } catch (e) {
      print('Pin error: $e');
    }
  }

  Future<void> _deletePost() async {
    try {
      await FirebaseFirestore.instance
          .collection('social_media_posts')
          .doc(widget.postId)
          .delete();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gönderi silindi')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  void _editPost() {
    showDialog(
      context: context,
      builder: (ctx) => _EditPostModal(
        postId: widget.postId,
        initialCaption: widget.data['caption'],
        initialRecipients: List<String>.from(widget.data['recipients'] ?? []),
        schoolTypeId: widget.schoolTypeId,
      ),
    );
  }

  void _showPostOptions(bool isPinned, String creatorEmail) {
    final isOwner = widget.currentUserEmail == creatorEmail;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(
              isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              color: Colors.indigo,
            ),
            title: Text(isPinned ? 'Sabitlemeyi Kaldır' : 'Gönderiyi Sabitle'),
            onTap: () {
              Navigator.pop(context);
              _togglePin(isPinned);
            },
          ),
          if (isOwner) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Düzenle'),
              onTap: () {
                Navigator.pop(context);
                _editPost();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Sil'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Emin misiniz?'),
                    content: const Text('Bu gönderi kalıcı olarak silinecek.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('İptal'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deletePost();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Sil'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays > 7) return DateFormat('dd/MM/yyyy').format(date);
    if (difference.inDays > 0) return '${difference.inDays} gn';
    if (difference.inHours > 0) return '${difference.inHours} sa';
    if (difference.inMinutes > 0) return '${difference.inMinutes} dk';
    return 'Şimdi';
  }

  void _downloadBase64Image(String base64String) {
    try {
      final bytes = base64Decode(base64String);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute(
          "download",
          "image_${DateTime.now().millisecondsSinceEpoch}.jpg",
        )
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      print("Download error: $e");
    }
  }

  void _openFullScreenImage(List<String> images, int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => _FullScreenImageViewer(
        images: images,
        initialIndex: initialIndex,
        onDownload: _downloadBase64Image,
      ),
    );
  }

  String? _extractYoutubeId(String url) {
    if (url.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(url.trim());
      if (uri.host.contains('youtube.com')) {
        if (uri.queryParameters.containsKey('v')) {
          return uri.queryParameters['v'];
        }
        if (uri.pathSegments.contains('shorts') &&
            uri.pathSegments.last.isNotEmpty) {
          return uri.pathSegments.last;
        }
      }
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }
    } catch (e) {
      // ignore
    }

    RegExp regExp = RegExp(
      r'.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/|e\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 1) {
      final id = match.group(1);
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> _launchVideo(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Video açılamadı: $url')));
    }
  }

  String? _getEmbedUrl(String url) {
    url = url.trim();

    // 1. Google Drive (First Priority)
    if (url.contains('drive.google.com')) {
      final RegExp driveExp = RegExp(r'(?:file\/d\/|id=)([-_\w]+)');
      final match = driveExp.firstMatch(url);
      if (match != null) {
        final id = match.group(1);
        return 'https://drive.google.com/file/d/$id/preview';
      }
    }

    // 2. YouTube (Strict Check)
    if (url.contains('youtube.com') || url.contains('youtu.be')) {
      final youtubeId = _extractYoutubeId(url);
      if (youtubeId != null) {
        return 'https://www.youtube.com/embed/$youtubeId?autoplay=1&rel=0&modestbranding=1';
      }
    }

    // 3. Direct Video Files
    final lower = url.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.ogg')) {
      return url;
    }

    // Fallback
    return url;
  }

  Widget _buildVideoPlaceholder(String url) {
    if (_isPlaying) {
      // 2. Generic (Drive, MP4, etc.)
      final String? embedUrl = _getEmbedUrl(url);

      if (embedUrl != null) {
        final String viewId = 'web_view-${widget.postId}';
        try {
          // ignore: undefined_prefixed_name
          ui.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
            final element = html.IFrameElement()
              ..src = embedUrl
              ..style.border = 'none'
              ..allow =
                  'autoplay; fullscreen; picture-in-picture; encrypted-media';
            return element;
          });
        } catch (e) {}

        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              HtmlElementView(viewType: viewId),
              Positioned(top: 8, right: 8, child: _buildCloseButton()),
            ],
          ),
        );
      }
    }

    final videoId = _extractYoutubeId(url);
    final thumbnailUrl = videoId != null
        ? 'https://img.youtube.com/vi/$videoId/0.jpg'
        : '';

    return GestureDetector(
      onTap: () {
        setState(() => _isPlaying = true);
      },
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            thumbnailUrl.isNotEmpty
                ? Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (c, o, s) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2C3E50), Color(0xFF000000)],
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2C3E50), Color(0xFF000000)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.video_library,
                        color: Colors.white54,
                        size: 40,
                      ),
                    ),
                  ),
            Container(color: Colors.black26),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return InkWell(
      onTap: () {
        setState(() {
          _isPlaying = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final likeCount = data['likeCount'] ?? 0;
    final likes = List<String>.from(data['likes'] ?? []);
    final userIdentifier = widget.currentUserEmail ?? widget.currentUserId;
    final isLiked = userIdentifier != null && likes.contains(userIdentifier);
    final caption = data['caption'] ?? '';
    final creatorName = data['creatorName'] ?? 'Anonim';
    final creatorPhotoUrl = data['creatorPhotoUrl'];
    final timestamp = data['createdAt'] as Timestamp?;
    final date = timestamp?.toDate() ?? DateTime.now();
    final isPinned = data['isPinned'] ?? false;
    final creatorEmail = data['createdBy'] ?? '';

    List<String> images = [];
    if (data['mediaItems'] != null) {
      images = List<String>.from(data['mediaItems']);
    } else if (data['imageBase64'] != null &&
        data['imageBase64'].toString().isNotEmpty) {
      images = [data['imageBase64']];
    }

    final videoUrl = data['videoUrl'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: creatorPhotoUrl != null
                      ? NetworkImage(creatorPhotoUrl)
                      : null,
                  backgroundColor: Colors.indigo.shade50,
                  child: creatorPhotoUrl == null
                      ? Icon(
                          Icons.person,
                          size: 18,
                          color: Colors.indigo.shade300,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        creatorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isPinned)
                        const Row(
                          children: [
                            Icon(
                              Icons.push_pin,
                              size: 12,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Sabitlendi",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onPressed: () => _showPostOptions(isPinned, creatorEmail),
                ),
              ],
            ),
          ),

          // Image Area
          Expanded(
            child: (videoUrl != null && videoUrl.isNotEmpty)
                ? _buildVideoPlaceholder(videoUrl)
                : images.isNotEmpty
                ? Stack(
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: images.length,
                        onPageChanged: (idx) =>
                            setState(() => _currentImageIndex = idx),
                        itemBuilder: (context, idx) {
                          return GestureDetector(
                            onTap: () => _openFullScreenImage(images, idx),
                            child: Image.memory(
                              base64Decode(images[idx]),
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, _, __) => Container(
                                color: Colors.grey[100],
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          );
                        },
                      ),
                      if (images.length > 1) ...[
                        if (_currentImageIndex > 0)
                          Positioned(
                            left: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: CircleAvatar(
                                backgroundColor: Colors.black26,
                                radius: 14,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.chevron_left,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _pageController.previousPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        if (_currentImageIndex < images.length - 1)
                          Positioned(
                            right: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: CircleAvatar(
                                backgroundColor: Colors.black26,
                                radius: 14,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _pageController.nextPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                      if (images.length > 1)
                        Positioned(
                          bottom: 8,
                          right: 0,
                          left: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(images.length, (index) {
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                width: _currentImageIndex == index ? 8 : 6,
                                height: _currentImageIndex == index ? 8 : 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == index
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              );
                            }),
                          ),
                        ),
                      if (images.length > 1)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "${_currentImageIndex + 1}/${images.length}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : Container(
                    color: Colors.grey[100],
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.grey,
                      ),
                    ),
                  ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.black,
                  ),
                  onPressed: () => _toggleLike(likes),
                ),
                if (likeCount > 0)
                  Text(
                    '$likeCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),

                const Spacer(),
                IconButton(
                  icon: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: isPinned ? Colors.orange : Colors.grey,
                  ),
                  onPressed: () => _togglePin(isPinned),
                  tooltip: 'Sabitle',
                ),
              ],
            ),
          ),

          // Caption & Date
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caption.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$creatorName ',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: caption,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Text(
                  _formatTimeAgo(date),
                  style: TextStyle(color: Colors.grey[500], fontSize: 10),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final Function(String) onDownload;

  const _FullScreenImageViewer({
    Key? key,
    required this.images,
    required this.initialIndex,
    required this.onDownload,
  }) : super(key: key);

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(
                  base64Decode(widget.images[index]),
                  fit: BoxFit.contain,
                ),
              );
            },
          ),
          if (widget.images.length > 1) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => _controller.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                  ),
                ),
              ),
            if (_currentIndex < widget.images.length - 1)
              Positioned(
                right: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward, color: Colors.white),
                    onPressed: () => _controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                  ),
                ),
              ),
          ],
          Positioned(
            top: 40,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: () =>
                    widget.onDownload(widget.images[_currentIndex]),
              ),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 40,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${_currentIndex + 1} / ${widget.images.length}",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditPostModal extends StatefulWidget {
  final String postId;
  final String initialCaption;
  final List<String> initialRecipients;
  final String schoolTypeId;

  const _EditPostModal({
    Key? key,
    required this.postId,
    required this.initialCaption,
    required this.initialRecipients,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<_EditPostModal> createState() => _EditPostModalState();
}

class _EditPostModalState extends State<_EditPostModal> {
  late TextEditingController _captionController;
  late List<String> _recipients;
  bool _isPublic = false;
  final AnnouncementService _announcementService = AnnouncementService();

  List<Map<String, dynamic>> _classes = [];
  String? _selectedClass;
  bool _isLoadingClasses = false;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
    _recipients = List.from(widget.initialRecipients);
    _isPublic = _recipients.isEmpty;
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoadingClasses = true);
    try {
      // Simplified: Just loading classes for the school type
      final classes = await _announcementService.getClasses(
        widget.schoolTypeId,
      );
      if (mounted) setState(() => _classes = classes);
    } catch (e) {
      print("Error loading classes: $e");
    } finally {
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  void _addRecipient(String id) {
    if (!_recipients.contains(id)) {
      setState(() {
        _recipients.add(id);
        _isPublic = false;
      });
    }
  }

  void _removeRecipient(String id) {
    setState(() {
      _recipients.remove(id);
      if (_recipients.isEmpty) _isPublic = true;
    });
  }

  void _addClassRecipients() {
    if (_selectedClass == null) return;
    // Format: class:schoolTypeId_ClassName
    // AnnouncementService logic might vary, but assuming format
    // Simple approach: Add as topic string
    _addRecipient('class:${widget.schoolTypeId}_$_selectedClass');
    setState(() => _selectedClass = null);
  }

  Future<void> _save() async {
    try {
      await FirebaseFirestore.instance
          .collection('social_media_posts')
          .doc(widget.postId)
          .update({
            'caption': _captionController.text.trim(),
            'recipients': _isPublic ? [] : _recipients,
            'isPublic': _isPublic,
          });
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gönderi güncellendi')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Gönderiyi Düzenle",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(
                labelText: "Açıklama",
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),

            // Audience Section
            const Text(
              "Hedef Kitle",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              title: const Text("Herkese Açık"),
              subtitle: const Text("Tüm okul ve veliler görebilir"),
              value: _isPublic,
              onChanged: (val) {
                setState(() {
                  _isPublic = val;
                  if (val) _recipients.clear();
                });
              },
            ),

            if (!_isPublic) ...[
              const Divider(),
              // Add Recipient Controls
              Row(
                children: [
                  Expanded(
                    child: _isLoadingClasses
                        ? const LinearProgressIndicator()
                        : DropdownButtonFormField<String>(
                            value: _selectedClass,
                            hint: const Text("Sınıf Seç"),
                            isExpanded: true,
                            items: _classes.map<DropdownMenuItem<String>>((c) {
                              final val = c['name'].toString();
                              return DropdownMenuItem<String>(
                                value: val,
                                child: Text(val),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setState(() => _selectedClass = val),
                          ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.indigo),
                    onPressed: _addClassRecipients,
                    tooltip: "Sınıf Ekle",
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _recipients.map((r) {
                  String label = r;
                  if (r.startsWith('class:')) label = r.split('_').last;
                  return Chip(
                    label: Text(label),
                    onDeleted: () => _removeRecipient(r),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("İptal"),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Kaydet"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
