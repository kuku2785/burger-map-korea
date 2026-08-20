# Phase 3C 매장 검수 및 게시 워크플로

## 범위

Phase 3C-A는 24개 staging 매장을 사람이 검수할 표와, 검수 완료 행만 Supabase SQL Editor에 전달할 수 있는 오프라인 SQL 생성기를 만든다. 원격 Supabase 접속, 데이터 업로드, Flutter 쓰기 기능은 포함하지 않는다.

실제 원격 쓰기는 Phase 3C-B에서 사용자가 게시 대상을 최종 승인한 뒤 수동으로만 수행한다.

## 안전한 작업 순서

1. `data/staging/yongsan_burger_stores_staging.csv`와 보류 보고서를 기반으로 게시 검수표를 생성한다.
2. 사용자가 각 매장의 영업 상태, 버거 전문성, 이름, 주소, 좌표와 출처 기준일을 직접 확인한다.
3. 검수표에 판단과 근거를 기록한다. 확인 전에는 `pending`과 `false`를 유지한다.
4. 사용자가 게시 대상을 최종 승인한 뒤 SQL 생성기를 실행한다.
5. 생성 SQL의 행 수와 내용을 다시 검토한다.
6. Phase 3C-B 승인 후 사용자가 Supabase SQL Editor에서 transaction SQL을 수동 적용한다.
7. `stores` 행 수, RLS 공개 조회, Flutter 지도와 상세 카드를 확인한다.

## 게시 검수표

생성 명령:

```bat
C:\Users\jeong\AppData\Local\Programs\Python\Python312\python.exe scripts\data\build_store_publish_review.py
```

출력 파일은 `data/review/yongsan_burger_store_publish_review.csv`이며 Git에서 제외된다. 최초 생성 시 외부 장소 ID와 무관한 UUIDv4 `storeId`를 부여한다. 같은 출력 파일을 다시 생성하면 `candidateId`가 같은 행의 `storeId`와 수동 검수 필드를 보존한다. staging의 이름·주소·좌표·출처 유형이 바뀌면 기존 판단을 잘못 승계하지 않도록 생성을 중단한다.

보류 보고서의 다음 4개 매장은 24행 게시 검수표에 포함하지 않는다.

- 다운타우너 한남
- 잭잭
- 버거운녀석들
- 로스니버거

## 검수표 입력 규칙

| 필드 | 입력 규칙 |
| --- | --- |
| `storeId` | 생성기가 부여한다. 수정하지 않는다. |
| `candidateId` | 로컬 대조용 식별자다. 수정하지 않으며 DB에 게시하지 않는다. |
| `name` | 현재 영업 중인 매장명과 일치하는지 확인한다. |
| `address` | 현재 실제 영업 주소와 좌표가 일치하는지 확인한다. |
| `latitude`, `longitude` | 주소와 마커 위치를 직접 확인한다. |
| `burgerStyle` | 확인된 분류만 입력한다. 확인되지 않으면 빈 값으로 둔다. |
| `sourceType` | 생성된 `mixed` 또는 `manual_review`를 유지한다. |
| `sourceAsOf` | 확인한 원천 정보의 기준일을 `YYYY-MM-DD`로 입력한다. API 조회 시각을 임의로 넣지 않는다. |
| `publishDecision` | `pending`, `needs_recheck`, `verified`, `rejected`, `hold` 중 하나다. |
| `isActive` | 실제 공개 대상만 `true`다. `verified` 이외에는 반드시 `false`다. |
| `verifiedAt` | `verified`일 때 시간대가 포함된 ISO 8601 시각을 입력한다. |
| `verificationNote` | 확인 방법과 판단 근거를 짧고 구체적으로 기록한다. |

검수 완료 예시:

```text
sourceAsOf=2026-08-18
publishDecision=verified
isActive=true
verifiedAt=2026-08-18T15:30:00+09:00
verificationNote=공식 안내와 현장 지도 위치를 대조해 영업 상태, 주소, 좌표를 확인함.
```

예시는 형식 설명일 뿐 실제 매장 승인 기록이 아니다. 날짜와 메모는 각 매장을 실제로 확인한 값으로 입력한다. 불명확하면 `needs_recheck`, `false`, 빈 `verifiedAt`을 사용한다.

## 출처 유형 변환

staging의 로컬 조합값은 DB의 migration 제약에 맞게 다음처럼 변환한다.

- `semas_kakao` → `mixed`
- `kakao` → `manual_review`

외부 Place ID, 외부 URL, `candidateId`, 검수 메모는 `public.stores` INSERT에 포함하지 않는다.

## 게시 SQL 생성

검수 완료 후 실행한다.

```bat
C:\Users\jeong\AppData\Local\Programs\Python\Python312\python.exe scripts\data\generate_store_publish_sql.py
```

생성기는 migration에서 `stores` 컬럼, `verification_status`, `source_type` 허용값을 읽는다. 전체 검수표의 UUID, 상태, 활성값, 필수값, 좌표, 중복 의심을 먼저 검사한 뒤 `publishDecision=verified`이고 `isActive=true`인 행만 명시적 컬럼 INSERT로 만든다.

버거 스타일 검수가 끝난 뒤 새 게시 SQL을 생성할 때는 `--style-review data/review/yongsan_burger_style_review.csv`를 선택적으로 전달할 수 있다. `approved` 스타일만 `burger_style`에 사용하며 다른 스타일은 `unclassified`로 둔다. 이 결합은 게시 검수표의 `publishDecision`과 `isActive`를 변경하거나 pending 매장을 INSERT 대상으로 추가하지 않는다.

`sourceAsOf`, 시간대가 있는 `verifiedAt`, `verificationNote` 중 하나라도 없으면 중단한다. 승인 대상이 0개이면 `data/staging/yongsan_burger_store_publish.sql`을 만들지 않고 종료 코드 3으로 안전 중단한다. 출력 SQL은 Git에서 제외되며 `begin`/`commit` transaction을 사용한다.

## URL과 REST 경로

Flutter SDK 설정의 `SUPABASE_URL`에는 다음 형태의 Project URL만 사용한다.

```text
https://<project-ref>.supabase.co
```

`/rest/v1`은 SDK가 내부에서 추가하는 REST endpoint이므로 Project URL에 직접 붙이지 않는다. 실제 URL, 프로젝트 식별자, Publishable Key, secret/service-role 키, DB 비밀번호는 검수표·SQL·문서에 기록하지 않는다.

## Phase 3C-B 전 확인

- 24개 매장을 한 행씩 사람이 검수했는가
- 게시 대상만 `verified + true`인가
- 모든 게시 대상에 `sourceAsOf`, `verifiedAt`, `verificationNote`가 있는가
- 보류 4개가 게시 대상에서 제외됐는가
- 생성 SQL의 행 수가 사용자 최종 승인 수와 같은가
- SQL에 외부 Place ID, URL, 키, 로컬 `candidateId`가 없는가
- Supabase SQL Editor 적용 직전 DB가 예상 상태인지 다시 확인했는가

Phase 3C-A 완료 시점에는 24개 모두 `pending + false`이며 실제 게시 SQL과 원격 데이터 변경은 없었다.

## Phase 3C-B 실제 게시 검증

2026-08-18 사용자가 24개 검수 후보 중 직접 승인한 매장 1곳만 게시 대상으로 변경했다. 나머지 pending 23곳과 보류 4곳은 승인하거나 게시하지 않았다.

확인된 전체 흐름은 다음과 같다.

```text
사람 검수
→ reviewed CSV
→ 안전 검증
→ 게시 SQL 생성
→ 사용자 SQL Editor 적용
→ Supabase RLS 공개 SELECT
→ Flutter 지도 마커 및 상세 카드 표시
```

사용자가 개발용 Supabase SQL Editor에서 생성 SQL을 정확히 한 번 실행했고 `Success. No rows returned` 결과를 확인했다. 이후 원격 상태는 다음과 같았다.

- `stores` 테이블: 0행에서 1행으로 변경
- 게시 매장: 노머시버거 1곳
- `verification_status = verified`
- `is_active = true`
- RLS 활성화 상태 유지
- pending 23곳 미게시
- 보류 4곳 미게시

Flutter를 development + supabase 모드로 실행해 Google 지도, Supabase 매장 마커 1개, 마커 선택, 이름과 주소 상세 카드를 사용자가 육안으로 검증했다.

로컬 reviewed CSV와 생성 SQL은 Git에 포함하지 않는다. 저장소에는 생성기, migration 기반 검증 로직, 합성 fixture, 테스트와 운영 문서만 기록한다.

## 비활성화 운영 원칙

게시 매장에 폐업, 이전, 잘못된 정보 또는 긴급한 비노출 사유가 발생하면 행을 삭제하거나 Flutter에서 숨김 목록을 만들지 않는다. 권한 있는 관리자가 SQL로 해당 행의 `is_active`를 `false`로 변경해 RLS 공개 SELECT에서 제외한다.

변경 전에는 대상 내부 UUID와 현재 상태를 확인하고, 변경 후에는 다음을 다시 검증한다.

- 해당 행은 DB에 감사 가능한 상태로 남아 있음
- `is_active = false`
- 익명 공개 SELECT 결과에서 제외됨
- Flutter 지도에서 마커가 사라짐

공개 Flutter 클라이언트에는 INSERT, UPDATE, DELETE, UPSERT, RPC 또는 관리자 키를 추가하지 않는다.

Phase 4C-B2에서 현재 게시된 매장의 스타일만 반영하기 위한 오프라인 UPDATE SQL 생성기를 추가했다. 스타일 검수표의 `approved`와 게시 검수표의 `verified + active`가 UUID·candidateId·이름·주소까지 일치할 때만 `burger_style`을 갱신한다. 생성 SQL은 사용자가 내용을 검토한 뒤 SQL Editor에서 수동 적용하기 전까지 원격 상태에 영향을 주지 않는다.

2026-08-20 사용자가 생성 SQL을 개발용 SQL Editor에서 정확히 한 번 실행했다. 대상은 기존에 게시된 노머시버거 1행뿐이었고 `burger_style`만 `classic`으로 변경했다. `verification_status=verified`, `is_active=true`와 RLS는 유지됐으며 INSERT, DELETE, UPSERT, 다른 매장 변경은 없었다. development + supabase 모드에서 `전체·클래식` 필터와 상세 화면의 `클래식·검수 완료` 표시를 확인했다. 이미 적용된 SQL은 재실행하지 않는다.

## 연결 설정 주의사항

`SUPABASE_URL`에는 `/rest/v1`이 없는 Project URL만 사용한다. Phase 3B에서 확인된 `PGRST125`의 원인은 Project URL에 `/rest/v1`을 포함해 SDK가 중복 REST 경로를 생성한 것이었다. 실제 Project URL, 프로젝트 식별자, API 키, JWT, service-role 키와 DB 비밀번호는 저장소나 문서에 기록하지 않는다.
