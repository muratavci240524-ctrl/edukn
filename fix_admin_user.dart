import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Tek seferlik çalıştırılacak script - Admin kullanıcı kaydı oluştur
void main() async {
  await Firebase.initializeApp();

  // Murat AVCI (okul yöneticisi) için users kaydı oluştur
  final adminUserData = {
    'authUserId': 'zcNQzEBLD9WaYn0puENLvk3VA5D2',
    'institutionId': 'ABC06',
    'schoolId': '2ej0GIw20xv8wdXN6Fiy',
    'fullName': 'Murat AVCI',
    'username': 'abckoleji',
    'email': 'abckoleji@ABC06.edukn',
    'phone': '05452242482',
    'role': 'genel_mudur', // Admin rolü
    'isActive': true,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),

    // Tüm modüllerde editor yetkisi
    'modulePermissions': {
      'kullanici_yonetimi': {'enabled': true, 'level': 'editor'},
      'ogrenci_kayit': {'enabled': true, 'level': 'editor'},
      'okul_turleri': {'enabled': true, 'level': 'editor'},
      'insan_kaynaklari': {'enabled': true, 'level': 'editor'},
      'muhasebe': {'enabled': true, 'level': 'editor'},
      'satin_alma': {'enabled': true, 'level': 'editor'},
      'depo': {'enabled': true, 'level': 'editor'},
      'destek_hizmetleri': {'enabled': true, 'level': 'editor'},
      'genel_duyurular': {'enabled': true, 'level': 'editor'},
    },

    // Okul türleri (schools dokümanından alınan activeModules'e göre ayarlanabilir)
    'schoolTypes': [], // Gerekirse doldur
    'schoolTypePermissions': {}, // Gerekirse doldur
  };

  try {
    // Admin kullanıcıyı Firebase Auth UID'i ile kaydet
    await FirebaseFirestore.instance
        .collection('users')
        .doc('zcNQzEBLD9WaYn0puENLvk3VA5D2') // Firebase Auth UID
        .set(adminUserData);

    print('✅ Admin kullanıcı kaydı oluşturuldu!');
    print('🎯 Artık kullanıcı yönetimi yapabilirsin.');
  } catch (e) {
    print('❌ Hata: $e');
  }
}
