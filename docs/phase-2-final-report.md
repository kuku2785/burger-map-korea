# Phase 2 Final Report

## Scope

Phase 2 validated a local data workflow for displaying reviewed burger-store candidates on Google Maps without promoting them to production data.

- Phase 2.0: Added three manually checked Itaewon pilot stores and validated markers and the existing preview card.
- Phase 2.1: Extracted and manually screened Yongsan burger candidates from public commercial-store data, then used Kakao Local search only as a supplementary discovery and comparison source.
- Phase 2.2: Integrated the review results into a local staging dataset and loaded 24 pending stores in the Flutter Android debug app.

## Final Staging State

- Staging stores: 24
- Linked SEMAS and Kakao candidates: 14
- Kakao-only pending candidates: 10
- Held for additional review: 4
- Verification status of all staging stores: `pending`
- Automatically promoted `verified` stores: 0

The four held stores remain outside the Flutter staging dataset because their current address or operating status needs further confirmation. They were not changed to `verified` or `rejected`.

## Runtime Safety

The default `STORE_DATA_MODE` is `pilot`, which keeps the existing three-store pilot dataset.

The 24-store local asset is selected only when both conditions are met:

```text
APP_ENV=development
STORE_DATA_MODE=staging
```

Production environments and release builds block staging mode and fall back to pilot data. The generated development JSON is local-only and excluded from Git.

## Manual Android Verification

- Verification date: 2026-08-14
- Device: Android emulator `emulator-5554`
- Result: completed

The following behaviors were manually confirmed:

- Google Maps tiles rendered successfully.
- Staging store markers were visible.
- Different markers could be selected.
- The selected store name and address appeared in the preview card.
- Tapping an empty map area closed the preview card.
- Map zoom and camera movement worked.
- No obvious duplicate marker or clearly incorrect location was observed.

## Data and Release Status

Phase 2 data remains a development and staging test dataset. It has not been promoted to production, written to Supabase, or exposed as verified store data.

The repository contains transformation code and synthetic test fixtures. Local public-data files, review CSVs, staging CSVs, generated Flutter JSON, API responses, external place identifiers used in manual decision files, API keys, APKs, and build outputs remain excluded from Git.
