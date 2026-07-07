import 'package:cloud_functions/cloud_functions.dart';

/// Gemini AI Servisi — API çağrıları güvenli Cloud Function üzerinden yapılıyor.
/// API anahtarı istemci tarafında bulunmuyor, sunucuda Firebase Secrets'ta.
///
/// ⚙️ Setup:
///   firebase functions:secrets:set GEMINI_API_KEY
///   (Firebase Console'da API key'i Gemini AI Studio'dan alın)
class GeminiService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Öğrenci performansını Gemini AI ile analiz eder.
  /// API key server-side'da tutuluyor (Firebase Secrets).
  Future<String> analyzeStudentPerformance({
    required String studentName,
    required List<Map<String, dynamic>> topicAnalysis,
  }) async {
    try {
      final callable = _functions.httpsCallable('analyzeStudentPerformance');
      final result = await callable.call({
        'studentName': studentName,
        'topicAnalysis': topicAnalysis,
      });

      final data = result.data as Map<dynamic, dynamic>;
      if (data['status'] != 'success') {
        throw Exception('AI analizi başarısız.');
      }

      return data['analysis'] as String;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw Exception('Çok fazla AI isteği. Lütfen bekleyin.');
      }
      throw Exception('Yapay zeka analizi oluşturulamadı: ${e.message}');
    } catch (e) {
      throw Exception('Yapay zeka analizi oluşturulamadı: $e');
    }
  }
}
