# Implementation Plan - Fixes for Crash, Empty Name, and Branch Filter

## User Objectives
1.  **Fix Parent Edit Crash**: Prevent the "Red Screen" (Dropdown Value Assertion Error) when editing a parent.
2.  **Fix Parent Name Empty**: Ensure Excel-uploaded parent names are correctly parsed even if column mapping is tricky.
3.  **Fix Branch Filter**: Ensure "Ders Sınıfı" type branches are correctly filtered and shown.

## Changes Implemented

### 1. Robust Parent Edit Dialog
- **File**: `student_registration_screen.dart`
- **Method**: `_editParentInForm`
- **Problem**: The dialog (or underlying data structure) had a mismatch where "Anne" (Capitalized) was being passed to a Dropdown expecting "anne" (lowercase key), causing a Flutter Assertion Error (Red Screen).
- **Fix**:
    - Rewrote the dialog to explicitly use a `DropdownButtonFormField`.
    - Added normalization logic: `value.toString().toLowerCase()`.
    - Validated the value against the allowed list (`validRelations`). If not found (e.g. "Veli"), it defaults to "diger" to prevent crashes.
    - Used `StatefulBuilder` to handle dropdown state changes correctly within the Dialog.

### 2. Branch Filter Logic
- **File**: `student_registration_screen.dart`
- **Fix**:
    - Re-implemented the "Ders Sınıfı" filter but using **Client-Side Filtering** in Dart instead of Firestore Query.
    - This allows fetching all active classes first, then filtering `classTypeName == 'Ders Sınıfı'` in memory.
    - This is more robust against Firestore index issues and allows easier debugging or loose matching if needed.

### 3. Parent Name (Previously Addressed)
- **File**: `student_bulk_upload_dialog.dart`
- **Fix**: Added dynamic Header Mapping to find the correct column for "Veli Ad Soyad". This relies on the user re-uploading the file.

## Verification
- **Edit Parent**: Clicking the edit pencil on a parent card should now open the dialog safely, with "Anne" correctly selected (as "Anne" label for "anne" key).
- **Branch Dropdown**: Should specifically list branches that are "Ders Sınıfı".
