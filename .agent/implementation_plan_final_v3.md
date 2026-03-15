# Implementation Plan - Final Resolution
## User Objectives
1.  **Show All Relevant Branches**: Remove any "Class Type" filtering to ensure the user sees all branches, regardless of how they are named types in the system.
2.  **Fix Parent Name Parsing**: Ensure Excel upload correctly identifies the header row (even if it's not the first row) and finds the parent name column.
3.  **Fix Parent Edit Crash**: Ensure "Anne" (capitalized) does not crash the dropdown expecting "anne" (lowercase).

## Changes Implemented

### 1. Branch Filter Removed
- **File**: `student_registration_screen.dart`
- **Action**: Completely removed the client-side filter `list = list.where...`.
- **Result**: The "Branch" dropdown will now display **ALL active branches** belonging to the selected institution (and school type if selected), filtered only by Class Level (e.g., "8" vs "8. Sınıf" match). We rely on the user to pick the correct one.

### 2. Smart Header Detection
- **File**: `student_bulk_upload_dialog.dart`
- **Action**: Implemented a scanning loop that checks the first 10 rows of the Excel file to find the real header row (containing "TC", "Kimlik", "Ad", etc.).
- **Result**: Even if the Excel file has empty rows at the top or title rows, the system will correctly lock onto the header row and map columns dynamically. This ensures "Veli Ad Soyad" is found correctly.

### 3. Parent Edit robustness (Confirmed)
- **File**: `student_registration_screen.dart`
- **Action**: The `_editParentInForm` method now normalizes the existing relation value (e.g. "Anne" -> "anne") before setting the dropdown state, preventing the red screen crash.

## Verification
- **Branches**: Dropdown should now show a full list of branches.
- **Upload**: Re-uploading the Excel should populate Parent Names correctly thanks to smart header detection.
- **Edit**: Editing a parent should be safe.
