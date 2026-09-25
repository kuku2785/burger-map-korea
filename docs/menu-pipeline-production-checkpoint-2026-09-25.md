# Menu Pipeline production checkpoint — 2026-09-25

## Repository and production state

- Branch before checkpoint: `nearby-store-sort`
- Pre-checkpoint HEAD: `c1931068f56864d07b0120e241e1cb252445ff89`
- Production project: `burger-map-korea-dev`
- Migration `20260924140656_menu_evidence_v1` applied to Production.
- Last verified Production counts: stores 280; verified and active stores 237; `public.menus` 4; `burger_map_private.menu_evidence` 5.

## First public menus

All four menus have a NULL price. Only the N버거 menu is marked as a signature menu.

| Store | Menu | Signature |
| --- | --- | --- |
| 더백테라스 신용산점 | 더백버거 | false |
| 브루클린더버거조인트 가로수길점 | SET_브루클린 웍스 140g | false |
| 브루클린더버거조인트 가로수길점 | SET_브루클린 웍스 200g | false |
| N버거 | 서울 불고기 버거 | true |

## Verification completed

- Android E2E on SM-N981N (Android 13): public menu display at all three stores; the two Brooklyn menus appear in order without duplicates; N버거 signature indication; NULL prices display as `가격 정보 없음`; empty-menu state; rapid store switching without stale menu data; guest map, search, detail, and favorite flow.
- `flutter analyze --no-pub`: PASS.
- `flutter test --no-pub`: 325/325 PASS.
- Python data tests: 254/254 PASS.
- Production mutation during Android E2E: 0.

## Remaining work

- Authenticated JWT menu REST test was not run.
- Menu coverage expansion is pending.
- Release build and Play signing were outside this checkpoint. This checkpoint does not establish release readiness.
