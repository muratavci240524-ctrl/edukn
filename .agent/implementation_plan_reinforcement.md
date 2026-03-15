---
description: Implementation plan for Reinforcement Programs (Güçlendirme Programları) module
---

# Reinforcement Programs (Güçlendirme Programları)

## Objective
Enable school administrators to identify academic weaknesses at both branch and student levels and take actionable steps (creating reinforcement programs) to address them.

## Core Features

1.  **Reinforcement Dashboard (Main Screen)**
    *   **KPIs**: Active Programs, Completed Programs, At-Risk Students Count.
    *   **Navigation**: Tabs or Sections for "Branch-Based" and "Student-Based".

2.  **Branch-Based Reinforcement**
    *   **Weakness Detection**: Automatically identify subjects/topics where the class average is below a threshold (e.g., 50%).
    *   **Visualization**: List of branches with "Alert" badges for weak topics.
    *   **Action**: "Create Branch Program" (e.g., Remedial Class, Extra Homework).
        *   Fields: Topic, Subject, Scheduled Date, Assigned Teacher (optional), Description.

3.  **Student-Based Reinforcement**
    *   **Weakness Detection**: Identify students performing significantly below class average or improving trends.
    *   **Visualization**: Ranking or List of students needing attention.
    *   **Action**: "Create Individual Plan" (e.g., specialized task, parent meeting request).

4.  **Integration**
    *   Use `AssessmentService` to fetch exam results.
    *   Calculate aggregating stats on the fly (similar to CombinedExamResults).

## UI/UX Design
*   **Theme**: Consistent with existing "Premium" aesthetics (indigo/white/gray/glassmorphism).
*   **Components**:
    *   `ReinforcementDashboardScreen`: Main entry.
    *   `BranchWeaknessCard`: Shows branch name and list of weak topics.
    *   `StudentRiskCard`: Shows student name, branch, and specific weak points.
    *   `CreateProgramDialog`: Form to assign tasks.

## Step-by-Step Implementation

1.  **Scaffold**: Create `lib/screens/school/assessment/reinforcement/reinforcement_dashboard_screen.dart`.
2.  **Navigation**: Add entry point in `SchoolDashboardScreen`.
3.  **Data Logic**: Implement analytics to extract "Weak Topics" from `AssessmentService`.
4.  **UI Construction**:
    *   Build the TabView (Branch vs Student).
    *   Build the Analysis Cards.
    *   Build the Creation Dialogs.

## Future/Ideas
*   Track "Success Rate" of reinforcement programs (Did the score improve in the next exam?).
