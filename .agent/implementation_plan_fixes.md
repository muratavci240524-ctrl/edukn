# Implementation Plan - Student Bulk Upload & Filter Fixes

## User Objectives
1.  **Fix Parent Name Missing**: Resolve why "Veli Ad Soyad" is not being saved or displayed despite being in the Excel file.
2.  **Fix Branch Filter**: Ensure Branch dropdown populates correctly (currently showing empty).

## Changes Implemented

### 1. Robust Excel Parsing (Header Detection)
- **File**: `student_bulk_upload_dialog.dart`
- **Likely Cause**: The user's Excel file might have shifted columns or modified headers (e.g. deleting "Student Phone" column), causing hardcoded indexes to read wrong data (or empty columns).
- **Fix**: Implemented **Dynamic Header Mapping**.
    - The code now reads Row 0 (Headers).
    - It searches for keywords (e.g., "tc", "kimlik", "ad", "veli", "telefon") to map column names to indexes dynamically.
    - Fallback to standard indexes (0..12) is provided if headers are not found.
    - This ensures correct data extraction even if columns are reordered or removed.

### 2. Branch Filter Repair
- **File**: `student_registration_screen.dart`
- **Cause**: The previously added filter `.where('classTypeName', isEqualTo: 'Ders Sınıfı')` was too restrictive or data mismatch occurred, causing zero results.
- **Fix**: Removed the `classTypeName` filter from the Firestore query. The dropdown now works by fetching all active classes for the institution and filtering by "Class Level" client-side (using robust digit matching), ensuring all relevant branches are shown.

## Verification
- **Bulk Upload**: Uploading the Excel file should now correctly identify the "Veli Ad Soyad" column and populate the parent name.
- **Branch Dropdown**: Should now display branches.
