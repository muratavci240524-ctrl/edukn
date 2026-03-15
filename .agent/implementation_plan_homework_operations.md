# Homework Operations Module Implementation Plan

## Overview
Create a comprehensive homework tracking and statistics screen (`HomeworkOperationsScreen`) for administrators. The goal is to monitor homework assignments, completion rates, and identify at-risk students.

## User Requirements
1.  **Weekly Tracking**: List homeworks assigned in the current week (Teacher, Class, Lesson).
2.  **General Statistics**: Total assigned homeworks summary.
3.  **Teacher Statistics**: Break down by teacher (Assigned, Graded, Completed).
4.  **Student Statistics**:
    *   List students who haven't done homework.
    *   Filter by "Consecutive X homeworks missed".
    *   Filter by date range and lesson.
5.  **Design**: Premium, chart-based, slick UI.

## Components

### 1. `HomeworkOperationsScreen` (Main Entry)
*   **Path**: `lib/screens/school/homework/homework_operations_screen.dart`
*   **Layout**:
    *   Top Bar: Date range picker (Default: Current Week), Global Stats Cards.
    *   Tabs or Sections:
        *   "Genel Bakış" (Overview): Weekly List & Charts.
        *   "Öğretmen Analizi" (Teacher Stats): Detailed teacher table/list.
        *   "Öğrenci Analizi" (Student Stats): Filters and risk list.

### 2. Services & Models
*   **Service**: `HomeworkStatisticsService` (New)
    *   `getWeeklyHomeworks(institutionId, startDate, endDate)`
    *   `getTeacherStats(institutionId, startDate, endDate)`
    *   `getStudentRiskList(institutionId, consecutiveMissedCount)`
*   **Data Aggregation**: Since Firestore aggregation can be expensive, we will fetch `homeworks` collection filtered by date and aggregate in-memory for the MVP.

### 3. Sub-Components
*   **`HomeworkWeeklyList`**: A sleek list showing recent assignments.
*   **`TeacherPerformanceCard`**: Card showing teacher name, total assignments, and completion rate.
*   **`StudentRiskFilter`**: UI to select "Consecutive Missed Count" (Slider or Dropdown: 2, 3, 5, etc.).
*   **`RiskStudentList`**: List of students matching the risk criteria.

## Implementation Steps

1.  **Create Service**: `lib/services/homework_statistics_service.dart`.
2.  **Create Main Screen**: `lib/screens/school/homework/homework_operations_screen.dart`.
3.  **Implement Overview Tab**:
    *   Fetch homeworks for the selected week.
    *   Display "Total Homeworks", "Completion Rate" cards.
    *   Display a list of homeworks grouped by day or class.
4.  **Implement Teacher Stats Tab**:
    *   Group fetched homeworks by `teacherId`.
    *   Calculate stats per teacher.
    *   Show in a sortable list/table.
5.  **Implement Student Stats Tab**:
    *   This is the most complex part.
    *   Need to fetch `homeworks` and iterate through `studentStatuses`.
    *   Algorithm:
        *   Fetch all homeworks for the target class/lesson or general.
        *   Sort by date desc.
        *   For each student, count consecutive `notCompleted` or `missing`.
    *   This might be heavy if done for the WHOLE school. **Constraint**: Force filter by Class Level or specific Class first to avoid fetching too much data? Or fetch strictly by date range (e.g. last 1 month).
    *   *Decision*: For "Consecutive Missed", we need history. We'll limit the "Lookback" period (e.g. last 20 homeworks per class).

## Dependencies
*   `fl_chart`: For graphs (Pie chart for completion rates, Bar chart for teacher activity).
*   `intl`: For date formatting.

## Refinement
*   **Data Structure**: `Homework` model has `studentStatuses` (Map<String, int>).
    *   Index 0: pending
    *   Index 1: completed
    *   Index 2: notCompleted
    *   Index 3: missing
    *   Index 4: notBrought
*   **Risk Logic**: Check for values 2, 3, 4 as "Negative".

