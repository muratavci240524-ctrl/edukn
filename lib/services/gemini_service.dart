import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  // TODO: Secure this key! Ideally, fetch from a secure backend or environment variable.
  // For this prototype, we will ask the user to input it or hardcode it temporarily.
  // You can get an API key from https://aistudio.google.com/
  static const String _apiKey = "YOUR_API_KEY_HERE";

  late final GenerativeModel _model;

  GeminiService() {
    // Switching to gemini-pro for stability
    _model = GenerativeModel(model: 'gemini-pro', apiKey: _apiKey);
  }

  // Initialize with a custom key if needed (e.g. from user input)
  GeminiService.withKey(String apiKey) {
    _model = GenerativeModel(model: 'gemini-pro', apiKey: apiKey);
  }

  Future<String> analyzeStudentPerformance({
    required String studentName,
    required List<Map<String, dynamic>> topicAnalysis,
  }) async {
    try {
      // 1. Prepare Data for Prompt
      final weakTopics = topicAnalysis
          .where((e) => (e['success'] as num) < 50)
          .map((e) => "${e['subject']} - ${e['topic']} (%${e['success']})")
          .join(", ");

      final strongTopics = topicAnalysis
          .where((e) => (e['success'] as num) >= 80)
          .map((e) => "${e['subject']} - ${e['topic']} (%${e['success']})")
          .join(", ");

      final averageSuccess = topicAnalysis.isNotEmpty
          ? topicAnalysis
                    .map((e) => (e['success'] as num).toDouble())
                    .reduce((a, b) => a + b) /
                topicAnalysis.length
          : 0;

      // 2. Construct Prompt
      final prompt =
          '''
      Sen tecrübeli, motive edici ve öğrenci psikolojisinden anlayan bir rehberlik öğretmenisin.
      
      Öğrenci Adı: $studentName
      Genel Başarı Ortalaması: %${averageSuccess.toStringAsFixed(1)}
      
      Zayıf Olduğu Konular (Acil Çalışmalı): $weakTopics
      Güçlü Olduğu Konular (Pekiştirmeli): $strongTopics
      
      GÖREV:
      Bu öğrenci için 3-4 cümlelik, KISA, ÖZ ve MOTİVE EDİCİ bir haftalık çalışma tavsiyesi yaz.
      
      KURALLAR:
      1. Doğrudan öğrenciye hitap et ("Ahmet, harikasın..." gibi).
      2. Emojiler kullan (🚀, ✨, 📚, 🎯 gibi) ama abartma.
      3. Zayıf konuları için spesifik bir strateji öner (örn: "Video izle", "Soru çöz").
      4. Güçlü yönlerini takdir et.
      5. HTML veya Markdown kullanma, sadece düz metin (ve emoji).
      6. Çıktı çok uzun olmasın, bir paragrafa sığsın.
      ''';

      // 3. Call API
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (response.text == null || response.text!.isEmpty) {
        throw Exception("Boş cevap döndü.");
      }

      return response.text!;
    } catch (e) {
      print("Gemini API Error: $e");
      // Fallback message (or rethrow to let UI handle it)
      throw Exception("Yapay zeka analizi oluşturulamadı: $e");
    }
  }
}
