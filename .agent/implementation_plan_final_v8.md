# Implementation Plan - Resolution Status (v8)

## User Objectives
1.  **Fit Parent Name Single Field** (Updated): User explicitly requested "DO NOT SPLIT". The registration form and bulk upload must handle "Name Surname" as a single combined string.
2.  **Fix Parent Display**: The dash "-" issue on the specific parent card is fixed by ensuring `fullName` is populated and displayed.

## Changes Implemented

### 1. Bulk Upload (Reverted Split)
- **File**: `student_bulk_upload_dialog.dart`
- **Action**: Reverted the name splitting logic.
    - Logic: Stores the full string from Excel ("REZZAN KAVUK") into BOTH `name` and `fullName` fields.
    - `surname` is left empty.

### 2. Parent Edit Form (Restructured)
- **File**: `student_registration_screen.dart`
- **Action**: Completely refactored `_showEditParentDialog`.
    - **Removed**: Separate "Ad" and "Soyad" fields.
    - **Added**: Single "Ad Soyad (Tam İsim)" field.
    - **Logic**: Binds to `nameController`. On save, updates `name` and `fullName` with the full string. `surname` is saved as empty.

## Verification
- **Re-upload**: Please delete old test data and upload Excel again.
- **Check Form**: Click "Veli Düzenle". You should see a single field "Ad Soyad (Tam İsim)" populated with "REZZAN KAVUK".
- **Check Card**: The parent card should now show "REZZAN KAVUK" instead of "-".
