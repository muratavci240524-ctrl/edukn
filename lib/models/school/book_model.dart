import 'package:cloud_firestore/cloud_firestore.dart';

enum BookType { reading, questionBank }

class BookSubtopic {
  final String id;
  String name;
  int testCount;
  int? questionsPerTest; // Global questions per test if list is empty
  List<int>? questionsPerTestList; // Individual counts per test

  BookSubtopic({
    required this.id,
    required this.name,
    required this.testCount,
    this.questionsPerTest,
    this.questionsPerTestList,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'testCount': testCount,
      'questionsPerTest': questionsPerTest,
      'questionsPerTestList': questionsPerTestList,
    };
  }

  factory BookSubtopic.fromMap(Map<String, dynamic> map) {
    return BookSubtopic(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      testCount: map['testCount'] ?? 0,
      questionsPerTest: map['questionsPerTest'],
      questionsPerTestList: map['questionsPerTestList'] != null
          ? List<int>.from(map['questionsPerTestList'])
          : null,
    );
  }
}

class BookTopic {
  final String id;
  String name;
  int? testCount;
  int? questionsPerTest;
  List<int>? questionsPerTestList; // Individual counts per test
  List<BookSubtopic> subtopics;

  BookTopic({
    required this.id,
    required this.name,
    this.testCount,
    this.questionsPerTest,
    this.questionsPerTestList,
    required this.subtopics,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'testCount': testCount,
      'questionsPerTest': questionsPerTest,
      'questionsPerTestList': questionsPerTestList,
      'subtopics': subtopics.map((x) => x.toMap()).toList(),
    };
  }

  factory BookTopic.fromMap(Map<String, dynamic> map) {
    return BookTopic(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      testCount: map['testCount'],
      questionsPerTest: map['questionsPerTest'],
      questionsPerTestList: map['questionsPerTestList'] != null
          ? List<int>.from(map['questionsPerTestList'])
          : null,
      subtopics: List<BookSubtopic>.from(
        (map['subtopics'] ?? []).map((x) => BookSubtopic.fromMap(x)),
      ),
    );
  }
}

class Book {
  final String id;
  final String institutionId;
  final String name;
  final BookType type;
  final String? author; // for reading
  final int? pageCount; // for reading
  final String? branch; // for question_bank
  final List<String> classLevels; // for question_bank
  final List<BookTopic> topics; // for question_bank
  final bool isActive;
  final DateTime createdAt;

  Book({
    required this.id,
    required this.institutionId,
    required this.name,
    required this.type,
    this.author,
    this.pageCount,
    this.branch,
    required this.classLevels,
    required this.topics,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'institutionId': institutionId,
      'name': name,
      'type': type.name,
      'author': author,
      'pageCount': pageCount,
      'branch': branch,
      'classLevels': classLevels,
      'topics': topics.map((x) => x.toMap()).toList(),
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Book.fromMap(Map<String, dynamic> map, String id) {
    return Book(
      id: id,
      institutionId: map['institutionId'] ?? '',
      name: map['name'] ?? '',
      type: BookType.values.byName(map['type'] ?? 'reading'),
      author: map['author'],
      pageCount: map['pageCount'],
      branch: map['branch'],
      classLevels: List<String>.from(map['classLevels'] ?? []),
      topics: List<BookTopic>.from(
        (map['topics'] ?? []).map((x) => BookTopic.fromMap(x)),
      ),
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }
}
