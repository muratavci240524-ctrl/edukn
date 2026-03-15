class OpticalForm {
  final String id;
  final String name; // Optik Form Adı
  final String institutionId;
  final String examTypeId; // Uygulanacak Sınav Türü ID
  final String examTypeName; // Uygulanacak Sınav Türü Adı (Denormalized)

  // Standard Parametreler
  final OpticalField studentNo;
  final OpticalField studentNameField; // Ad Soyad
  final OpticalField identityNo; // Tc/Tel
  final OpticalField classLevel; // Sınıf Seviyesi
  final OpticalField branch; // Şube
  final OpticalField institutionCode; // Kurum Kodu
  final OpticalField session; // Oturum
  final OpticalField bookletType; // Kitapçık Türü

  // Ders Alanları (Ders Adı -> Konum)
  // Key: BranchName (e.g. 'Matematik')
  final Map<String, OpticalField> subjectFields;
  final bool isActive;

  OpticalForm({
    required this.id,
    required this.name,
    required this.institutionId,
    required this.examTypeId,
    required this.examTypeName,
    required this.studentNo,
    required this.studentNameField,
    required this.identityNo,
    required this.classLevel,
    required this.branch,
    required this.institutionCode,
    required this.session,
    required this.bookletType,
    required this.subjectFields,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'institutionId': institutionId,
      'examTypeId': examTypeId,
      'examTypeName': examTypeName,
      'studentNo': studentNo.toMap(),
      'studentName': studentNameField.toMap(),
      'identityNo': identityNo.toMap(),
      'classLevel': classLevel.toMap(),
      'branch': branch.toMap(),
      'institutionCode': institutionCode.toMap(),
      'session': session.toMap(),
      'bookletType': bookletType.toMap(),
      'subjectFields': subjectFields.map((k, v) => MapEntry(k, v.toMap())),
      'isActive': isActive,
    };
  }

  factory OpticalForm.fromMap(Map<String, dynamic> map, String id) {
    return OpticalForm(
      id: id,
      name: map['name'] ?? '',
      institutionId: map['institutionId'] ?? '',
      examTypeId: map['examTypeId'] ?? '',
      examTypeName: map['examTypeName'] ?? '',
      studentNo: OpticalField.fromMap(map['studentNo'] ?? {}),
      studentNameField: OpticalField.fromMap(map['studentName'] ?? {}),
      identityNo: OpticalField.fromMap(map['identityNo'] ?? {}),
      classLevel: OpticalField.fromMap(map['classLevel'] ?? {}),
      branch: OpticalField.fromMap(map['branch'] ?? {}),
      institutionCode: OpticalField.fromMap(map['institutionCode'] ?? {}),
      session: OpticalField.fromMap(map['session'] ?? {}),
      bookletType: OpticalField.fromMap(map['bookletType'] ?? {}),
      subjectFields: (map['subjectFields'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, OpticalField.fromMap(v)),
      ),
      isActive: map['isActive'] ?? true,
    );
  }
}

class OpticalField {
  final int
  start; // Başlangıç (1-based index usually, but logic depends on implementation)
  final int length; // Uzunluk

  OpticalField({required this.start, required this.length});

  // Helper for End calculation
  int get end => start + length - 1;

  Map<String, dynamic> toMap() {
    return {'start': start, 'length': length};
  }

  factory OpticalField.fromMap(Map<String, dynamic> map) {
    return OpticalField(start: map['start'] ?? 0, length: map['length'] ?? 0);
  }

  // Empty helper
  factory OpticalField.empty() => OpticalField(start: 0, length: 0);
}
