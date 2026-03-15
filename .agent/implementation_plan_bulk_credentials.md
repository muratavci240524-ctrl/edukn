# Implementation Plan - Student Bulk Upload Enhancements

## User Objectives
1.  **Auto-Generate Credentials**: Automatically generate `username` and `password` for students during Excel bulk upload using the last 6 digits of their TC Identity Number.

## Changes Implemented

### 1. Username/Password Generation
- **File**: `student_bulk_upload_dialog.dart`
- **Method**: `_processSingleStudent`
- **Logic**:
    - Extracted the last 6 digits of `tcNo`.
    - Assigned this value to both `studentData['username']` and `studentData['password']`.
    - Added fallback to full `tcNo` if length is less than 6 (defensive).
    - Ensures that every student uploaded/updated via Excel receives these credentials, facilitating immediate login access.

## Verification
- **Bulk Upload**: When a new Excel file is processed, the resulting student documents in Firestore will contain `username` and `password` fields derived from their TC No.
