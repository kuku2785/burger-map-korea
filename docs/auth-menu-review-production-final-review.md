# Auth/Menu/Review Production Apply Final Review

감사일: 2026-09-22 (KST). 판정: **AUTH_MENU_REVIEW_PROD_APPLY_BLOCKED**.

이번 감사는 운영 읽기 전용 조회, 기존 로컬 DB의 읽기 전용 증거 점검, SQL/테스트 소스 검토에 한정했다.
새 migration 적용, fixture 생성, 테스트 수정, 운영 DDL/DML/GRANT/REVOKE, Auth 설정 변경은 하지 않았다.
직전 `AUTH_MENU_REVIEW_MIGRATION_LOCAL_READY` 보고의 **전체 필수 보안 검증 완료라는 해석을 정정한다**.
일부 SQL/REST 계약의 과거 PASS는 확인되지만, 아래 필수 테스트 누락과 테스트 자체 결함 때문에 운영 적용 승인 근거로는 부족하다.

## Environment

| 항목 | 이번에 확인한 결과 |
| --- | --- |
| branch | `nearby-store-sort` |
| HEAD | `ac89e13576521d81cc4a77933be321c2b823cd8e` |
| CLI | `npx.cmd --offline supabase --version`: 2.117.0 |
| 운영 project | `burger-map-korea-dev` / `eoiwfprghyyguthdtayx` |
| region / 상태 | `ap-northeast-2` / `ACTIVE_HEALTHY` |
| PostgreSQL | 운영 SQL `server_version=17.6`; 프로젝트 상세 17.6.1.155; 로컬 SQL 17.6 |
| 운영 조회 | 연결된 Supabase 도구의 project/migrations/SELECT/security advisor와 CLI migration list |
| 로컬 조회 | `supabase_db_local-auth-menu-review-fresh-20260922`, `psql -X -v ON_ERROR_STOP=1`, READ ONLY transaction |
| 쓰기 테스트 재실행 | 이번에는 미실시. 감사 요청에 따라 이전 테스트의 증거/누락을 검토 |
| production changes | **NONE** — 앱 데이터·schema·RLS·grants·Auth·migration 이력 변경 없음 |

초기 일반 npx 호출은 sandbox 네트워크 제한으로 실패했다. 기존 캐시의 CLI를 offline으로 실행해 버전/도움말/이력 조회를 완료했으며 dependency 설치·업그레이드는 하지 않았다.
전용 로컬 DB/Auth/REST는 실행 중이다. 로깅용 vector 컨테이너는 재시작 중으로 관찰되었으나 이를 SQL/RLS 실패로 분류하지 않았다. 이번에 컨테이너를 시작·중지·삭제하지 않았다.

## Repository integrity

migration 디렉터리는 정확히 두 파일이다. 예상 밖 migration과 ordering 문제는 없다.

| 파일 | 검증 |
| --- | --- |
| `0001_init_store_schema.sql` | HEAD와 working file의 Git blob 모두 `e8efea141ef7ef8204a1242730dacbc193ab02d0`. 수정 없음 |
| `20260922050439_auth_menu_reviews.sql` | 기존 untracked migration. 이번 수정 없음. 로컬 검증 프로젝트의 복사본과 SHA256 일치 |

신규 migration SHA256:
`1AE4E499A51742501531308C7E1B393063B1C8E2DC07C99A17A2C31E3E4DE35F`.

기존 0001 SHA256:
`0CC5D7D49252E6229B9600C16399A7700E7CCB64B9C63AB219ED4E3E7656305D`.

신규 파일 전체 139행을 검토했다. 4개 새 테이블, 5개 명시 인덱스, 2개 함수, 4개 trigger,
11개 정책, 2개 view 및 권한 문장으로 구성된다.
`ALTER TABLE public.stores`, 기존 stores 데이터 변경, 기존 stores 정책/함수 교체는 없다.
새 FK는 stores에 참조 의존성과 parent 측 내부 FK trigger를 추가하므로 영향이 전혀 없다고 표현하지 않는다.

## Migration History

운영 MCP migration 목록과 다음 CLI 읽기 전용 조회가 일치했다:

`npx.cmd --offline supabase migration list --project-ref eoiwfprghyyguthdtayx`

| version | repository | 운영 | 기존 fresh 로컬 DB |
| --- | --- | --- | --- |
| 0001 | 있음 | applied, init_store_schema | applied, 8 statements |
| 20260922050439 | 있음 | **not applied** | applied, auth_menu_reviews, 51 statements |

remote 0001 누락, 추가 remote migration, 신규 migration 선적용, 이력 divergence는 발견하지 못했다.
이번에 fresh reset 또는 migration을 다시 실행한 것은 아니다. 기존 로컬 이력을 직접 조회했고 파일 해시를 대조했다.

## Production Baseline

운영 `public.stores`에 실제 SELECT aggregate를 실행한 결과다. 이전 보고 숫자를 재사용하지 않았다.

| 검사 | 기대 | 실제 |
| --- | ---: | ---: |
| 전체 | 280 | 280 |
| verified + active | 237 | 237 |
| rejected | 43 | 43 |
| verified + verified_at NULL | 0 | 0 |
| non-verified + active | 0 | 0 |
| 공개 required-field 실패 | 0 | 0 |
| 공개 위도/경도 범위 실패 | 0 | 0 |
| 공개 한국 범위 실패(위도 33–39, 경도 124–132) | 0 | 0 |
| stores 열 수 | 13 | 13 |
| client write policy | 0 | 0 |

required-field 검사는 id/name/address/source_type/verified_at의 NULL 및 필수 문자열 공백을 검사했다.
좌표 검사는 NULL과 전 지구 위경도 범위를 검사했으며 한국 범위도 별도로 확인했다.
매장 개별 좌표/이름/주소 원문은 보고서에 저장하지 않았다.

실제 role 전환을 포함한 READ ONLY transaction 결과:

| role | RLS 적용 | 보이는 전체 행 | 비공개 행 | SELECT | INSERT/UPDATE/DELETE |
| --- | --- | ---: | ---: | --- | --- |
| anon | true | 237 | 0 | 허용 | effective table/column grant 모두 거부 |
| authenticated | true | 237 | 0 | 허용 | effective table/column grant 모두 거부 |

쓰기 거부는 실제 운영 쓰기 시도 없이 effective privilege와 정책으로 확인했다.
두 client role 모두 superuser/bypassrls가 아니며 추가 inherited role membership은 없었다.
TRUNCATE/REFERENCES/TRIGGER 권한도 없다.

RLS enabled=true, force=false, owner=postgres.
정책은 `stores_public_read_verified_active` 하나이며 SELECT TO anon/authenticated,
`verification_status = 'verified' AND is_active = true` 조건이다.
13개 열의 이름/타입/nullable/default 및 9개 PK/CHECK 정의를 0001과 대조했다.
다음 객체도 실제 존재한다:

- `stores_public_map_coordinates_idx`: 같은 공개 조건의 좌표 partial index
- `set_stores_updated_at()`: SECURITY INVOKER, search_path=pg_catalog
- `stores_set_updated_at`: enabled, BEFORE UPDATE

기존 Flutter loader의 명시 SELECT 열
`id,name,address,latitude,longitude,burger_style,verification_status`,
verified/active 조건과 name 정렬을 유지한 SQL은 anon role에서 237건을 반환했다.
region은 기존 opt-in 경로이며 이번 migration에 추가되지 않는다.
Flutter 또는 production REST 요청을 이번 검사로 통과시켰다고 주장하지 않는다.

**중요한 기존 환경 차이:** 운영 service_role은 stores SELECT/INSERT/UPDATE/DELETE가 없다.
로컬 stores의 service_role에는 해당 권한이 있었다. 자세한 영향은 M1에 기록했다.

## Object Collision

운영 카탈로그를 직접 조회했다.

| proposed object | 운영 상태 |
| --- | --- |
| public.profiles | ABSENT |
| public.menus | ABSENT |
| public.reviews | ABSENT |
| public.review_reports | ABSENT |
| public.public_reviews | ABSENT |
| public.store_review_stats | ABSENT |
| burger_map_private schema | ABSENT |
| burger_map_private.can_contribute() | ABSENT (schema 및 해당 schema 함수 없음) |
| burger_map_private.set_updated_at() | ABSENT (동일) |
| 새 테이블 PK/UNIQUE 인덱스 이름 | ABSENT |
| 5개 명시 인덱스 이름 | ABSENT |
| 새 relation과 같은 이름의 public composite type | ABSENT |
| public.can_contribute / public.set_updated_at | ABSENT |

새 정책/trigger는 위의 신규 테이블에 속하므로 그 테이블이 없는 현재 상태에서 해당 위치 충돌은 없다.

**Data API exposed schemas:** UNKNOWN.
pg_db_role_setting에서 pgrst.db_schemas/db_extra_search_path 항목은 발견되지 않았다.
이는 PostgREST 외부 설정의 부재를 증명하지 않는다.
CLI config 도움말에는 diff/pull/push만 있었고, pull로 사용자 설정 파일을 생성하지 않았다.
설정 화면의 읽기 전용 확인을 시도했으나 브라우저 도구가 `No browser is available`을 반환했다.
적용 전에 Dashboard의 Data API → Settings → Exposed schemas 또는
Management API의 GET /v1/projects/{ref}/postgrest에서 **db_schema 필드만** 확인하여
burger_map_private가 노출 목록에 없음을 검증해야 한다. 응답 전체에는 secret 필드가 있을 수 있으므로 출력하지 않는다.

## Current documentation check

2026-09-22에 공식 자료를 다시 조회했다. changelog.md 조회 실패 후 HTML changelog를 확인했다.
최근 breaking change 중 이 SQL에서 사용하는 public 객체/PG17 invoker view를 금지하는 변경은 확인하지 못했다.
새 테이블 자동 권한 부여 설정은 프로젝트별 차이가 있으므로 실제 ACL을 우선했다.

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security):
  role과 행 소유권을 함께 검사해야 한다. UPDATE에는 SELECT 정책이 필요하다.
  WITH CHECK가 생략되면 USING이 대체되는 PostgreSQL 의미도 확인했으며, 이 migration의 두 UPDATE는 둘 다 명시한다.
- [Data API security](https://supabase.com/docs/guides/api/securing-your-api):
  객체 GRANT와 행 RLS는 별도 경계다. 명시 REVOKE 후 최소 권한을 부여하는 구성을 대조했다.
- [Column privileges](https://supabase.com/docs/guides/database/postgres/column-level-security):
  table-level 권한을 제거한 뒤 허용 열만 선택/수정해야 한다. SELECT *는 여기서 허용된 클라이언트 계약이 아니다.
- [Anonymous Auth](https://supabase.com/docs/guides/auth/auth-anonymous):
  anonymous Auth도 authenticated role이다. 역할만 검사하지 않고 서명된 is_anonymous claim을 검사해야 한다.
- [PostgreSQL 17 CREATE FUNCTION](https://www.postgresql.org/docs/17/sql-createfunction.html):
  definer 함수는 소유자 권한으로 동작하므로 안전한 search_path와 execute 제한을 검토했다.
- [PostgreSQL 17 CREATE VIEW](https://www.postgresql.org/docs/17/sql-createview.html):
  security_invoker는 호출자의 base-table 권한/RLS를 사용한다. 뷰 SELECT grant만으로 base-table 권한을 대신하지 않는다.
- [Migration workflow](https://supabase.com/docs/guides/deployment/database-migrations):
  순서·이력·대상 확인을 적용 전후에 수행한다. CLI 2.117.0 도움말의 --skip-vault도 확인했다.
- [PostgreSQL 17 CREATE TABLE](https://www.postgresql.org/docs/17/sql-createtable.html):
  FK 생성은 참조 테이블에 SHARE ROW EXCLUSIVE lock을 요구한다.
- [Changelog](https://supabase.com/changelog), [PostgREST 설정 읽기 API](https://supabase.com/docs/reference/api/v1-get-postgrest-service-config).

## Migration Static Audit

SAFE는 해당 문장의 정적 의미와 확인된 의존성이 타당하다는 뜻이며 전체 운영 승인과 다르다.
REVIEW는 테스트/운영 설정/삭제 정책/적용 경계 확인이 남은 문장이다.
확정된 Critical/High SQL defect에 해당하는 BLOCKER 문장은 발견하지 못했다.
전체 승인 gate에는 별도 blocker가 있다. 번호는 로컬 migration history의 실제 51개 statement 순서다.
모든 line은 신규 migration 기준이다.

| # | line | statement | 판정 | 근거 |
| ---: | ---: | --- | --- | --- |
| 1 | 1 | CREATE SCHEMA burger_map_private | REVIEW | 충돌 없음; 운영 API 비노출 확인 필요 |
| 2 | 2 | REVOKE schema ALL | SAFE | PUBLIC/anon/auth/service의 기본 권한 제거 |
| 3 | 3 | GRANT schema USAGE | SAFE | auth/service lookup만; CREATE 허용 없음 |
| 4 | 5 | CREATE profiles | REVIEW | auth.users PK FK, 닉네임 제약 일치; client 정상 생성 검증 누락 |
| 5 | 18 | CREATE menus | SAFE | stores RESTRICT, nullable nonnegative integer price |
| 6 | 36 | menus_store_order_idx | SAFE | 새 빈 테이블의 FK/정렬 인덱스 |
| 7 | 38 | CREATE reviews | REVIEW | UUID/FK/unique/내용/별점/운영 제약 타당; 경계·lifecycle 실행 누락 |
| 8 | 58 | reviews_public_store_created_idx | SAFE | nonhidden partial pagination index |
| 9 | 59 | reviews_user_created_idx | SAFE | 소유자 조회/FK 경로 |
| 10 | 61 | CREATE review_reports | REVIEW | reporter unique, reason/status 제약; cascade 운영 tradeoff |
| 11 | 82 | review_reports_reporter_idx | SAFE | 신고자 FK 경로 |
| 12 | 83 | review_reports_queue_idx | SAFE | 운영 큐 정렬 |
| 13 | 85 | CREATE can_contribute() | REVIEW | current caller만 조회, 고정 path; 노출 설정/검증 H2 |
| 14 | 93 | REVOKE helper EXECUTE | SAFE | PUBLIC/anon/auth/service 초기 execute 제거 |
| 15 | 94 | GRANT helper to authenticated | SAFE | 필요한 최소 execute, UUID 인수 없음 |
| 16 | 96 | CREATE set_updated_at() | SAFE | invoker, 고정 path, NEW 시각만 변경 |
| 17 | 102 | profiles trigger | SAFE | 새 테이블에만 연결 |
| 18 | 103 | menus trigger | SAFE | 동일 |
| 19 | 104 | reviews trigger | SAFE | 동일, 운영 변경도 updated_at을 바꿈 |
| 20 | 105 | reports trigger | SAFE | 새 테이블에만 연결 |
| 21 | 106 | REVOKE trigger function EXECUTE | SAFE | trigger 생성 후 직접 호출 권한 제거 |
| 22 | 108 | ENABLE profiles RLS | SAFE | 새 테이블만 |
| 23 | 109 | ENABLE menus RLS | SAFE | 새 테이블만 |
| 24 | 110 | ENABLE reviews RLS | SAFE | 새 테이블만 |
| 25 | 111 | ENABLE reports RLS | SAFE | 새 테이블만 |
| 26 | 112 | REVOKE new-table ALL | SAFE | 운영 default ACL 차이를 명시적으로 제거 |
| 27 | 113 | profiles SELECT columns | SAFE | id/nickname만 |
| 28 | 114 | profiles INSERT columns | SAFE | id/nickname만, suspension 주입 불가 |
| 29 | 115 | profiles UPDATE nickname | SAFE | ID/정지/시각 수정 불가 |
| 30 | 116 | menus SELECT | SAFE | menu public policy와 결합 |
| 31 | 117 | reviews SELECT columns | SAFE | moderation note/by/at 제외 |
| 32 | 118 | reviews INSERT columns | SAFE | store/rating/content만; user_id는 auth.uid default |
| 33 | 119 | reviews UPDATE columns | SAFE | rating/content만 |
| 34 | 120 | reviews DELETE grant | REVIEW | owner policy, 정지자 본인 삭제는 설계 예외 |
| 35 | 121 | reports INSERT columns | SAFE | review/reason/detail만 |
| 36 | 122 | service new-table CRUD | REVIEW | trusted role용; 운영 stores 권한 차이 M1 |
| 37 | 124 | menus public SELECT policy | SAFE | menu active AND store verified+active |
| 38 | 125 | reviews public SELECT policy | SAFE | nonhidden AND public store |
| 39 | 126 | reviews owner SELECT policy | SAFE | 관리 예외 의도적; 공개 view는 재필터 |
| 40 | 127 | profiles owner SELECT policy | SAFE | auth.uid=id |
| 41 | 128 | profiles author SELECT policy | SAFE | 공개 리뷰 작성자만; reviews에서 profiles로 재귀 없음 |
| 42 | 129 | profiles owner INSERT policy | SAFE | own ID + regular claim + default nonsuspended |
| 43 | 130 | profiles owner UPDATE policy | SAFE | USING/WITH CHECK 모두 own+regular+nonsuspended |
| 44 | 131 | reviews INSERT policy | REVIEW | 소유권/기여/공개매장; 긍정·위조 경로 실행 누락 |
| 45 | 132 | reviews UPDATE policy | REVIEW | USING/WITH CHECK 일치; 본인 정상/정지 후 검증 누락 |
| 46 | 133 | reviews DELETE policy | REVIEW | own only; hard delete 운영 tradeoff |
| 47 | 134 | reports INSERT policy | REVIEW | other visible/public + contributor; 공격 사례 실행 누락 |
| 48 | 136 | public_reviews view | SAFE | invoker+barrier, nonhidden/public, 운영 metadata 제외 |
| 49 | 137 | store_review_stats view | REVIEW | 집계 식 타당; 변경 시나리오 실행 누락 |
| 50 | 138 | REVOKE view ALL | SAFE | 기본 write/불필요 권한 제거 |
| 51 | 139 | GRANT view SELECT | REVIEW | client 적합; service base stores SELECT 없음 M1 |

## RLS/GRANT Matrix

아래는 migration의 선언과 현재 적용된 **로컬 실체**를 함께 검토한 결과다.
운영 신규 객체는 아직 없으므로 운영 적용 후 실체 확인을 대체하지 않는다.
S/I/U/D는 SELECT/INSERT/UPDATE/DELETE, '-'는 허용 없음이다.

| 객체 | PUBLIC | anon | authenticated | service / trusted |
| --- | --- | --- | --- | --- |
| profiles | - | S(id,nickname): 공개 리뷰 작성자 | S: 공개 작성자+본인; I(id,nickname): 본인 regular; U(nickname): 본인 regular/비정지; D 불가 | service S/I/U/D, trusted owner |
| menus | - | S: active menu+public store | 같은 S, I/U/D 불가 | service S/I/U/D |
| reviews | - | S: 공개 열+nonhidden/public | S: 공개+본인관리; I(store_id,rating,content): 본인/regular/비정지/public; U(rating,content): 같은 조건; D: 본인 | service S/I/U/D |
| review_reports | - | - | I(review_id,reason,detail): valid contributor가 다른 공개 리뷰에만; S/U/D 불가 | service S/I/U/D |
| public_reviews | - | S: 공개 view | 같은 S, 본인 hidden도 제외 | SELECT grant; 운영 stores base grant 부족 |
| store_review_stats | - | S: 공개 store 집계 | 같은 S | SELECT grant; 동일한 운영 의존 권한 부족 |
| burger_map_private schema | - | - | USAGE, CREATE 없음 | service USAGE; trusted owner |
| can_contribute() | - | - | EXECUTE만 | service execute 없음; trusted owner |
| set_updated_at() | - | - | 직접 EXECUTE 없음 | service 직접 EXECUTE 없음; trigger/owner 경로 |

reviews의 공개 허용 열: id/store_id/user_id/rating/content/is_hidden/created_at/updated_at.
profile의 is_suspended, reviews의 moderation_note/moderated_at/moderated_by,
reports의 모든 조회 열은 일반 client가 읽을 수 없다.
SELECT * 또는 무제한 return=representation은 허용 열만 읽는 것과 다르다.

로컬 실체: 네 테이블 RLS=true, 11개 policy, 두 view의 security_invoker=true/security_barrier=true.
helper owner=postgres, SECURITY DEFINER=true, search_path=pg_catalog,
ACL은 postgres/authenticated EXECUTE만이다. owner는 client role이 아니어야 한다.
함수는 auth.uid 기반 자신의 profile 정지 여부만 읽고 boolean만 반환한다.
임의 UUID 인수, 동적 SQL, user_metadata 권한 판단, auth.role(), 공개 RPC wrapper는 없다.

permissive OR는 profiles의 공개 작성자+본인 SELECT, reviews의 공개+본인관리 SELECT에만 의도적으로 사용된다.
UPDATE/INSERT에 완화하는 다른 permissive policy는 없다.
두 UPDATE policy는 USING과 WITH CHECK를 모두 가진다.
소유자 SELECT 예외가 public_reviews/stats까지 확장되지 않도록 view가 공개 조건을 다시 명시한다.

## Security Findings

### Critical

확정된 migration Critical defect 또는 운영 권한 우회 없음.

### High

**H1 — 필수 보안 테스트 누락, 운영 적용 gate 차단. 취약점 재현 판정이 아닌 증거 부족이다.**

과거 실제 실행된 파일은
`build/local-supabase-auth-review-20260921/rest_auth_contract_test.py`다.
그 안의 SQL 부분은 assert_true 호출 10개 + 보고서 SELECT 권한 거부 DO 검사 2개로,
요청된 전체 시나리오를 실행하지 않는다.
profiles/reviews fixture는 service_insert로 생성되며 정상 사용자의 own INSERT 성공을 입증하지 않는다.
REST도 제한된 요청만 수행한다. 다음 증거가 누락됐다:

- profiles: 일반 사용자 본인 생성/닉네임 변경 성공, 다른 ID 주입, 타인 변경, suspension 주입, 직접 DELETE 차단
- reviews: 본인 INSERT/UPDATE/DELETE 성공; forged user_id; user_id/store_id/created_at/운영 열 UPDATE 차단
- duplicate 리뷰와 rating 0/6/NULL; content 9/10/2000/2001/whitespace/Unicode 경계
- suspended 사용자의 **본인** 리뷰 UPDATE 차단. 현재 C는 A의 리뷰를 변경하므로 소유권 차단과 정지 차단을 구분하지 못함
- anonymous Auth의 review/report 직접 기여 차단을 실제 세션으로 충분히 검증
- reports: duplicate/self/hidden/private 대상, UPDATE/DELETE 및 RETURNING/embedded select 차단
- verified-inactive/rejected store fixtures; 현재 private fixture는 pending+inactive 하나뿐
- rating 수정/두 번째 리뷰/hide/delete/store 비공개에 따른 집계 변화
- auth/profile/review 삭제 cascade, store hard-delete RESTRICT 및 삭제된 계정의 남은 JWT

`tests/local/test_auth_menu_reviews_local_rest.py`에는 test method 6개가 있으나,
이 파일 전체를 적절한 fixture와 함께 실행한 PASS 기록으로 위 누락을 메울 수 없다.
106–120행의 이름은 update_or_delete지만 실제 DELETE 요청은 없고, PATCH 후 행 **개수**만 검사한다.
rating이 바뀌어도 행이 하나이면 통과하므로 원본 보존 assertion이 불충분하다.

**수정안:** migration을 바꾸지 말고 versioned local runner/fixture/SQL/REST test를 보완한다.
소유자 정상 성공과 공격 거부를 쌍으로 검증하고, row_count 및 전체 원본 row 불변을 함께 확인한다.
그 후 동일 migration SHA의 fresh chain에서 빠짐없는 SQL+REST/Auth suite를 재실행해야 한다.
이번 감사에서는 테스트를 수정하지 않았다.

**H2 — 실제 실행된 SQL test의 claims/assertion 결함, 운영 적용 gate 차단.**

- runtime script 99–103행은 `request.jwt.claim.is_anonymous`를 설정한다.
- 로컬 DB의 실제 `auth.jwt()` 함수는 `request.jwt.claim` 또는 `request.jwt.claims` JSON만 읽는다.
- 이번 READ ONLY 세션에서 같은 legacy is_anonymous 설정 후 `auth.jwt()->>'is_anonymous'`는 NULL이었다.
- D에게 profile이 없으므로 can_contribute=false는 claim 차단 대신 profile 부재만으로도 통과한다.
- 108–109행의 assert 함수는 `IF NOT value THEN`이다. NULL 입력에서는 예외를 내지 않는다.
  이번 READ ONLY CASE 확인에서도 NULL 조건의 결과가 no_exception임을 확인했다.
- 별도 `supabase/local_validation/local_validation_rls.sql`은 전체 JSON claims와
  `IS DISTINCT FROM true`를 사용하지만, 과거 실행된 runtime script는 이 파일을 호출하지 않는다.

**수정안:** 모든 역할 테스트에 실제 PostgREST 방식의 JSON claims를 넣고 auth.uid/is_anonymous 자체를 assert한다.
정상 regular contributor에서 helper=true인 양성 대조군을 두고 anonymous claim/정지/profile 부재를 각각 분리한다.
assert는 NULL도 실패하도록 바꾸고 누락 행을 명시적으로 실패시킨다. 수정 후 fresh DB에서 재검증한다.

### Medium

**M1 — local/production service_role stores 권한 차이.**

운영 has_table_privilege 검사에서 service_role의 stores S/I/U/D가 모두 false였다.
로컬 fixture runner는 service key로 stores INSERT 및 representation 반환을 수행한다.
이 경로는 현재 운영에서 동작하지 않는다. 또한 신규 invoker views의 service SELECT grant만으로
base stores SELECT 부족을 해결하지 못한다. 이는 현재 권한과
[PostgreSQL invoker view 규칙](https://www.postgresql.org/docs/17/sql-createview.html)에 근거한 적용 후 동작 추론이다.

client anon/auth 조회는 정상이고 기존 stores 권한을 변경할 필요는 없다.
후속 smoke fixture의 stores 준비/정리는 별도로 승인받은 trusted DB operator 경로로 수행하도록 계획했다.
새 기능이 service_role을 통한 해당 views 읽기를 요구하면 별도 승인과 최소 수정 검토가 필요하다.
이 제한을 문서화하고 trusted operator를 사용한다면 그 자체는 migration 차단 사유가 아니다.

**M2 — hard delete 후 신고 근거 소실/재작성.**

migration 61–65, 120, 133행. review 삭제는 reports를 cascade하고,
정지되지 않은 작성자는 삭제 후 새 review를 작성할 수 있다.
설계가 명시한 선택이며 자동 hidden/repost 방지는 없다.
반복 악성 재작성은 운영자가 profile 정지를 병행해야 한다.
개인정보 최소화와 장기 증거 보존의 tradeoff다. 기존 승인 설계 범위에서는 non-blocking.

**M3 — 운영 private schema 비노출 설정 미확인.**

함수 SQL은 private schema와 최소 권한으로 적절히 제한되어 있다.
실제 Data API 노출은 이름만으로 보장되지 않는다. 아직 노출됐다고 판정하지 않으며 현재 상태는 UNKNOWN이다.
이번 최종 승인 조건에 포함된 항목이므로 **확인될 때까지 blocking**이다.

**M4 — 적용 transaction/lock 및 잠깐의 기본 권한 노출 관리.**

SQL 자체는 single transaction에서 실행 가능한 DDL만 포함한다.
파일에 명시 BEGIN/COMMIT은 없고, 이 감사에서 CLI 2.117.0의 실패 시 rollback을 실행으로 검증하지 않았다.
각 문장을 수동 autocommit으로 나누면 CREATE와 REVOKE/RLS 사이의 기본 ACL 상태가 외부에 보일 수 있다.
후속 로컬 검증에서 실제 선택한 적용 경로의 원자적 실패/rollback을 확인하고
운영에서도 그 경로를 사용해야 한다. 파일을 자동 수정하거나 임의로 BEGIN을 삽입하지 않았다.

### Low

- SQL과 REST의 제한된 과거 PASS가 전체 gate로 확장 보고됐다. 기존 local README/보고서는 아직 도구 없음/BLOCKED 시점을 담고 있어 기록끼리 불일치한다. 이 보고서가 최종 감사의 정정 근거다.
- 성공 runner가 ignored build 경로에만 있어 재현성과 보존성이 약하다. 후속 검증 작업에서 versioned 위치로 정리해야 한다.
- 이번 전체 diff-check 실패는 기존 `integration_test/app_flow_test.dart:93,96` 후행 공백이다. scope 밖이며 DB 적용 blocker가 아니다.
- 로그용 vector container가 restarting 중이었다. DB/Auth/REST 읽기 검증과 별도 운영 상태이며 이번에 고치지 않았다.

운영 Security Advisor는 이번 조회에서 `lints=[]`였다.
신규 객체가 아직 없는 운영 DB의 현재 상태 검사이며, 신규 migration 보안 검증을 대신하지 않는다.

## Fresh local evidence review

| 증거 | 이번 해석 |
| --- | --- |
| 기존 fresh DB migration 이력 | 0001(8문장), 신규(51문장) 적용을 현재 직접 확인 |
| migration 원본/로컬 복사본 SHA | 일치 |
| 기존 SQL_RLS_CONTRACT PASS 출력 | 일부 12개 논리 검사 통과 이력. H2 때문에 전체 계약 증거는 부족 |
| 기존 REST_AUTH_CONTRACT PASS 출력 | 일부 실제 Auth/REST 경로 통과 이력. H1의 공격 사례 누락 |
| 이번 local metadata READ ONLY | helper owner/path/ACL, 테이블·열 권한, 11 policy, invoker views 확인 |
| 이번 local claims READ ONLY probe | 잘못된 legacy claim 전달과 NULL assertion 문제 확인 |
| 전체 write suite 신규 실행 | NOT RUN. 이번은 감사만 수행 |
| 삭제 cascade/집계 lifecycle/별점·본문 경계 | 충분한 실행 증거 없음, PASS로 표기하지 않음 |

`Prefer: return=minimal` 타인 PATCH의 204/body 없음과 SQL row_count=0,
후속 rating=4 보존은 과거 runner에 실제 assertion이 있다.
그러나 REST 요청에는 count=exact가 없고 전체 row snapshot 비교도 없으므로
HTTP response만으로 affected rows를 확인했다고 표현하지 않는다.
기본 return=representation/SELECT *의 403/42501은 column SELECT 제한과 양립한다.
오류를 없애려고 broad SELECT/UPDATE를 부여해서는 안 된다.
후속 테스트는 minimal+count=exact의 실제 header, 원본 전체 row,
허용 열을 명시한 representation과 SELECT * representation을 각각 확인해야 한다.

## Referential Integrity

| parent → child | ON DELETE | 영향 |
| --- | --- | --- |
| stores → menus | RESTRICT | 자식이 있으면 store hard delete 실패 |
| stores → reviews | RESTRICT | review/menu 오삭제 방지, 비활성화 기본 운영 |
| auth.users → profiles | CASCADE | 계정 삭제 시 profile 삭제 |
| profiles → reviews | CASCADE | 작성자 profile 삭제 시 review 삭제 |
| profiles → review_reports(reporter) | CASCADE | 신고자 탈퇴 시 본인 신고 삭제 |
| reviews → review_reports | CASCADE | review 삭제 시 연결 신고 삭제 |

명시하지 않은 ON UPDATE는 NO ACTION이다. client는 FK/identity 열을 임의 수정할 수 없다.
인덱스는 child FK 조회를 뒷받침한다. review/report UNIQUE의 선두 열은 store_id/review_id다.
계정 탈퇴 뒤 JWT가 남아도 profile FK와 helper가 재작성을 차단하는 구조지만,
실제 삭제/남은 JWT 재시도 검증은 H1에 포함된 미완료 항목이다.

## Rollback Readiness

**A. 적용 실패 또는 적용 직후 사용자 데이터가 없는 경우**

single-transaction 실패라면 rollback과 migration history 미등록을 먼저 확인한다.
이미 commit된 후라면 새 4개 테이블의 실제 0행 여부와 새 외부 의존성이 없음을 확인한 뒤에만,
별도 승인된 복구 migration으로 views → reports → reviews/menus → profiles → helper/trigger 함수 →
빈 private schema 순서의 제거를 검토할 수 있다.
기존 stores·auth.users 또는 그 데이터를 DROP하지 않는다.
무조건 DROP CASCADE, history 삭제, 무승인 migration repair는 하지 않는다.

**B. 실제 profile/menu/review/report가 존재하는 경우**

DROP rollback은 기본 선택이 아니다.
feature disable와 서버 쪽 client write lockdown, 필요 시 신규 데이터 read lockdown을 우선하고,
데이터를 보존한 forward-fix를 준비한다.
앱 버튼만 감추는 것은 직접 REST 쓰기를 막지 못한다.
장애 원인이 정책이면 검토한 최소 권한 lockdown을 적용하되 기존 stores 공개 탐색은 유지한다.
운영자에 의한 evidence/backup 보존 및 계정 탈퇴/개인정보 처리 요구를 함께 고려한다.
어떠한 복구 SQL도 이번에 실행하거나 실행 파일로 만들지 않았다.

## Production Apply Risk

- 새 빈 테이블만 생성하므로 기존 280개 stores 행의 rewrite/backfill, 기존 대형 테이블 index build는 없다.
- FK 생성은 public.stores와 auth.users에 SHARE ROW EXCLUSIVE lock을 요구한다.
  일반 SELECT와 양립하지만 기존 쓰기/다른 DDL과 경합할 수 있으므로 짧다고 무조건 가정하지 않는다.
- 5개 명시 인덱스와 PK/UNIQUE 인덱스는 새 빈 테이블 대상이다. CONCURRENTLY나 비transaction 문장은 없다.
- table → function → trigger → RLS/grants → policy → view 순서의 의존성은 타당하다.
- helper owner는 신뢰된 migration operator여야 한다. 로컬 owner=postgres는 확인했지만 운영 적용 후 재확인해야 한다.
- 운영 postgres public default ACL에는 anon/auth/service의 일부 TRUNCATE/REFERENCES/TRIGGER/MAINTAIN 기본 권한이 남아 있다.
  신규 migration의 REVOKE ALL이 이를 제거한다. 최종 ACL만 아니라 적용 transaction 경계도 유지해야 한다.
- 미래 db push의 vault/config/seed/role 부수 변경을 제외한다. CLI 도움말에서 vault 업데이트 기본 동작을 확인했으므로
  후속 승인 시 --skip-vault를 사용하고 include-all/include-seed/include-roles를 사용하지 않는다.
- 실행 시간/최대 lock wait, 사고 rollback을 측정하지 않았으므로 무중단/운영 적용 완료라고 주장하지 않는다.

## Production Apply Plan

**아래는 blocker 해소 및 별도 운영 승인 이후의 계획이며, 이번 실행 결과가 아니다.**

1. H1/H2 보완 suite를 같은 migration SHA와 운영과 같은 권한 전제로 fresh local에서 실행하고 실패 시 원자적 rollback도 검증한다.
2. branch/HEAD/dirty 상태, 0001 blob과 신규 SHA256, migration 디렉터리의 정확히 두 파일을 재확인한다.
3. 프로젝트 ref/name/region/PG17, 운영 API exposed schemas와 신뢰된 migration owner를 확인한다.
4. `npx.cmd --offline supabase migration list --project-ref eoiwfprghyyguthdtayx`로 0001만 applied인지 확인한다.
5. 현재 보고서의 stores count/권한/RLS/객체 충돌 aggregate를 다시 읽고 달라지면 중지한다.
6. 실행 계획과 synthetic fixture/cleanup을 포함해 명시적 운영 승인을 받는다.
7. CLI의 정확한 pending migration이 신규 파일 하나임을 확인한 후,
   검증된 single-transaction 경로로
   `npx.cmd --offline supabase db push --project-ref eoiwfprghyyguthdtayx --skip-vault`
   를 다음 승인 단계에서만 수행한다. 이번에는 --help만 확인했고 push/dry-run을 실행하지 않았다.
8. 실패하면 자동 repair/retry로 덮지 말고 history/partial object/lock 원인을 읽는다.
9. 성공하면 두 migration 이력, 4 tables/11 policies/2 views/helper owner/path/ACL/모든 열 권한을 확인한다.
10. stores 280/237/43 및 익명/인증 역할 동일 공개 결과를 재확인한다.
11. 아래 smoke test를 별도 승인된 synthetic 범위에서만 수행하고 정확한 UUID 목록으로 정리한다.
12. stores 기준점과 신규 fixture 잔여 0건, Security Advisor를 확인한 뒤 실제 결과에 근거해 적용 판정한다.

## Smoke Test Plan

**이번에는 실행하지 않았다.** 운영 쓰기 테스트는 별도 승인에 fixture 생성/정리까지 포함해야 한다.
Auth email은 OTP/SMTP를 가정하지 않고 별도 승인된 synthetic 계정 발급 경로를 사용한다.
A/B 일반 사용자와 suspended C, 필요하면 anonymous Auth D를 준비한다.
운영 anonymous sign-in이 비활성이면 그것을 테스트를 위해 자동 활성화하지 않고 로컬 actual-session 검증과 구분한다.

기존 280개 store에 synthetic review/menu를 붙이지 않는다.
명확히 표시한 전용 synthetic store P(공개), E(공개 0건), N(비공개)만 trusted DB operator가
허용된 시간/수명 범위로 만든다. 공개 store fixture는 운영 목록에 잠시 보일 수 있으므로
이 부작용을 별도로 승인하고 통제된 검증 시간대를 사용해야 한다.
이를 허용하지 않는다면 public-write smoke는 동일 설정의 격리 환경으로 제한하고 운영 해당 항목은 SKIP으로 보고한다.
공개 fixture를 숨기려고 공개 RLS를 우회/변경하지 않는다. 운영 service_role stores INSERT는 현재 불가다.

| 대상 | 조작 | 기대 결과 |
| --- | --- | --- |
| stores | anon/auth 명시 열 SELECT, N 조회, effective write privilege 검사 | 기존 237 공개 행 유지, N 숨김, write 권한 없음 |
| profiles | A 생성/닉네임 변경, B ID 위조/변경, suspension 주입 | A만 성공, 금지 payload 거부/0행, B 원본 불변 |
| menus | trusted operator가 P active/inactive 및 N active 준비, anon/auth 조회·변조 시도 | active/public만 조회, client I/U/D 거부 |
| reviews | A rating=4 정상 작성, user_id=B 주입, duplicate | A만 성공, 위조/중복 실패 |
| reviews | A 자신의 rating=5 수정, B PATCH minimal+count=exact | A 성공; B 0행, 원본 전체 row 불변 |
| reviews | B PATCH SELECT * representation / 명시 허용 열 representation | 전자는 42501 가능; 후자도 타인 변경 0행, 원본 불변 |
| reviews | user/store/created_at/is_hidden/운영 열 변경 | 모두 거부, 원본 불변 |
| reviews | owner hidden 조회/수정, public view 조회, C own update | owner 관리 가능하나 hidden 유지; public 숨김; C 수정 차단 |
| reviews | 타인 DELETE 및 본인 DELETE | 타인 0행/원본 유지, 본인 삭제 및 report cascade |
| reports | B가 A visible review 신고; duplicate/self/hidden/N/위조 reporter | 첫 valid INSERT만 성공, 잘못된 요청 거부 |
| reports | GET/HEAD/count/embedded SELECT, UPDATE/DELETE, INSERT RETURNING * | 데이터 반환/조작 금지, representation 실패 시 INSERT 잔여 없음 확인 |
| stats | A=4 작성 → A=5 수정 → B=3 작성 → B 숨김 → A 삭제 → P 비공개 | (count,avg)=(1,4.0)→(1,5.0)→(2,4.0)→(1,5.0)→(0,NULL)→행 없음 |
| empty | E stats | count=0, average_rating=NULL |
| Auth lifecycle | 승인된 synthetic 계정 삭제, 남은 토큰 쓰기 | 연결 데이터 cascade, 재작성 실패 |

각 공격 요청의 HTTP status/body/선별 header 및 trusted 조회 결과를 확인한다.
401/403 또는 0-row를 상황에 맞게 구분하고 2xx만으로 성공/보안을 판정하지 않는다.
테스트에 사용하는 키·토큰·비밀번호를 파일/로그/보고서에 출력하지 않는다.

cleanup은 만든 UUID만 대상으로 reports → reviews → menus → profiles/Auth 계정 → synthetic stores 순서로,
cascade된 행은 존재 여부를 재확인하며 처리한다. broad DELETE/이름 패턴 삭제는 금지한다.
실패 시에도 finally 정리/잔여 확인을 수행하고,
실패 원인 때문에 데이터 보존이 필요하면 무조건 지우지 말고 승인된 보존/접근 제한 절차를 따른다.
마지막에 운영 stores 280/237/43, 13열/RLS/index/function/trigger와 신규 synthetic 잔여 0건을 확인한다.

## Files Changed

이번 감사에서 새로 작성한 파일:

- `docs/auth-menu-review-production-final-review.md`

migration, tests, Flutter, dependency, CSV, .env, 기존 사용자 문서는 수정하지 않았다.
Git stage/commit/push/PR/merge/reset/clean을 수행하지 않았다.

## Existing Dirty Files

시작 시 tracked 변경: `PROJECT_STATUS.md`, `README.md`, `integration_test/app_flow_test.dart`.
새 migration과 `CODEX_CONTEXT.md`, 기존 data/config 3개 JSON,
docs의 기존 launch/Android/지역/Auth 검토 문서 및 docs/sql,
scripts/data의 기존 gangbuk 도구, supabase/.branches/.temp/drafts/local_validation,
tests/local은 이미 untracked였다. 이들을 이번 산출물로 주장하지 않는다.

기존 3개 tracked 변경 파일·두 migration·두 주요 versionable 테스트의 SHA256을
최종 상태와 다시 대조했고 **7/7 일치**했다.
전역 diff-check는 기존 integration_test 93/96행에서만 실패했다.
새 보고서는 독립 whitespace 검사, 51개 statement 행 수 대조, secret 패턴 검사를 통과했다.

## Open Blockers

1. **H1/H2:** 실제 실행 가능한 SQL/REST/Auth suite의 필수 보안 사례 누락과 claims/NULL assertion 결함.
   테스트만 보완한 뒤 fresh chain·운영과 같은 권한 조건으로 재검증해야 한다.
2. **M3:** 운영 Data API exposed schemas에서 private helper schema 비노출이 미확인.
3. **적용 경계 확인:** 선택한 migration 실행 경로의 atomic failure/rollback을 로컬에서 확인하고
   운영 적용 시 같은 경계를 사용해야 한다. 이번에는 SQL의 transaction 가능성만 정적으로 확인했다.

stores 기준점·migration 이력·객체 충돌은 blocker가 아니다.
service_role의 기존 stores 권한을 유지한 trusted operator smoke 계획이 필요하며,
이를 이유로 stores GRANT를 자동 변경해서는 안 된다.
실제 공개 출시·Flutter Auth/Menu/Review 완성·운영 migration 적용을 승인하는 보고서가 아니다.

## Final Verdict

**AUTH_MENU_REVIEW_PROD_APPLY_BLOCKED**

운영 읽기 전용 기준점은 정상이다. 신규 SQL의 확정 Critical/High 권한 우회는 발견하지 못했다.
그러나 필수 local validation evidence가 충분하지 않고 노출/적용 경계 확인이 남아
요청된 모든 승인 조건을 충족하지 못한다.
자동 수정이나 운영 적용 없이 감사 보고서 작성으로 종료한다.
