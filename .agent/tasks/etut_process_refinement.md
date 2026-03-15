# Etüt İşlemleri Screen Refinement Plan

## Objective
Refine the `EtutProcessScreen` to improve mobile responsiveness, visual aesthetics, and performance during user interactions (specifically selection of students/teachers).

## Changes Implemented

### 1. Visual Feedback for Unavailable Slots
- **File**: `etut_process_screen.dart`
- **Change**: Updated `_buildTimeGrid` to visually indicate blocked slots.
- **Details**: 
    - Blocked slots now have a `Colors.red.shade100` background.
    - Added a centered `Icons.block` icon to clearly signify unavailability.
    - Disabled `onTap` interaction for these slots.

### 2. Layout Restructuring (Responsive Design)
- **File**: `etut_process_screen.dart`
- **Change**: Refactored the main screen body to use a Top-Bottom layout instead of Left-Right.
- **Details**:
    - **Top Section**: Combined Student and Teacher selection panels side-by-side in a container with a fixed height (~320px). Used `Expanded` widgets to allow them to share horizontal space equally.
    - **Bottom Section**: The Calendar/Schedule table takes up the remaining vertical space using `Expanded`.
    - This layout ensures usability on narrower mobile screens where sidebars would be too cramped.

### 3. Selection Panel Optimization
- **File**: `etut_process_screen.dart`
- **Change**: Refined `_buildStudentPanel` and `_buildTeacherPanel`.
- **Details**:
    - **Compact Headers**: 
        - Replaced large "Temizle" text buttons with compact `Icons.cleaning_services_rounded` icons.
        - Reduced header font size to 14sp.
        - Wrapped titles in `Expanded` with `TextOverflow.ellipsis` to prevent overflow errors on small screens.
    - **List Items**:
        - Reduced primary text size to 12sp and subtitle to 10sp.
        - Enforced single-line text with ellipsis for names to maintain list density.

### 4. Performance Optimization (Silent Loading)
- **File**: `etut_process_screen.dart`
- **Change**: Optimized data fetching to prevent UI freezing/flickering.
- **Details**:
    - Updated `_loadClashData` to accept a named parameter `{bool silent = false}`.
    - When `silent` is true, the method skips setting `_isLoading = true`, preventing the full-screen progress indicator from appearing.
    - Updated `onTap` handlers in both student and teacher lists to call `_loadClashData(silent: true)`, enabling a smoother "optimistic UI" feel where the selection updates immediately while data fetches in the background.

## User Constraints Addressed
- **Blocked Slots**: Clearly distinct and unselectable.
- **Mobile Layout**: Usable table view by moving selection to top.
- **"Temizle" Button**: Replaced with a non-intrusive icon to save space.
- **Performance**: Eliminated the jarring "re-opening" effect (loading spinner) on every selection.
