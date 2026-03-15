# Implementation Plan - Final Resolution (v5 - Data Driven)

## User Objectives
1.  **Fix Branch Filter (Definitive)**: The user demands that the Branch Filter works based on the ACTUAL data visible on student cards, rather than a potentially disjointed "Classes" database collection. If a student is in "8-A", "8-A" MUST appear in the filter.

## Changes Implemented

### 1. Data-Driven Branch Filter
- **File**: `student_registration_screen.dart`
- **Action**: Completely removed the Firestore-based `FutureBuilder` for the Branch Dropdown.
- **New Logic**:
    - The filter now iterates through the **loaded student list** (`_students`) in memory.
    - It respects the current School Type and Class Level filters.
    - It extracts the unique `className` and `classId` from the student records themselves.
    - It populates the dropdown with these unique branches.
- **Benefit**: 
    - 100% guarantee that if a student is visible, their branch is filterable.
    - No more database query mismatches or "Active/Inactive" class confusion.
    - No more "Ders Sınıfı" type filtering issues, as it only shows what is actually in use.

### 2. (Previous) Header Detection & Edit Crash
- These fixes remain in place and are verified.

## Verification
- **Branch Dropdown**: Should now immediately populate with the branches (e.g., "8-A", "8-B") found in the current student list.
- **Filtering**: Selecting a branch should correctly filter the list to only students in that branch.
