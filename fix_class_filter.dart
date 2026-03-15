// Bu dosyayı çalıştırmayın, sadece referans için
// Manuel düzeltme gerekiyor:

// 1. Satır 4873'ü bulun:
// .where('classLevel', isEqualTo: int.parse(_selectedClassLevel!))

// Değiştirin:
// .where('classLevel', isEqualTo: int.tryParse(_selectedClassLevel?.toString() ?? '0') ?? 0)

// 2. Hemen altına ekleyin (satır 4874'ten önce):
// .where('classTypeId', isEqualTo: 'DERS_SINIFI_ID') // Ders Sınıfı ID'sini bulup ekleyin

// 3. Aynı değişiklikleri satır 7734 için de yapın

// Alternatif: classTypeId yerine classTypeName kullanın:
// .where('classTypeName', isEqualTo: 'Ders Sınıfı')
