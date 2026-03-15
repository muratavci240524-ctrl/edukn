# Implementation Plan - Student List Filter and UI Enhancements

## User Objectives
1.  **Fix Branch Filter**: Ensure Branch dropdown shows only "Ders Sınıfı" type classes and works correctly with Class Level selection.
2.  **Fix Student Filter**: Ensure Student list filters correctly by Class Level (digits matching).
3.  **Fix Parent Edit Crash**: Prevent app crash when opening the "Edit Parent" dialog.
4.  **Bulk Upload**: Verify Parent Name handling (logic confirmed as passing full name to 'name' field).

## Changes Implemented

### 1. Filter Logic (Enhanced)
- **Branch Loader**: 
    - Query now includes `.where('classTypeName', isEqualTo: 'Ders Sınıfı')` to filter only relevant branches.
    - Query fetches all active classes for the institution (detached from School Type filter initially to allow broader finding).
    - Client-side filtering applies School Type (if selected) and Class Level (using robust digit-matching).
- **Student Filter**:
    - `_filterStudents` logic normalizes both Student Data and Filter Value to digits only before comparing, solving the "8" vs "8. Sınıf" mismatch.

### 2. Parent Edit Crash Fix
- **Method**: `_editParentInForm`
- **Fix**: Added `.toString()` to all `TextEditingController` initializations (`tcNo`, `name`, `surname`, `phone`, `email`). This prevents crashes if the parent data map contains non-String values (e.g., integers from Excel) or unexpected nulls.

## Verification
- **Branch Filter**: Will now show "Tanımlı Ders Sınıfı" branches.
- **Parent Edit**: Will safely open the dialog even with Excel-imported numeric data.
