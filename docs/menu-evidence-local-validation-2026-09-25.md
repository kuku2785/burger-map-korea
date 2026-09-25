# Menu evidence V1 — fresh local Supabase validation (2026-09-25)

**Verdict: `MENU_EVIDENCE_SCHEMA_LOCAL_PASS`. Production migration apply: 0. Production menu INSERT: 0.** 이 보고서는 `nearby-store-sort`의 시작 HEAD `c1931068f56864d07b0120e241e1cb252445ff89`에서 [새 migration](../supabase/migrations/20260924140656_menu_evidence_v1.sql)만 추가하여 격리된 LOCAL Supabase에서 검사한 결과다. 원격 Supabase에 연결하거나 `db push`하지 않았다. 기존 dirty/untracked 사용자 파일은 보존했다.

## 실제 스키마와 결정

- `public.stores.id`는 UUID PK다. `verification_status`는 `pending/needs_recheck/verified/rejected`, `is_active`는 boolean이고, anon/authenticated SELECT는 `verified AND active`만 허용한다.
- `public.menus.id`는 UUID PK, `store_id`는 stores FK `ON DELETE RESTRICT`, 메뉴명은 필수, 실제 가격 컬럼은 nullable integer `price`, `is_signature`·`is_active` boolean, `display_order` integer다. 기존 menu SELECT 정책은 active 메뉴와 verified+active 매장만 허용한다. 기존 `(store_id,id)` UNIQUE는 없었다.
- V1은 nullable `menu_id`로 게시 전 근거를 허용하고, 연결 시 매장 소속을 DB에서 보장한다. 단일 `menu_id` FK만으로는 다른 매장의 메뉴 연결을 막지 못한다. Trigger는 잠금·경쟁 상태와 유지보수 부담이 커서 선택하지 않았다. 복합 FK를 위해 `public.menus(store_id,id)` UNIQUE를 추가했다. `id` PK 때문에 논리상 중복된 인덱스지만 복합 FK의 참조 키로 필요하며, 기존 컬럼·RLS·grants·조회 API는 변경하지 않는다.
- stores FK와 복합 menu FK 모두 `ON DELETE RESTRICT ON UPDATE RESTRICT`다. 근거는 감사 이력이므로 매장/연결 메뉴의 hard delete 또는 UUID/소속 변경이 이를 조용히 지우거나 잘못 연결하면 안 된다. 공개 메뉴 교체는 별도 승인 작업에서 비활성화 및 새 snapshot 생성으로 처리해야 한다. 과거 메뉴 hard delete가 필요한 운영 절차는 evidence 보존·재연결 정책을 먼저 정해야 한다.

## 테이블과 보안 경계

`burger_map_private.menu_evidence`는 UUID PK, 필수 매장 UUID, nullable 메뉴 UUID, 출처 URL/유형/A·B·C, 매장 일치 상태, 관찰명/정규화명, nullable 관찰 가격, 가격 맥락, 현재성, nullable 출처 게시일, 필수 실제 열람일, nullable signature 근거, `candidate/approved/rejected/superseded` 상태, nullable 승인 참조/메모, 생성일을 갖는다. 출처 유형·등급·동일성·가격 맥락·현재성·상태·길이·가격 비음수·승인/링크 생명주기 CHECK와 매장/메뉴 FK를 사용한다. 인덱스는 `(store_id,evidence_status,retrieved_at DESC)`와 linked `menu_id`의 partial index다. Postgres enum type이나 신규 CMS는 만들지 않았다.

격리 로컬 `supabase/config.toml`의 API schemas와 실제 PostgREST `PGRST_DB_SCHEMAS`는 `public,graphql_public`이며 `burger_map_private`가 없다. `pg_db_role_setting`의 SQL-level `pgrst.db_schemas`에 private schema를 넣는 override도 0건이다. 기존 Auth helper 때문에 private schema의 `USAGE`는 authenticated에 남아 있다. **새 테이블**의 anon/authenticated SELECT/INSERT/UPDATE/DELETE는 모두 없고, 실제 역할 SQL 시도도 거부됐다. 테이블 RLS는 활성화했으며 client 정책은 0개다. 따라서 Data API schema 제외, 테이블 GRANT 부재, RLS의 세 경계를 별도로 확인했다. `service_role`에는 내부 기록에 필요한 SELECT/INSERT/UPDATE만 부여하고 DELETE는 부여하지 않았다. Flutter client에는 service role 경로가 없다.

## 격리와 migration 재현

- Docker Desktop 로컬 엔진 29.8.0, Supabase CLI 2.117.0. 새 로컬 프로젝트는 `build/menu_evidence_v1_local_20260924_1406`에 초기화했고 `project_id=menu_evidence_v1_local_20260924_1406`, loopback API 포트 `58321`, DB 포트 `58322`를 사용한다. 기존 로컬 프로젝트/컨테이너/volume을 stop/reset/delete하지 않았다. 이번 프로젝트의 link 정보는 없다.
- 기존 `0001_init_store_schema.sql`, `20260922050439_auth_menu_reviews.sql`과 새 `20260924140656_menu_evidence_v1.sql`을 이 프로젝트에 복사해 최초 `supabase start`에서 적용했다. 원본의 기존 두 migration은 수정하지 않았다.
- 이 **작업 전용 DB만** `supabase db reset --local --no-seed`한 후 세 migration이 순서대로 재적용되었다. `supabase migration list --local`에서 `0001`, `20260922050439`, `20260924140656`의 local/적용 버전이 일치했다. 별도 DOWN 체계는 도입하지 않았다.
- 로컬 테스트 매장/메뉴/근거는 합성 UUID와 `example.org` URL만 사용했고 각 SQL fixture는 transaction rollback으로 정리했다. 기존 실제 store 데이터나 운영 설정을 읽거나 바꾸지 않았다.

## 실행한 계약 검증

| 구분 | 실제 결과 |
| --- | --- |
| `menu_id=NULL` 후보 INSERT | PASS |
| 같은 store의 유효 menu 연결 | PASS |
| 다른 store menu 연결 | FK `23503`으로 거부 PASS |
| 없는 store / 없는 menu | 각각 FK `23503`으로 거부 PASS |
| 허용된 source type 13종/tier/status | PASS |
| 잘못된 URL/type/tier/match/정규화명/status/승인 참조/context/currentness/가격 | CHECK `23514`로 거부 PASS |
| 관찰 가격 NULL / 출처 게시일 NULL | PASS |
| 연결 메뉴 DELETE·매장 변경, 근거가 있는 store DELETE | FK `23503`으로 거부 PASS |
| anon SELECT/INSERT/UPDATE/DELETE | 전부 권한 오류 `42501` PASS |
| authenticated SELECT/INSERT/UPDATE/DELETE | 전부 권한 오류 `42501` PASS |
| service_role SELECT/INSERT/UPDATE, DELETE 거부 | PASS |
| anon/authenticated 공개 store·menu fixture | 각 verified+active store 1 / 공개 active menu 1만 조회 PASS |
| localhost REST 공개 menus | HTTP 200 PASS |
| localhost REST `Accept-Profile: burger_map_private` | HTTP 406 PASS |
| evidence 후보 → 승인 상태 → 로컬 publish proposal | 승인 없으면 오류, 승인 뒤 제안 생성 PASS |
| 관찰 `10800/order_channel` → 공개 제안 `price=NULL` | PASS |

fresh reset 후 [로컬 SQL/승인 계약 테스트](../tests/local/test_menu_evidence_v1_local.py) **32/32 PASS**, [Python 데이터 테스트](../tests/data/) **254/254 PASS**. 로컬 API 개발 anon 키는 실행 프로세스 메모리에서만 읽고 폐기했으며 값이나 응답 본문을 출력·파일 기록하지 않았다. Flutter 파일은 변경하지 않았고 Flutter 테스트/빌드는 이 schema-only 단계에서 실행하지 않았다.

## 남은 위험과 정지선

Production Data API exposed schemas와 운영 권한은 이번에 재검증하지 않았다. Production 적용 직전 별도 read-only gate가 필요하다. UNIQUE 인덱스 추가의 운영 잠금/시간과 기존 public menu 데이터 상태를 그때 확인해야 한다. RESTRICT 때문에 근거가 연결된 메뉴 hard delete는 실패하므로 후속 게시 배치가 비활성화 중심인지 검토해야 한다. SQL CHECK는 출처 진위·현재성·사람 승인 의사를 증명하지 못하며, 별도 review와 게시 dry-run은 여전히 필수다. 이번 단계에서 commit/push/PR/merge, production migration·menu INSERT는 모두 0건이다.
