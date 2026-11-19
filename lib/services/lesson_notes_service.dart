import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../screens/school/school_types/chat/chat_models.dart';
import 'announcement_service.dart';
import 'chat_service.dart';

/// Öğretmenin tahtada hazırladığı / kaydettiği not (sayfalar PNG + PDF).
class LessonNote {
  LessonNote({
    required this.id,
    required this.institutionId,
    required this.teacherId,
    required this.teacherName,
    required this.title,
    required this.pageUrls,
    required this.pdfUrl,
    required this.createdAt,
  });

  final String id;
  final String institutionId;
  final String teacherId;
  final String teacherName;
  final String title;
  final List<String> pageUrls;
  final String pdfUrl;
  final DateTime createdAt;

  int get pageCount => pageUrls.length;
  String get coverUrl => pageUrls.isNotEmpty ? pageUrls.first : '';

  factory LessonNote.fromMap(Map<String, dynamic> d, String id) => LessonNote(
    id: id,
    institutionId: (d['institutionId'] ?? '').toString(),
    teacherId: (d['teacherId'] ?? '').toString(),
    teacherName: (d['teacherName'] ?? '').toString(),
    title: (d['title'] ?? 'Ders Notu').toString(),
    pageUrls: List<String>.from(d['pageUrls'] ?? const []),
    pdfUrl: (d['pdfUrl'] ?? '').toString(),
    createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}

/// Bir notun belirli bir sınıf + derse eklenmiş hali.
class LessonNoteLink {
  LessonNoteLink({
    required this.id,
    required this.noteId,
    required this.title,
    required this.pageUrls,
    required this.pdfUrl,
    required this.classId,
    required this.className,
    required this.lessonId,
    required this.lessonName,
    required this.teacherId,
    required this.teacherName,
    required this.createdAt,
    required this.comment,
  });

  final String id;
  final String noteId;
  final String title;
  final List<String> pageUrls;
  final String pdfUrl;
  final String classId;
  final String className;
  final String lessonId;
  final String lessonName;
  final String teacherId;
  final String teacherName;
  final DateTime createdAt;
  final String comment;

  factory LessonNoteLink.fromMap(Map<String, dynamic> d, String id) =>
      LessonNoteLink(
        id: id,
        noteId: (d['noteId'] ?? '').toString(),
        title: (d['title'] ?? 'Ders Notu').toString(),
        pageUrls: List<String>.from(d['pageUrls'] ?? const []),
        pdfUrl: (d['pdfUrl'] ?? '').toString(),
        classId: (d['classId'] ?? '').toString(),
        className: (d['className'] ?? '').toString(),
        lessonId: (d['lessonId'] ?? '').toString(),
        lessonName: (d['lessonName'] ?? '').toString(),
        teacherId: (d['teacherId'] ?? '').toString(),
        teacherName: (d['teacherName'] ?? '').toString(),
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        comment: (d['comment'] ?? '').toString(),
      );
}

class LessonNotesService {
  LessonNotesService._();
  static final LessonNotesService instance = LessonNotesService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  Future<String> _teacherName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Öğretmen';
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final d = doc.data();
      final n = (d?['fullName'] ?? d?['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    } catch (_) {}
    return (user.email ?? 'Öğretmen').split('@').first;
  }

  static const Duration _uploadTimeout = Duration(seconds: 90);

  Never _timeoutError() => throw Exception(
    'Yükleme zaman aşımına uğradı. İnternet bağlantısını ve Firebase Storage kurallarını (lesson_notes/**) kontrol edin.',
  );

  /// Not sayfalarını (PNG) ve PDF'i Storage'a yükler, `lesson_notes` kaydını oluşturur.
  Future<LessonNote> saveNote({
    required String institutionId,
    required String title,
    required List<Uint8List> pagePngs,
    required Uint8List pdfBytes,
    void Function(String message)? onProgress,
  }) async {
    final teacherId = uid;
    if (teacherId == null) throw Exception('Oturum bulunamadı.');
    final docRef = _db.collection('lesson_notes').doc();
    final storage = FirebaseStorage.instance;
    final base = 'lesson_notes/$institutionId/$teacherId/${docRef.id}';

    final urls = <String>[];
    for (int i = 0; i < pagePngs.length; i++) {
      onProgress?.call('Sayfa ${i + 1}/${pagePngs.length} yükleniyor...');
      final ref = storage.ref('$base/page_${i + 1}.png');
      await ref
          .putData(pagePngs[i], SettableMetadata(contentType: 'image/png'))
          .timeout(_uploadTimeout, onTimeout: _timeoutError);
      urls.add(await ref.getDownloadURL());
    }
    onProgress?.call('PDF yükleniyor...');
    final pdfRef = storage.ref('$base/not.pdf');
    await pdfRef
        .putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'))
        .timeout(_uploadTimeout, onTimeout: _timeoutError);
    final pdfUrl = await pdfRef.getDownloadURL();

    final name = await _teacherName();
    await docRef.set({
      'id': docRef.id,
      'institutionId': institutionId,
      'teacherId': teacherId,
      'teacherName': name,
      'title': title,
      'pageCount': urls.length,
      'pageUrls': urls,
      'pdfUrl': pdfUrl,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final snap = await docRef.get();
    return LessonNote.fromMap(snap.data() ?? {}, docRef.id);
  }

  Future<List<LessonNote>> listMyNotes(String institutionId) async {
    final id = uid;
    if (id == null) return [];
    final snap = await _db
        .collection('lesson_notes')
        .where('institutionId', isEqualTo: institutionId)
        .where('teacherId', isEqualTo: id)
        .get();
    final list = snap.docs
        .where((d) => d.data()['isActive'] != false)
        .map((d) => LessonNote.fromMap(d.data(), d.id))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> deleteNote(LessonNote note) async {
    await _db.collection('lesson_notes').doc(note.id).update({
      'isActive': false,
    });
  }

  Future<void> attachToClass({
    required LessonNote note,
    required String institutionId,
    required String schoolTypeId,
    required String classId,
    required String className,
    required String lessonId,
    required String lessonName,
    String comment = '',
  }) async {
    final teacherName = await _teacherName();
    await _db.collection('lesson_note_links').add({
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'noteId': note.id,
      'title': note.title,
      'pageUrls': note.pageUrls,
      'pdfUrl': note.pdfUrl,
      'classId': classId,
      'className': className,
      'lessonId': lessonId,
      'lessonName': lessonName,
      'teacherId': uid ?? note.teacherId,
      'teacherName': teacherName,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<LessonNoteLink>> listClassNotes({
    required String institutionId,
    required String classId,
    String? lessonId,
  }) async {
    final snap = await _db
        .collection('lesson_note_links')
        .where('institutionId', isEqualTo: institutionId)
        .where('classId', isEqualTo: classId)
        .get();
    var list = snap.docs
        .map((d) => LessonNoteLink.fromMap(d.data(), d.id))
        .toList();
    if (lessonId != null && lessonId.isNotEmpty) {
      list = list.where((l) => l.lessonId == lessonId).toList();
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> deleteLink(String linkId) =>
      _db.collection('lesson_note_links').doc(linkId).delete();

  /// Notu sınıfa DUYURU olarak paylaşır (PDF ve sayfa görselleri bağlantı olarak eklenir).
  Future<void> shareAsAnnouncement({
    required String title,
    required String pdfUrl,
    required List<String> pageUrls,
    required String classId,
    required String className,
    String? schoolTypeId,
    String? message,
  }) async {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final token = 'branch:$classId:$className';
    final links = <Map<String, String>?>[
      {'title': 'Ders notunu aç (PDF)', 'url': pdfUrl},
      for (int i = 0; i < pageUrls.length && i < 5; i++)
        {'title': 'Sayfa ${i + 1}', 'url': pageUrls[i]},
    ];
    await AnnouncementService().saveAnnouncement(
      title: '📚 Ders Notu: $title',
      content: message?.trim().isNotEmpty == true
          ? message!.trim()
          : '$className şubesi için ders notu paylaşıldı. Aşağıdaki bağlantılardan inceleyebilirsiniz.',
      recipients: [token],
      publishDate: now,
      publishTime: '${two(now.hour)}:${two(now.minute)}',
      links: links,
      schoolTypeId: schoolTypeId,
      recipientNames: {token: '$className Şubesi'},
    );
  }

  /// Notu var olan bir sohbete MESAJ olarak gönderir.
  Future<void> shareAsMessage({
    required String conversationId,
    required String title,
    required String pdfUrl,
    String? message,
  }) async {
    final sender = uid;
    if (sender == null) throw Exception('Oturum bulunamadı.');
    final text = [
      '📚 Ders Notu: $title',
      if (message != null && message.trim().isNotEmpty) message.trim(),
      pdfUrl,
    ].join('\n');
    await ChatService().sendMessage(
      conversationId,
      ChatMessage(
        id: '',
        senderId: sender,
        content: text,
        timestamp: DateTime.now(),
        type: MessageType.text,
      ),
    );
  }

  /// Giriş yapan kullanıcının sohbetleri (ad çözümlemesiyle).
  Future<List<MapEntry<String, String>>> myConversations() async {
    final me = uid;
    if (me == null) return [];
    final snap = await _db
        .collection('conversations')
        .where('participantIds', arrayContains: me)
        .get();
    final out = <MapEntry<String, String>>[];
    final nameCache = <String, String>{};
    Future<String> nameOf(String id) async {
      if (nameCache.containsKey(id)) return nameCache[id]!;
      var n = id;
      try {
        final u = await _db.collection('users').doc(id).get();
        final d = u.data();
        n = (d?['fullName'] ?? d?['name'] ?? '').toString().trim();
        if (n.isEmpty) {
          final p = await _db.collection('parents').doc(id).get();
          final pd = p.data();
          n = '${pd?['name'] ?? ''} ${pd?['surname'] ?? ''}'.trim();
        }
        if (n.isEmpty) n = 'Kullanıcı';
      } catch (e) {
        debugPrint('[LessonNotes] ad çözülemedi: $e');
        n = 'Kullanıcı';
      }
      nameCache[id] = n;
      return n;
    }

    for (final d in snap.docs.take(60)) {
      final data = d.data();
      final chatName = (data['chatName'] ?? '').toString().trim();
      if (chatName.isNotEmpty) {
        out.add(MapEntry(d.id, chatName));
        continue;
      }
      final others = List<String>.from(
        data['participantIds'] ?? const [],
      ).where((p) => p != me).toList();
      final names = <String>[];
      for (final o in others.take(3)) {
        names.add(await nameOf(o));
      }
      out.add(MapEntry(d.id, names.isEmpty ? 'Sohbet' : names.join(', ')));
    }
    return out;
  }
}
