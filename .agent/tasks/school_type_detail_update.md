# School Type Detail Updates

## Objective
Update the "Rehberlik ve Portfolyo" section menu items in `SchoolTypeDetailScreen` as per user request.

## Changes Implemented

### 1. Menu Item Renaming
- **File**: `lib/screens/school/school_types/school_type_detail_screen.dart`
- **Change**: Renamed the menu item "Davranış ve Gözlem" to "Gözlem ve Etkinlik İşlemleri".
- **Location**: Within the `_buildCategoryContent` method, under the `case 'portfolyo'` block.

## Impact
- Users will now see "Gözlem ve Etkinlik İşlemleri" instead of "Davranış ve Gözlem" in the School Type Detail screen under the "Rehberlik ve Portfolyo" category.
- The functionality linked to this item (currently showing a "yakında eklenecek" message) remains unchanged as the routing logic in `_buildMenuItem` defaults to the generic message for unknown titles.
