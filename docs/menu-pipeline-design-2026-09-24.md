# Burger Map 메뉴 근거 수집 설계 (2026-09-24)

상태: **설계·오프라인 시범 검토용**. 운영 메뉴 INSERT 0건, migration 적용 0건. 이전 13건의 `HOLD_FOR_USER_APPROVAL` 판정은 이 설계의 가격·지점 동일성 기준을 통과했다는 뜻이 아니다. 특히 Shuttle의 배송 채널 가격을 `public.menus.price`에 그대로 옮기지 않는다.

## 현재 계약과 한계

`supabase/migrations/20260922050439_auth_menu_reviews.sql`의 `public.menus`는 UUID PK, 공개 `stores.id` FK, 필수 이름, nullable 정수 KRW 가격, nullable category/description, signature/active/display_order, 타임스탬프를 가진다. PK 외 메뉴 고유성 제약은 없다. `(store_id,is_active,display_order,id)` 인덱스가 있으며 anon/auth는 활성 메뉴를 `verified AND active` 매장에서만 SELECT할 수 있다. 클라이언트 쓰기 정책은 없다. `SupabaseMenuRepository`는 매장 UUID와 활성 조건으로 읽고, 상세의 `StoreMenuSection`은 순서대로 표시하며 null 가격을 “가격 정보 없음”으로 표시한다. 현재 메뉴 행에는 출처 URL·관찰 시각·가격 맥락이 없다.

## 단계와 출처 정책

```text
verified + active store snapshot
  → 매장명·지점·주소를 포함한 검색어 생성
  → 허용된 검색/API로 URL 후보 발견
  → 출처 유형·운영 주체 확인
  → 매장과 출처의 이름/지점/주소/공식 계정 동일성 확인
  → 접근 가능한 원문에서 메뉴 관찰값 추출
  → 이름/가격 정규화 및 중복·충돌 표시
  → 근거 등급과 검토 CSV
  → 사람의 지점·메뉴·가격·signature 승인
  → 별도 승인된 배포 작업의 dry-run/INSERT/사후 검증
```

자동화는 후보 생성까지만 수행한다. 검색 결과가 없거나 페이지가 막혀도 메뉴가 없다는 뜻으로 변환하지 않는다. 운영 stores는 공개 상태를 read-only로 재확인한 뒤 입력 snapshot을 만든다. 이번 5개 UUID/이름/주소는 2026-09-24 운영 DB SELECT에서 모두 `verified AND active`임을 재확인했다. 메뉴 출처와 이름·가격은 이전 시범의 **과거 관찰값**이며 이번에는 웹을 새로 검색하지 않았다. 같은 SELECT에서 stores 280, 공개 237, menus 0을 확인했다.

| 등급 | 허용 출처 | 용도 |
|---|---|---|
| A | 소유·운영 관계와 해당 지점이 확인된 공식 웹/브랜드/매장/주문/SNS | 현재 메뉴의 강한 근거. 공식이라는 도메인 추측만으로 승격 금지 |
| B | 사업자 관리 프로필, 해당 지점의 주문·예약 플랫폼, 주소가 일치하는 현재 메뉴 | 사람 검토 대상. 채널 가격은 현장 가격과 분리 |
| C | Kakao/Naver Place, 일반 검색, 블로그, 리뷰·맛집 사이트 | 발견·교차확인만. 단독 공개 근거 불가 |

Kakao Local API는 기존 `scripts/data/discover_kakao_burger_candidates.py`처럼 장소 존재·지점명·주소·place URL 확인에만 사용한다. Kakao/Naver 지도·Place의 화면 메뉴/가격을 크롤링해 복제하지 않는다. 공식 메뉴 API가 없는 경우 미문서화 필드를 추출하지 않는다. 검색 엔진은 URL 발견용이며 검색 스니펫은 원문 메뉴 확정 근거가 아니다. 정상 HTTP 접근이 403, 로그인, CAPTCHA, robots/anti-bot 제한을 만나면 `BLOCKED_SOURCE`로 기록하고 우회하지 않는다.

## 검색, 동일성, 추출

기본 검색어 7개는 `<매장명> 메뉴/가격/주문/공식/burger menu/instagram/order`이며 주소 포함 검색어를 추가한다. 실제 구현에서는 지점명과 도로명 주소를 각각 넣어 쿼리 중복 제거, URL 정규화, 호스트별 요청 제한, 오류 분리를 한다. 발견 CSV는 `store_id`, `store_name`, `source_url`, `source_domain`, `source_type`, `title`, `discovered_at`, `discovery_query`, `candidate_score`와 tier/identity/access를 담는다. 검색 서비스 선택·쿼터·약관은 실제 연결 전에 확인한다.

출처 유형은 알려진 플랫폼 호스트를 보수적으로 분류하고, 공식 출처 주장은 소유 관계가 별도로 확인되어야 A가 된다. 동일성은 매장명·지점·도로명/구주소·전화번호(허용되고 필요한 경우)·공식 계정을 교차검증해 `EXACT_MATCH`, `LIKELY_MATCH`, `AMBIGUOUS`, `MISMATCH`로 기록한다. 주소가 다른 지점은 이름이 비슷해도 `MISMATCH`; 애매하거나 불일치하면 자동 공개 후보가 아니다. 현재 시범 구현은 이름+도로명 주소의 정규화된 정확 일치만 EXACT로 처리한다. 구주소·전화·계정 교차검증은 설계만 했으며 아직 구현하지 않았다.

추출 행에는 원문 메뉴명과 정규화명, 원문 가격과 KRW 정수 또는 null, `dine_in/pickup/delivery/order_channel/unknown`, signature 주장, 출처 URL/유형/tier, 지점 매칭, 확인 시각, 추출 방식·메모를 보존한다. Unicode NFKC, 공백·구두점·대소문자만 정규화한다. 영어와 한국어 번역명은 자동 병합하지 않는다. 정확한 `10,800원`은 10800으로 해석하지만 `10.8`, `1.08`, `10,800원~`, `시가`는 null이다. 이전 CSV에서 숫자 KRW만 보존된 시범 관찰은 별도의 `prior_csv_numeric_krw` 형식으로 처리해 원문 표기를 복원했다고 주장하지 않는다. 배송·주문 가격은 관찰값으로 남기되 현재 공개 스키마에 가격 맥락이 없으므로 현장/공식 적용 동일성 확인 전 `menus.price=NULL`을 권장한다. signature는 공식 출처의 직접적인 대표/시그니처/flagship 주장만 후보로 기록하고 사람 검토를 거친다.

판정 규칙: A1 = 현재 공식·정확한 지점·현장 가격 → `READY_WITH_PRICE`; A2 = 현재 공식·정확한 지점·가격 미확인/채널 가격만 있음 → `READY_WITHOUT_PRICE`; B1 또는 출처/시점 불확실 → `NEEDS_REVIEW`; C 단독 → 검토 보조만; 접근 차단 → `BLOCKED_SOURCE`; 다른 지점 → `REJECT`. 모든 READY도 **승인 제안**일 뿐 INSERT 허가가 아니다. 서로 다른 가격·메뉴명, 중복 후보, 가격 채널 혼합은 수동 검토 큐로 보낸다.

## 출처 저장 모델 비교

| 기준 | A: `menus`에 출처 칼럼 | B: 별도 `menu_evidence` |
|---|---|---|
| MVP 변경량 | 칼럼 몇 개 | 테이블·FK·인덱스·권한 추가 |
| 여러 출처/가격 재확인 | 행 하나로 불충분, 덮어쓰기 위험 | 관찰 행 추가로 이력 유지 |
| 감사·자동화 | 이전 근거 추적 어려움 | 근거 단위 검토·재확인 가능 |
| 저장/조회 비용 | 작음, 메뉴 한 행 | 관찰 행 증가; 기존 Flutter 메뉴 조회는 그대로 |
| RLS | 기존 공개 메뉴 행에 URL 노출 가능 | private schema에서 운영자만 접근 |

**B 권장.** 원문 출처·관찰 가격·맥락을 여러 건 보존하고 공개 메뉴의 간단한 read path를 유지한다. 승인 전 후보는 이 테이블이 아닌 versioned review CSV/JSON에 둔다. `menu_id` FK가 필요하므로 승인된 메뉴 INSERT 이후 같은 별도 배포 절차에서 근거를 연결해야 한다. B는 근거 관찰 이력이지 `menus` 수정 자체의 완전한 감사 로그는 아니다. 변경 이력이 필요해지면 별도 설계한다. `menu_candidate` DB 테이블과 CMS는 아직 불필요하다.

### 미적용 SQL 초안 (Option B)

기존 migration은 수정하지 않는다. 아래는 **검토용 초안**이며 아직 신규 migration 파일도 만들지 않았다. 적용 전 local migration/RLS 테스트와 실제 권한·Data API 노출 설정 확인이 필요하다. `burger_map_private`는 기존 migration이 생성한 schema이며 공개 Exposed schemas에 넣지 않는다. Supabase의 [RLS 가이드](https://supabase.com/docs/guides/database/postgres/row-level-security)와 [Data API 보안 가이드](https://supabase.com/docs/guides/api/securing-your-api)를 기준으로 public client 권한을 부여하지 않는다.

```sql
CREATE TABLE burger_map_private.menu_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_id uuid NOT NULL REFERENCES public.menus(id) ON DELETE RESTRICT,
  source_url text NOT NULL,
  source_type text NOT NULL,
  source_tier text NOT NULL,
  observed_name text NOT NULL,
  observed_price integer,
  price_context text NOT NULL,
  checked_at timestamptz NOT NULL,
  evidence_status text NOT NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT menu_evidence_url_check CHECK (
    source_url = btrim(source_url) AND char_length(source_url) BETWEEN 8 AND 2048
    AND source_url ~ '^https?://[^[:space:]]+$'),
  CONSTRAINT menu_evidence_type_check CHECK (source_type IN (
    'official_website','official_store_page','official_brand_page','official_social',
    'official_order','business_profile','delivery_platform','reservation_platform',
    'kakao_place','naver_place','third_party_review','blog','unknown')),
  CONSTRAINT menu_evidence_tier_check CHECK (source_tier IN ('A','B','C')),
  CONSTRAINT menu_evidence_name_check CHECK (
    observed_name = btrim(observed_name) AND char_length(observed_name) BETWEEN 1 AND 200),
  CONSTRAINT menu_evidence_price_check CHECK (observed_price IS NULL OR observed_price >= 0),
  CONSTRAINT menu_evidence_context_check CHECK (
    price_context IN ('dine_in','pickup','delivery','order_channel','unknown')),
  CONSTRAINT menu_evidence_status_check CHECK (
    evidence_status IN ('supporting','corroborating','superseded','rejected')),
  CONSTRAINT menu_evidence_notes_check CHECK (notes IS NULL OR char_length(notes) <= 1000)
);
CREATE INDEX menu_evidence_menu_checked_idx
  ON burger_map_private.menu_evidence (menu_id, checked_at DESC, id);
ALTER TABLE burger_map_private.menu_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE burger_map_private.menu_evidence FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON burger_map_private.menu_evidence TO service_role;
-- anon/authenticated RLS policy 없음. Flutter client에는 service_role 사용 금지.
```

Option A는 비교용으로 `public.menus`에 `source_url text`, `source_type text`, `price_context text`, `verified_at timestamptz`를 추가하는 안이다. URL/유형/가격 맥락 CHECK가 필요하고, 공개 SELECT에 출처가 노출되는지 확인해야 한다. 단일 출처 덮어쓰기 문제로 채택하지 않는다.

## 코드·아티팩트·배포 계약

현재 Python 관례에 맞춰 `scripts/data/build_menu_evidence_review.py`에 순수 변환 함수를 두었다. 입력은 UTF-8 JSON, 출력은 UTF-8-SIG CSV 두 개다. 재실행은 새 버전 경로를 지정해야 하고 기존 파일은 덮어쓰지 않는다. 실제 검색/API 클라이언트·HTML parser는 아직 없다. 현재 `classify_source`는 알려진 플랫폼 호스트와 검증된 소유 주장만 분류하고, `extract_menu_candidates` 역할은 수동 관찰 JSON 입력이 맡는다. `generate_publish_payload`는 아직 **의도적으로 미구현**이다.

장래 배포 전 필수 gate: 대상 UUID/FK 및 최신 `verified AND active`, 기존 `menus` 중복, 출처 원문·매장 동일성·현재성, 가격 맥락, signature 근거, dry-run 결과, 명시적인 `human_approved=true`와 승인자/시각 기록. 하나라도 없으면 SQL 생성과 INSERT를 거부한다. 관찰 CSV의 `human_approved=false`는 표시 전용이며 누구도 이 CSV를 바로 운영 INSERT 입력으로 쓰면 안 된다. 승인된 배포 후 건수·샘플 REST 조회·RLS·rollback 계획을 확인한다.

## 5개 매장 오프라인 시범

입력: [pilot JSON](menu-pipeline-pilot-input-2026-09-24.json). 출력: [출처 발견 CSV](menu-pipeline-source-discovery-pilot-2026-09-24.csv), [메뉴 검토 CSV](menu-pipeline-candidate-review-pilot-2026-09-24.csv). 매장 공개 상태만 운영 DB에서 SELECT로 재확인했다. 이전 조사 URL을 재처리했으며 새 웹 검색/HTTP 요청·현재 판매 여부 재확인은 하지 않았다.

| 항목 | 결과 |
|---|---:|
| 처리 매장 / 출처 후보 | 5 / 5 |
| A 공식 출처 / B 출처 | 1 / 4 |
| 메뉴 관찰 후보 / 이전 CSV에 기록된 채널 가격 숫자 | 8 / 2 |
| 공개 가격 후보 | 0 |
| `NEEDS_REVIEW` / `BLOCKED_SOURCE` 메뉴 행 / `REJECT` | 3 / 4 / 1 |
| 직접 접근 차단 출처 | 2 |

Shuttle 2개 가격은 배송 채널 관찰값으로만 남겼다. Daangn 두 출처는 이전 조사에서 직접 접근 403이었으므로 스니펫 기반 이름을 확정하지 않는다. N버거 공식 소개는 현재 메뉴임을 입증하지 못해 검토 대상이다. 더백푸드트럭 후보는 다른 지점 주소 출처여서 거부한다. 이번 표본은 의도적으로 어려운 사례이며 자동 승인률·가격 보급률의 서울 전체 추정치가 아니다.

## 확장 추정과 다음 검증

현재 기록의 공개 매장 237개를 가정하면 기본 8개 검색어로 단순 계산 **1,896개 검색어**다. 이는 요청 수나 비용 확정치가 아니다. 검색 서비스의 배치·페이지 수·쿼터·약관 확인 전 API 비용은 계산하지 않는다. URL 중복 제거 후 매장당 검토 출처 수를 `S`, 출처당 메뉴 후보 수를 `M`, 사람 검토 소요를 `T`분/후보라 하면 검토량은 `237×S×M×T`분이다. 이번 5개 매장의 출처 1.0개/매장, 메뉴 1.6개/매장, 차단 2/5 출처를 전체 서울에 외삽하면 선택 편향이 크므로 작업량 예산으로 사용하지 않는다. 우선 20~30개 매장에 서로 다른 브랜드/체인/독립점/출처 유형을 섞어 재시범하고 실제 검토 시간을 측정한다.

다음 단계는 합법적으로 접근 가능한 검색·원문 추출 수단의 약관/쿼터 확인, 매장 동일성의 구주소·전화·공식 계정 검증, 출처 최신성/충돌 규칙 추가, 승인 UI 없이도 감사 가능한 review 기록, local migration/RLS 테스트다. 그 후 승인된 메뉴 몇 건만 별도 배포 제안한다. 현재 앱·Flutter 코드는 변경하지 않았다.
