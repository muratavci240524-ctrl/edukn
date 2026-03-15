import '../../survey_model.dart';

abstract class GuidanceTestDefinition {
  String get id;
  String get title;
  String get description;
  List<SurveySection> get sections;
  bool get isAnonymous => false;

  /// Creates a Survey instance from this definition
  Survey createSurvey({
    required String institutionId,
    required String schoolTypeId,
    required String authorId,
    required List<String> targetIds,
    required SurveyTargetType targetType,
    DateTime? scheduledAt,
  }) {
    return Survey(
      id: '', // ID will be assigned by Firestore/Service
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      title: title,
      description: description,
      authorId: authorId,
      createdAt: DateTime.now(),
      publishedAt: null,
      scheduledAt: scheduledAt,
      closedAt: null,
      status: SurveyStatus.draft,
      targetType: targetType,
      targetIds: targetIds,
      sections: sections,
      responseCount: 0,
      isAnonymous: isAnonymous,
      guidanceTemplateId: id,
    );
  }
}
