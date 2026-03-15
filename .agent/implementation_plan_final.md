# Implementation Plan - Final Fixes

## User Objectives
1.  **Fix Branch Filter**: Ensure branches are visible and filtered correctly by "Ders Sınıfı".
2.  **Fix Parent Name**: Ensure "Veli Ad Soyad" is detected even with loose header matching.
3.  **Fix Edit Crash**: Ensure "Veli Düzenle" works safely.

## Changes Implemented

### 1. Branch Filter (Relaxed)
- **File**: `student_registration_screen.dart`
- **Method**: `FutureBuilder` inside `_buildStudentList`
- **Fix**: Changed strict equality (`== 'Ders Sınıfı'`) to loose matching (`contains('Ders')`, case-insensitive). This handles potential encoding issues or minor naming variations (e.g. "Ders Sınıfi" vs "Ders Sınıfı").

### 2. Parent Name Header Detection (Expanded)
- **File**: `student_bulk_upload_dialog.dart`
- **Fix**: Updated header detection logic to:
    - Match if header contains "veli" AND ("ad" OR "isim").
    - Fallback: Match if header contains "veli" but NOT ("tc", "telefon", "yakınlık") and name hasn't been found found yet.
    - This covers cases like "Veli Adı", "Veli İsmi", or just "Veli" (first occurring column).

### 3. Parent Edit Robustness (Verified)
- **File**: `student_registration_screen.dart`
- **Fix**: Reconfirmed that `_editParentInForm` uses `DropdownButtonFormField` with safe value normalization (`toLowerCase()`) and fallback to "diger" if the relation is unknown. This specifically fixes the "Anne" vs "anne" crash.

## Verification
- **Branch Filter**: The dropdown should now populate with any class containing "Ders" in its type title.
- **Parent Name**: Re-uploading the Excel should now catch the name column.
- **Edit**: Editing a parent should open the dialog without crash.
