import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'demo_seed_context.dart';

/// HABERLEŞME modülleri demo verisi:
///  * Ek duyurular   -> schools/{schoolDocId}/announcements (id: an2_<n>)
///  * Sosyal medya   -> social_media_posts
///  * Mesajlaşma     -> conversations (+ messages alt koleksiyonu)
///
/// Not: Sohbet ekranı konuşmaları `participantIds array-contains <uid>` ile
/// listeler. Demo kullanıcıların Auth hesabı yoktur; bu yüzden tohumlama anında
/// oturum açmış yönetici (varsa) bazı konuşmalara katılımcı olarak eklenir.
const List<String> demoCommunicationTopCollections = [
  'social_media_posts',
  'conversations',
];

/// Eklenen duyurular isDemo ile işaretlidir; çekirdek temizlik bunları siler.
const List<String> demoCommunicationSchoolSubcollections = [];

/// Temizlikte taranacak en fazla konuşma sayısı (seed bunun altında kalır).
const int _kMaxConversationScan = 150;

Timestamp _ts(DemoSeedContext ctx, int daysAgo, int hour, int minute) {
  var d = DateTime(
    ctx.today.year,
    ctx.today.month,
    ctx.today.day - daysAgo,
    hour,
    minute,
  );
  final floor = DateTime(
    ctx.termStart.year,
    ctx.termStart.month,
    ctx.termStart.day,
    8,
    0,
  );
  if (d.isBefore(floor)) d = floor.add(Duration(minutes: minute));
  return Timestamp.fromDate(d);
}

String _pad(int n) => n.toString().padLeft(2, '0');

Future<void> seedDemoCommunication(DemoSeedContext ctx) async {
  final students = ctx.allStudents;
  final teachers = ctx.teachers;
  String? adminUid;
  try {
    adminUid = FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {
    adminUid = null;
  }

  await _seedAnnouncements(ctx, students, teachers);
  await _seedSocialPosts(ctx, students, teachers);
  if (teachers.isNotEmpty) {
    await _seedChat(ctx, students, teachers, adminUid);
  }
}

// ---------------------------------------------------------------------------
// DUYURULAR
// ---------------------------------------------------------------------------
Future<void> _seedAnnouncements(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  List<DemoTeacherInfo> teachers,
) async {
  final col = ctx.schoolCol('announcements');
  if (col == null) return;
  final rng = ctx.rng;
  final typeId = ctx.types.isNotEmpty ? ctx.types.first.id : '';

  List<String> readers(int max) {
    final ids = <String>[
      ...teachers.map((t) => t.id),
      ...students.map((s) => s.id),
    ]..shuffle(rng);
    return ids.take(max).toList();
  }

  DemoClassInfo? cls(int i) =>
      ctx.classes.isEmpty ? null : ctx.classes[i % ctx.classes.length];

  // kind: g=genel, v=veli, o=öğretmen, c=sınıf-özel(veli), s=sınıf-özel(öğrenci)
  // status: p=published, w=pending approval, s=scheduled
  final items = <Map<String, dynamic>>[
    {
      'k': 'g',
      'st': 'p',
      'd': 1,
      't': 'ACİL: Hava Muhalefeti Nedeniyle Servis Değişikliği',
      'c':
          'Yarın sabah beklenen yoğun kar yağışı nedeniyle servis saatleri 30 dakika geç başlayacaktır. Velilerimizin bilgisine sunulur.',
      'sms': true,
      'pin': true,
    },
    {
      'k': 'v',
      'st': 'p',
      'd': 3,
      't': 'Dönem Sonu Veli Görüşmeleri Randevuları',
      'c':
          'Veli görüşmeleri için randevu takvimi portalda yayımlanmıştır. Lütfen uygun saatinizi seçerek öğretmeninize bildiriniz.',
      'sms': true,
    },
    {
      'k': 'o',
      'st': 'p',
      'd': 4,
      't': 'Öğretmenler Kurulu Toplantısı',
      'c':
          'Öğretmenler kurulu toplantısı Cuma günü 15:30\'da konferans salonunda yapılacaktır. Gündem: sınav takvimi ve rehberlik raporları.',
    },
    {
      'k': 'g',
      'st': 'p',
      'd': 5,
      't': 'Cumhuriyet Bayramı Kutlama Programı',
      'c':
          'Cumhuriyet Bayramı kutlama programımız okul bahçesinde saat 10:00\'da başlayacaktır. Tüm öğrencilerimiz ve velilerimiz davetlidir.',
      'pin': true,
    },
    {
      'k': 'c',
      'st': 'p',
      'd': 6,
      'ci': 0,
      't': 'Sınıf Veli Toplantısı Daveti',
      'c':
          'Sınıfımızın veli toplantısı Perşembe günü 18:00\'de sınıfımızda yapılacaktır. Katılımınız bizler için çok değerlidir.',
    },
    {
      'k': 's',
      'st': 'p',
      'd': 7,
      'ci': 1,
      't': 'Deneme Sınavı Hazırlık Çalışması',
      'c':
          'Hafta sonu yapılacak deneme sınavı öncesinde konu tekrarı için kaynak listesi sınıf panosuna asılmıştır. Başarılar dileriz.',
    },
    {
      'k': 'v',
      'st': 'p',
      'd': 9,
      't': 'Okul Fotoğraf Çekimi Bilgilendirmesi',
      'c':
          'Yıllık sınıf ve vesikalık fotoğraf çekimleri gelecek hafta yapılacaktır. Öğrencilerimizin okul kıyafetleriyle gelmesi rica olunur.',
    },
    {
      'k': 'g',
      'st': 'p',
      'd': 11,
      't': 'Kitap Okuma Kampanyası Başladı',
      'c':
          'Bu dönem "Her Gün 20 Sayfa" kitap okuma kampanyamıza tüm öğrencilerimiz davetlidir. En çok kitap okuyan sınıfa sürpriz ödül verilecektir.',
    },
    {
      'k': 'o',
      'st': 'w',
      'd': 0,
      'ti': 0,
      't': 'Laboratuvar Kullanım Saatleri Hakkında',
      'c':
          'Fen laboratuvarının hafta içi 5. ve 6. ders saatlerinde ortak kullanımı için yeni bir çizelge önerisi hazırlanmıştır. Onayınıza sunarım.',
    },
    {
      'k': 'v',
      'st': 'w',
      'd': 0,
      'ti': 1,
      't': 'Müze Gezisi İzin Formu',
      'c':
          'Önümüzdeki ay planlanan müze gezisi için veli izin formları sınıf öğretmenleri aracılığıyla dağıtılacaktır. Duyuru onayınıza sunulmuştur.',
    },
    {
      'k': 'c',
      'st': 'w',
      'd': 1,
      'ti': 2,
      'ci': 2,
      't': 'Ödev Teslim Takvimi Değişikliği',
      'c':
          'Matematik proje ödevinin teslim tarihi bir hafta uzatılmıştır. Yeni teslim tarihi duyuru ekinde belirtilmiştir.',
    },
    {
      'k': 'g',
      'st': 's',
      'd': -3,
      't': 'Kurum Tanıtım Günü',
      'c':
          'Gelecek hafta Cumartesi günü kurumumuzu tanıtım günü düzenlenecektir. Misafir veli ve öğrencilerimizi ağırlamak için hazırlıklar sürmektedir.',
    },
    {
      'k': 'v',
      'st': 's',
      'd': -5,
      't': 'Dönem İçi Ücret Ödemeleri Hatırlatması',
      'c':
          'Taksit ödemelerinde son ödeme günü ayın 15\'idir. Muhasebe birimimizden detaylı bilgi alabilirsiniz.',
      'sms': true,
    },
    {
      'k': 'g',
      'st': 's',
      'd': -7,
      't': 'Bilim Şenliği Etkinliği',
      'c':
          'Bilim şenliğimiz gelecek ay okulumuzda düzenlenecektir. Projeleriyle katılmak isteyen öğrencilerimiz öğretmenlerine başvurabilir.',
    },
    {
      'k': 'g',
      'st': 'p',
      'd': 14,
      't': 'Beslenme Çantası ve Sağlıklı Atıştırmalıklar',
      'c':
          'Sağlıklı beslenme haftası kapsamında öğrencilerimizin beslenme çantalarında meyve ve süt ürünleri tercih etmesini öneriyoruz.',
    },
  ];

  for (int i = 0; i < items.length; i++) {
    final it = items[i];
    final kind = it['k'] as String;
    final st = it['st'] as String;
    final dAgo = it['d'] as int;
    final hour = 8 + (i % 8);
    final minute = (i * 7) % 60;
    final created = _ts(ctx, dAgo < 0 ? 0 : dAgo, hour, minute);
    final publish = dAgo < 0
        ? Timestamp.fromDate(
            DateTime(
              ctx.today.year,
              ctx.today.month,
              ctx.today.day - dAgo,
              hour,
              minute,
            ),
          )
        : created;

    List<String> recipients;
    Map<String, String> recipientNames;
    final c = (it['ci'] != null) ? cls(it['ci'] as int) : null;
    switch (kind) {
      case 'v':
        recipients = ['VELI'];
        recipientNames = {'VELI': 'Tüm Veliler'};
        break;
      case 'o':
        recipients = ['TEACHER'];
        recipientNames = {'TEACHER': 'Tüm Öğretmenler'};
        break;
      case 'c':
        if (c != null) {
          final key = 'branch:${c.id}:Veliler';
          recipients = [key];
          recipientNames = {key: '${c.name} Veliler'};
        } else {
          recipients = ['ALL'];
          recipientNames = {'ALL': 'Herkes'};
        }
        break;
      case 's':
        if (c != null) {
          final key = 'branch:${c.id}:Öğrenciler';
          recipients = [key];
          recipientNames = {key: '${c.name} Öğrenciler'};
        } else {
          recipients = ['ALL'];
          recipientNames = {'ALL': 'Herkes'};
        }
        break;
      default:
        recipients = ['ALL'];
        recipientNames = {'ALL': 'Herkes'};
    }

    String createdBy = 'demo@edukn';
    String creatorName = 'Okul Yönetimi';
    if (it['ti'] != null && teachers.isNotEmpty) {
      final t = teachers[(it['ti'] as int) % teachers.length];
      createdBy = '${t.id}@demo.edukn';
      creatorName = t.fullName;
    }

    final status = st == 'p'
        ? 'published'
        : (st == 'w' ? 'pending_approval' : 'scheduled');
    final approval = st == 'w' ? 'pending' : 'approved';

    await ctx.set(col.doc(ctx.id('an2_$i')), {
      'title': it['t'],
      'content': it['c'],
      'summary': it['c'],
      'recipients': recipients,
      'recipientNames': recipientNames,
      'publishDate': publish,
      'publishTime': '${_pad(hour)}:${_pad(minute)}',
      'sendSms': it['sms'] == true,
      'links': <String>[],
      'createdAt': created,
      'createdBy': createdBy,
      'creatorName': creatorName,
      'isAnonymous': false,
      'status': status,
      'approvalStatus': approval,
      'schedulePublish': st == 's',
      'reminders': <Map<String, dynamic>>[],
      'isReminder': false,
      'isPinned': it['pin'] == true,
      'readBy': st == 'p' ? readers(ctx.between(6, 30)) : <String>[],
      'termId': ctx.termId,
      'schoolTypeId': c?.typeId ?? typeId,
      'targetSchoolTypeIds': [
        if ((c?.typeId ?? typeId).isNotEmpty) c?.typeId ?? typeId,
      ],
      'institutionId': ctx.inst,
    });
    ctx.count('Duyuru');
  }
}

// ---------------------------------------------------------------------------
// SOSYAL MEDYA
// ---------------------------------------------------------------------------
Future<void> _seedSocialPosts(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  List<DemoTeacherInfo> teachers,
) async {
  final rng = ctx.rng;
  final typeId = ctx.types.isNotEmpty ? ctx.types.first.id : '';
  final posts = <List<String>>[
    [
      'Fen Bilimleri Deney Günü',
      'Öğrencilerimiz laboratuvarda renkli kimya deneyleriyle bilimin büyüsünü keşfetti. Merak eden herkese teşekkürler! 🔬',
    ],
    [
      'Cumhuriyet Bayramı Coşkusu',
      '29 Ekim Cumhuriyet Bayramımızı okulumuzda şiirler, şarkılar ve koro gösterisiyle kutladık. 🇹🇷',
    ],
    [
      'Kitap Okuma Kampanyamız Başladı',
      'Bu dönem "Her Gün 20 Sayfa" kampanyamızla okuma alışkanlığı kazandırıyoruz. Sınıflarımız yarışıyor! 📚',
    ],
    [
      'Robotik Kodlama Atölyesi',
      'Robotik kodlama kulübümüz ilk projesini tamamladı. Küçük mühendislerimizi tebrik ederiz. 🤖',
    ],
    [
      'Basketbol Turnuvası Şampiyonları',
      'Okullar arası basketbol turnuvasında takımımız ikinci oldu. Emeği geçen herkesi kutluyoruz! 🏀',
    ],
    [
      'Veli Toplantımızdan Kareler',
      'Dönem ilk veli toplantımızda velilerimizle keyifli bir buluşma gerçekleştirdik. Katılan herkese teşekkür ederiz.',
    ],
    [
      'Resim Sergisi Açıldı',
      'Görsel sanatlar dersinde hazırlanan eserler okul koridorumuzda sergileniyor. Hepinizi bekleriz. 🎨',
    ],
    [
      'Deneme Sınavı Başarıları',
      'Bu haftaki deneme sınavında başarı gösteren öğrencilerimizi gururla tebrik ederiz. 🌟',
    ],
    [
      'Sağlıklı Beslenme Haftası',
      'Beslenme haftası etkinliklerinde öğrencilerimiz meyve tabakları hazırladı ve sağlıklı yaşam üzerine sunum yaptı. 🍎',
    ],
    [
      'Okul Gezisi: Bilim Merkezi',
      'Öğrencilerimizle birlikte bilim merkezi gezimizi gerçekleştirdik. Gözlemleri çok değerliydi.',
    ],
  ];
  final likers = <String>[
    ...teachers.map((t) => t.id),
    ...students.map((s) => s.id),
  ];

  for (int i = 0; i < posts.length; i++) {
    final likeCount = likers.isEmpty
        ? 0
        : math.min(likers.length, ctx.between(5, 40));
    final shuffled = [...likers]..shuffle(rng);
    final likes = shuffled.take(likeCount).toList();
    final reads = shuffled
        .take(math.min(shuffled.length, likeCount + 15))
        .toList();
    final t = teachers.isEmpty ? null : teachers[i % teachers.length];
    await ctx.set(ctx.col('social_media_posts').doc(ctx.id('sm_$i')), {
      'schoolTypeId': typeId,
      'institutionId': ctx.inst,
      'imageUrl': '',
      'imageBase64': '',
      'mediaItems': <String>[],
      'videoUrl': '',
      'title': posts[i][0],
      'caption': posts[i][1],
      'createdAt': _ts(ctx, 1 + i * 3, 9 + (i % 6), (i * 11) % 60),
      'createdBy': t == null ? 'demo@edukn' : '${t.id}@demo.edukn',
      'creatorName': i % 3 == 0 || t == null ? 'Okul Yönetimi' : t.fullName,
      'creatorPhotoUrl': null,
      'likes': likes,
      'likeCount': likes.length,
      'commentCount': 0,
      'recipients': <String>[],
      'recipientNames': <String, String>{},
      'isPublic': true,
      'isPinned': i == 1,
      'readBy': reads,
    });
    ctx.count('Sosyal Medya Paylaşımı');
  }
}

// ---------------------------------------------------------------------------
// SOHBET
// ---------------------------------------------------------------------------
const List<List<String>> _teacherParentDialogs = [
  [
    '1|Merhaba hocam, {s} bu hafta derse biraz isteksiz geldiğini söyledi. Bir sorun var mı?',
    '0|Merhaba, genel olarak iyi ama son iki derste ödevlerini eksik getirdi. Birlikte takip edersek toparlayacaktır.',
    '1|Teşekkürler, akşamları kontrol edeceğim. Ek kaynak önerir misiniz?',
    '0|Elbette, yarın portala çalışma kâğıdı yükleyeceğim.',
    '1|Çok sağ olun hocam, kolay gelsin.',
  ],
  [
    '0|Merhaba, {s} bugün derste çok başarılıydı, tebrik ederim. 👏',
    '1|Çok teşekkür ederiz, evde de çok çalışıyor. Bu sevindirici.',
    '0|Deneme sınavında da yükselişte, böyle devam ederse hedefine ulaşır.',
  ],
  [
    '1|İyi günler, {s} yarın sağlık kontrolü nedeniyle okula gelemeyecek. İzin için ne yapmalıyım?',
    '0|İyi günler, rapor veya randevu belgesini sınıf defterine iletmeniz yeterli. Geçmiş olsun.',
    '1|Teşekkürler, belgeyi yarın gönderirim.',
    '0|Tamamdır, derslerini ben takip edip paylaşırım.',
  ],
  [
    '1|Hocam veli toplantısı için müsait bir saat var mı?',
    '0|Perşembe günü 16:00 veya 17:30 uygun. Hangisi sizin için daha iyi?',
    '1|17:30 uygun olur, teşekkürler.',
  ],
];

const List<List<String>> _teacherTeacherDialogs = [
  [
    '0|Merhaba, yarınki sınav gözetmenliğinde yer değişikliği yapabilir miyiz?',
    '1|Tabii, 3. ders sende olsun, ben 5. dersi alırım.',
    '0|Süper, teşekkürler. Müdür yardımcısına bildiririm.',
  ],
  [
    '1|Ortak proje ödevi için rubriği paylaşabilir misin?',
    '0|Hemen gönderiyorum, puanlama kriterlerini de ekledim.',
    '1|Harika, ortak bir sunum günü planlayalım.',
    '0|Cuma 6. ders laboratuvar boş, orayı alalım.',
  ],
  [
    '0|Zümre toplantısı için gündem maddelerin var mı?',
    '1|Sınav takvimi ve ortak yazılı soruları. Bir de kazanım dağılımı.',
    '0|Not aldım, taslağı akşam paylaşırım.',
  ],
];

const List<List<String>> _adminTeacherDialogs = [
  [
    '0|Merhaba hocam, sınıfınızın dönem içi devamsızlık raporu hazır mı?',
    '1|Merhaba, akşama kadar sisteme işlemiş olacağım.',
    '0|Teşekkürler. Riskli öğrencileri ayrıca not düşebilir misiniz?',
    '1|Tabii, üç öğrenci için görüşme planladım.',
  ],
  [
    '1|Müdür Bey/Hanım, etkinlik için salon talebimiz onaylandı mı?',
    '0|Evet, Çarşamba 14:00 sizin için ayrıldı.',
    '1|Teşekkür ederim, hazırlıkları başlatıyorum.',
  ],
  [
    '0|Hocam yarınki nöbet çizelgesinde değişiklik oldu, kontrol eder misiniz?',
    '1|Baktım, giriş kapısı nöbeti bende. Teşekkürler.',
  ],
];

const List<List<String>> _adminParentDialogs = [
  [
    '1|İyi günler, servis saatiyle ilgili bilgi alabilir miyim? {s} için yeni durak talebimiz var.',
    '0|İyi günler, talebinizi aldım. Servis sorumlusuyla görüşüp bugün dönüş yapacağım.',
    '1|Teşekkür ederim, bekliyorum.',
  ],
  [
    '1|Merhaba, dönem sonu taksit planı hakkında bilgi alabilir miyim?',
    '0|Merhaba, muhasebe birimimiz detayları size iletecektir. İyi günler dilerim.',
  ],
];

const List<List<String>> _groupMessages = [
  ['Arkadaşlar yarın sınav haftası programı yayımlanacak, kontrol edelim.'],
  ['Deneme sınavı sonuçları portala yüklendi. 📊'],
  ['Hafta sonu etkinliği için gönüllü arıyoruz.'],
  ['Teşekkürler, ben ilgileniyorum.'],
  ['Toplantı Cuma 15:30\'da, katılım önemli.'],
  ['Not aldım, hazırlıkları tamamlayacağım.'],
  ['Servis saatleri yarın 30 dk geç başlayacak, duyuru yapıldı.'],
  ['Süper, teşekkürler!'],
];

Future<void> _seedChat(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  List<DemoTeacherInfo> teachers,
  String? adminUid,
) async {
  final rng = ctx.rng;
  int convNo = 0;

  String parentId(DemoStudentInfo s) => ctx.id('p_${s.no}');

  Future<void> writeConv({
    required List<String> participants,
    required Map<String, String> names,
    required List<Map<String, dynamic>> msgs, // {s: senderId, c: text, ch?}
    required int daysAgoStart,
    bool isGroup = false,
    String? chatName,
    bool pinned = false,
    Map<String, int>? forcedUnread,
  }) async {
    if (convNo >= _kMaxConversationScan - 1) return;
    final convRef = ctx.col('conversations').doc(ctx.id('cv_$convNo'));
    convNo++;

    // Zaman damgaları
    var cur = DateTime(
      ctx.today.year,
      ctx.today.month,
      ctx.today.day - daysAgoStart,
      9 + rng.nextInt(6),
      rng.nextInt(60),
    );
    final floor = ctx.termStart.add(const Duration(hours: 9));
    if (cur.isBefore(floor)) cur = floor;
    final times = <DateTime>[];
    for (int i = 0; i < msgs.length; i++) {
      times.add(cur);
      cur = cur.add(Duration(minutes: 2 + rng.nextInt(45)));
      if (rng.nextInt(5) == 0)
        cur = cur.add(Duration(hours: 3 + rng.nextInt(10)));
    }
    final now = DateTime.now();
    for (int i = 0; i < times.length; i++) {
      if (times[i].isAfter(now)) {
        times[i] = now.subtract(Duration(minutes: (times.length - i) * 3));
      }
    }

    // Okunmamış sayıları
    final lastSender = msgs.last['s'] as String;
    int trailing = 0;
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i]['s'] == lastSender) {
        trailing++;
      } else {
        break;
      }
    }
    final unreadCounts = <String, int>{};
    final unreadMsgIdx = <int>{};
    if (forcedUnread != null) {
      forcedUnread.forEach((k, v) => unreadCounts[k] = v);
    } else if (!isGroup) {
      final other = participants.firstWhere(
        (p) => p != lastSender,
        orElse: () => lastSender,
      );
      final n = math.min(trailing, [0, 0, 1, 2, 3][rng.nextInt(5)]);
      unreadCounts[other] = n;
      for (int k = 0; k < n; k++) {
        unreadMsgIdx.add(msgs.length - 1 - k);
      }
    }
    for (final p in participants) {
      unreadCounts.putIfAbsent(p, () => 0);
    }
    final totalUnread = unreadCounts.values.fold<int>(0, (a, b) => a + b);

    Map<String, dynamic> msgMap(int i) => {
      'senderId': msgs[i]['s'],
      'content': msgs[i]['c'],
      'timestamp': Timestamp.fromDate(times[i]),
      'isRead': !unreadMsgIdx.contains(i),
      'type': 'text',
      'isStarred': false,
      'isForwarded': false,
      'isEdited': false,
      'repliedMessage': null,
      'recipientChannel': msgs[i]['ch'],
    };

    for (int i = 0; i < msgs.length; i++) {
      await ctx.set(convRef.collection('messages').doc(ctx.id('m_$i')), {
        ...msgMap(i),
        'participants': participants,
        'institutionId': ctx.inst,
      });
    }

    await ctx.set(convRef, {
      'participantIds': participants,
      'participantNames': names,
      'lastMessage': msgMap(msgs.length - 1),
      'unreadCount': totalUnread,
      'unreadCounts': unreadCounts,
      'chatName': chatName,
      'chatImage': null,
      'isArchived': false,
      'isPinned': pinned,
      'isGroup': isGroup,
      'termId': ctx.termId,
      'updatedAt': Timestamp.fromDate(times.last),
      'institutionId': ctx.inst,
    });
    ctx.count('Mesaj Görüşmesi');
    ctx.count('Mesaj', msgs.length);
  }

  List<Map<String, dynamic>> script(
    List<String> dialog,
    String a,
    String b,
    String studentName,
  ) {
    return dialog.map((line) {
      final i = line.indexOf('|');
      final who = line.substring(0, i) == '0' ? a : b;
      final text = line.substring(i + 1).replaceAll('{s}', studentName);
      return <String, dynamic>{'s': who, 'c': text};
    }).toList();
  }

  // 1) Öğretmen ↔ Veli
  if (students.isNotEmpty) {
    final count = math.min(14, students.length);
    final used = <String>{};
    for (int i = 0; i < count; i++) {
      final s = students[(i * 7 + 3) % students.length];
      if (!used.add(s.id)) continue;
      final t = teachers[i % teachers.length];
      final pid = parentId(s);
      final d = _teacherParentDialogs[i % _teacherParentDialogs.length];
      await writeConv(
        participants: [t.id, pid],
        names: {t.id: t.fullName, pid: '${s.fullName} Velisi'},
        msgs: script(d, t.id, pid, s.fullName.split(' ').first),
        daysAgoStart: 1 + (i * 2) % 20,
      );
    }
  }

  // 2) Öğretmen ↔ Öğretmen
  if (teachers.length >= 2) {
    for (int i = 0; i < 6; i++) {
      final a = teachers[i % teachers.length];
      final b = teachers[(i + 1 + i ~/ teachers.length) % teachers.length];
      if (a.id == b.id) continue;
      final d = _teacherTeacherDialogs[i % _teacherTeacherDialogs.length];
      await writeConv(
        participants: [a.id, b.id],
        names: {a.id: a.fullName, b.id: b.fullName},
        msgs: script(d, a.id, b.id, ''),
        daysAgoStart: 1 + i * 3,
      );
    }
  }

  // 3) Yönetici ↔ Öğretmen / Veli ve gruplar (yönetici hesabı varsa)
  if (adminUid != null && adminUid.isNotEmpty) {
    final adminName = 'Okul Yönetimi';
    for (int i = 0; i < math.min(6, teachers.length); i++) {
      final t = teachers[(i * 2) % teachers.length];
      final d = _adminTeacherDialogs[i % _adminTeacherDialogs.length];
      await writeConv(
        participants: [adminUid, t.id],
        names: {adminUid: adminName, t.id: t.fullName},
        msgs: script(d, adminUid, t.id, ''),
        daysAgoStart: i * 2,
        pinned: i == 0,
      );
    }
    for (int i = 0; i < math.min(3, students.length); i++) {
      final s = students[(i * 11 + 5) % students.length];
      final pid = parentId(s);
      final d = _adminParentDialogs[i % _adminParentDialogs.length];
      await writeConv(
        participants: [adminUid, pid],
        names: {adminUid: adminName, pid: '${s.fullName} Velisi'},
        msgs: script(d, adminUid, pid, s.fullName.split(' ').first),
        daysAgoStart: 2 + i * 4,
      );
    }
  }

  // 4) Gruplar
  Future<void> group(
    String name,
    List<String> memberIds,
    Map<String, String> names,
    int daysAgo,
    String? adminId,
  ) async {
    final members = <String>{
      ...memberIds,
      if (adminId != null) adminId,
    }.toList();
    if (members.length < 3) return;
    final msgs = <Map<String, dynamic>>[];
    final n = 6 + rng.nextInt(5);
    String? prev;
    for (int i = 0; i < n; i++) {
      var sender = members[rng.nextInt(members.length)];
      if (sender == prev)
        sender = members[(members.indexOf(sender) + 1) % members.length];
      prev = sender;
      msgs.add({
        's': sender,
        'c': _groupMessages[(i + daysAgo) % _groupMessages.length].first,
      });
    }
    final unread = <String, int>{};
    for (final m in members) {
      unread[m] = rng.nextInt(4) == 0 ? 0 : rng.nextInt(5);
    }
    if (adminId != null) unread[adminId] = 1 + rng.nextInt(4);
    await writeConv(
      participants: members,
      names: names,
      msgs: msgs,
      daysAgoStart: daysAgo,
      isGroup: true,
      chatName: name,
      forcedUnread: unread,
      pinned: name == 'Öğretmenler Odası',
    );
  }

  final allNames = <String, String>{for (final t in teachers) t.id: t.fullName};
  if (adminUid != null && adminUid.isNotEmpty)
    allNames[adminUid] = 'Okul Yönetimi';
  await group(
    'Öğretmenler Odası',
    teachers.map((t) => t.id).toList(),
    allNames,
    2,
    adminUid,
  );

  for (int i = 0; i < math.min(4, ctx.classes.length); i++) {
    final c = ctx.classes[i];
    final tIds = <String>{
      for (final l in c.lessons) l.teacherId,
    }.where((id) => id.isNotEmpty).toList();
    if (tIds.length < 2) continue;
    final names = <String, String>{};
    for (final t in teachers) {
      if (tIds.contains(t.id)) names[t.id] = t.fullName;
    }
    if (adminUid != null && adminUid.isNotEmpty)
      names[adminUid] = 'Okul Yönetimi';
    await group('${c.name} Sınıf Grubu', tIds, names, 3 + i * 2, adminUid);
  }

  // Branş zümresi grubu (varsa)
  final branches = <String, List<DemoTeacherInfo>>{};
  for (final t in teachers) {
    branches.putIfAbsent(t.branch, () => []).add(t);
  }
  for (final e in branches.entries) {
    if (e.value.length >= 2 && e.key.isNotEmpty) {
      await group(
        '${e.key} Zümresi',
        e.value.map((t) => t.id).toList(),
        {for (final t in e.value) t.id: t.fullName},
        6,
        null,
      );
      break;
    }
  }
}

// ---------------------------------------------------------------------------
// TEMİZLİK
// ---------------------------------------------------------------------------
Future<int> cleanDemoCommunicationExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async {
  int deleted = 0;
  WriteBatch batch = db.batch();
  int pending = 0;

  Future<void> queue(DocumentReference ref) async {
    batch.delete(ref);
    pending++;
    deleted++;
    if (pending >= 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }

  for (int n = 0; n < _kMaxConversationScan; n++) {
    try {
      final msgs = await db
          .collection('conversations')
          .doc('${prefix}cv_$n')
          .collection('messages')
          .get();
      for (final d in msgs.docs) {
        await queue(d.reference);
      }
    } catch (_) {
      // yoksay
    }
  }
  if (pending > 0) {
    await batch.commit();
  }
  return deleted;
}
