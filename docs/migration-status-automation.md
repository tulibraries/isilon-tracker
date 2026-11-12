# Migration Status Automation Rules

## Overview

The CSV data ingestion service now includes automated migration status assignment to reduce manual review requirements. Rules are processed in order, and the first matching rule applies to each asset.

## Rules Summary

### Rule 1: Migrated Directories
**Condition:** 
- Directory is in `/deposit/`
- Directory name contains "- Migrated" (case-insensitive)
- Directory is NOT in born-digital area (`/deposit/SCRC Accessions`)

**Action:** Assign migration status "Migrated" to all assets within that directory

**Example paths that trigger this rule:**
- `/deposit/photo-collection - Migrated/image.jpg`
- `/deposit/manuscripts/series-1 - Migrated/document.pdf`

### Rule 2: DELETE Directories in Born-Digital Areas
**Condition:**
- Directory is in `/deposit/SCRC Accessions`  
- Directory contains the string "DELETE" (case-insensitive)

**Action:** Assign migration status "Don't migrate" to all assets within that directory

**Example paths that trigger this rule:**
- `/deposit/SCRC Accessions/collection-DELETE/file.pdf`
- `/deposit/SCRC Accessions/DELETE-temp-files/document.txt`

### Rule 3: Duplicate Assets Outside Main Areas
**Status:** Handled by separate duplicate detection task (not during CSV import): https://tulibdev.atlassian.net/browse/IMT-142

**Condition:**
- Asset has a duplicate (checksum matches another asset)
- Current asset is NOT in main areas (`media-repository` or `deposit`)
- Duplicate IS located in `media-repository` or `deposit`

**Action:** Assign migration status "Don't migrate" to the asset outside main areas

**Note:** This rule is implemented as a separate post-processing task that runs after CSV import for better performance and more sophisticated duplicate analysis.

### Rule 4: Unprocessed Files with Processed Equivalents
**Condition:**
- Directory is in `/deposit/`
- Directory is NOT in born-digital area (`/deposit/SCRC Accessions`)
- Asset is in subdirectory named "UNPROCESSED" or "RAW"
- Asset is a TIFF file (.tiff or .tif)
- Count of TIFF files in sibling "PROCESSED" directory equals count in "UNPROCESSED"/"RAW"

**Action:** Assign migration status "Don't migrate" to all assets in the "UNPROCESSED"/"RAW" directory

**Note:** This rule runs as post-processing after all assets are imported to compare file counts.

## Implementation Details

### Files Modified
- `app/services/sync_service/assets.rb` - Main implementation

### Key Methods Added
- `apply_automation_rules(row)` - Main rule processing logic (Rules 1 & 2)
- `rule_1_migrated_directory?(path)` - Rule 1 logic
- `rule_2_delete_directory?(path)` - Rule 2 logic  
- `apply_rule_4_post_processing()` - Post-processing for Rule 4
- `find_parent_dirs_with_matching_tiff_counts()` - Database-optimized Rule 4 analysis
- `extract_parent_directory(path)` - Extract parent directory for TIFF comparison
- `extract_subdirectory_type(path)` - Determine processed/unprocessed type
- `mark_unprocessed_tiffs_as_dont_migrate(parent_dir, count)` - Bulk update for Rule 4

**Note:** Rule 3 duplicate detection methods have been moved to a separate duplicate detection service.

### Logging
When logging is enabled, all rule applications are logged with details about which rule was applied and to which asset path. This provides an audit trail for automated decisions.

### Performance Considerations
- Rules 1 and 2 are lightweight string operations during CSV processing
- Rule 3 is handled by separate duplicate detection task for better performance
- Rule 4 runs as post-processing using database-optimized ActiveRecord queries
- CSV processing uses streaming with lazy evaluation for memory efficiency
- Batch processing (1000 rows per batch) with bulk database inserts
- Garbage collection triggered periodically during large imports

## Usage

The automation runs automatically when using the CSV import service:

```bash

# Test with a sample CSV (make sure it exists)
rails "sync:assets[scan_output.applications-backup.csv]"

```

## Migration Status Mappings

The automation uses these existing migration statuses:
- "Migrated" - For Rule 1
- "Don't migrate" - For Rules 2 and 4 (during CSV import), Rule 3 (via separate task)
- "Needs review" (default) - When no automation rules apply during CSV import

**Note:** Rule 3 duplicates will initially get "Needs review" status during CSV import, then updated to "Don't migrate" by the separate duplicate detection task.

## Testing

```bash

rspec spec/services/sync_services/assets_spec.rb

```
