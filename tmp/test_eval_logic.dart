import 'package:edukn/models/assessment/trial_exam_model.dart';
import 'package:flutter/material.dart';

void main() {
  debugPrint('Testing TrialExam.evaluateAnswer...');

  // Test Case: S (Correct for all)
  assert(TrialExam.evaluateAnswer('A', 'S') == AnswerStatus.correct);
  assert(TrialExam.evaluateAnswer('B', 'S') == AnswerStatus.correct);
  assert(TrialExam.evaluateAnswer(' ', 'S') == AnswerStatus.correct);

  // Test Case: X (Cancelled)
  assert(TrialExam.evaluateAnswer('A', 'X') == AnswerStatus.correct);
  assert(TrialExam.evaluateAnswer(' ', 'X') == AnswerStatus.correct);

  // Test Case: # (Blank for all)
  assert(TrialExam.evaluateAnswer('A', '#') == AnswerStatus.empty);
  assert(TrialExam.evaluateAnswer(' ', '#') == AnswerStatus.empty);

  // Test Case: Standard
  assert(TrialExam.evaluateAnswer('A', 'A') == AnswerStatus.correct);
  assert(TrialExam.evaluateAnswer('B', 'A') == AnswerStatus.wrong);
  assert(TrialExam.evaluateAnswer(' ', 'A') == AnswerStatus.empty);
  assert(TrialExam.evaluateAnswer('*', 'A') == AnswerStatus.empty);
  assert(TrialExam.evaluateAnswer('.', 'A') == AnswerStatus.empty);

  debugPrint('All tests passed!');
}
