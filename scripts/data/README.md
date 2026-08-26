# 버거 매장 후보 추출기

소상공인시장진흥공단 상가(상권)정보 CSV에서 지정 지역의 버거 매장 후보를 생성하는 로컬 도구다. 후보 생성만 수행하며 실제 매장 여부를 승인하지 않는다.

## 입력 준비

1. 공공데이터포털에서 받은 서울 상가(상권)정보 원본 CSV를 `data/raw/`에 둔다.
2. 원본 자료에 적힌 실제 기준일을 확인한다.
3. 기준일을 파일명만 보고 추측하지 않는다.

`data/raw/`의 파일은 Git에서 제외된다. 입력은 UTF-8 또는 UTF-8-SIG CSV여야 한다. 다른 인코딩이면 스크립트가 오류를 출력하므로 원본 인코딩을 확인한 뒤 UTF-8로 변환한다.

## 실행

프로젝트 루트에서 다음 명령을 실행한다. `<원본 기준일>`은 실제 자료에서 확인한 날짜로 바꾼다.

```powershell
python scripts/data/extract_burger_candidates.py `
  --input data/raw/seoul_commercial_stores.csv `
  --output data/review/yongsan_burger_candidates.csv `
  --source-as-of <원본 기준일> `
  --sido 서울특별시 `
  --sigungu 용산구
```

출력 CSV는 UTF-8-SIG로 생성된다. `data/review/*.csv`도 Git에서 제외된다.

## 테스트

테스트 데이터는 실제 매장이 아닌 가상 이름과 가상 주소만 사용한다.

```powershell
C:\Users\jeong\anaconda3\python.exe -m pytest tests/data
```

## 판정 원칙

- `상권업종소분류명`이 `버거`이거나 업종 필드에 `버거`, `햄버거`, `수제버거`가 있으면 업종 후보가 된다. Phase 2.1A 출력과의 하위 호환을 위해 기존 `패스트푸드` 업종 탐색도 유지한다.
- 상호명/지점명에 `버거`, `햄버거`, `burger`, `hamburger` 중 하나가 있으면 이름 후보가 된다.
- `data/config/burger_brand_aliases.json`의 별칭과 정규화한 상호명이 정확히 일치하면 별칭 후보가 된다.
- 업종, 이름, 별칭 조건은 합집합이다. `candidateReason`은 `category`, `name`, `category_and_name`, `brand_alias`, `category_and_alias`, `name_and_alias`, `category_name_and_alias` 중 하나다.
- 비교할 때만 Unicode NFKC, 영문 소문자, 연속 공백, 공백·하이픈·괄호 차이를 정규화한다. 출력의 원본 상호명과 주소는 변경하지 않는다.
- 정상 후보는 `pending`, 누락·좌표 오류·중복 의심이 있는 후보는 `needs_recheck`다.
- `data/config/burger_exclusion_rules.json`에 일치하면 행을 삭제하지 않고 `exclusionReason`과 `verificationNote`에 근거를 기록한 뒤 `needs_recheck`로 둔다.
- 식별자인 `상가업소번호`가 없으면 결정적 `candidateId`를 만들 수 없어 출력에서 제외하고 통계에 사유를 남긴다.
- 중복 의심 후보는 자동 삭제하지 않는다.
- 어떤 규칙도 후보를 `verified` 또는 `rejected`로 자동 변경하지 않는다. 최종 판단은 사람이 한다.

별칭과 제외 규칙은 JSON 배열에 항목을 추가하는 방식으로 확장한다. 후보 발견용 브랜드 별칭은 정규화 후 정확 일치만 사용하며 퍼지 매칭은 하지 않는다. 제외 규칙의 `contains`는 설정에 명시한 강한 브랜드 별칭이 상호명에 포함됐는지 확인하며, 결과는 삭제나 확정 거절이 아니라 항상 추가 검수 대상으로 남는다.

30m 이내 유사 이름 비교는 Phase 2.1A 범위에 포함하지 않는다. 필요성은 실제 후보를 검토한 뒤 Phase 2.1B에서 판단한다.

## Phase 2.1B 카카오 보완 후보 수집

`discover_kakao_burger_candidates.py`는 카카오맵 키워드 장소검색 결과를 기존 V2 및 reviewed 후보와 대조해 수동 검수용 CSV를 만든다. 원본 JSON은 저장하지 않고 장소 id, 이름, 카테고리, 주소, 좌표, 장소 URL만 실행 중 메모리에서 처리한다. 전화번호, 리뷰, 사용자 정보는 수집하지 않는다.

검색어와 용산구 중심 좌표·반경은 `data/config/kakao_burger_search_queries.json`에서 관리한다. 공식 제한에 따라 한 페이지 15건, 검색어당 최대 45페이지를 사용하며 `meta.is_end`가 참이면 즉시 종료한다. 401, 403, 429 및 네트워크 오류는 자동 재시도하지 않는다.

호출량만 먼저 확인한다.

```powershell
C:\Users\jeong\anaconda3\python.exe scripts\data\discover_kakao_burger_candidates.py --estimate-only
```

무료 쿼터 적용 앱인지 카카오디벨로퍼스 앱 관리에서 확인한 다음 실행한다.

```powershell
C:\Users\jeong\anaconda3\python.exe scripts\data\discover_kakao_burger_candidates.py
```

기본 출력은 `data/review/yongsan_kakao_burger_discovery.csv`다. 파일이 이미 있으면 안전을 위해 중단하며, 명시적으로 다시 생성할 때만 `--overwrite`를 사용한다.

API 키는 OS 환경변수 또는 Git에서 제외된 프로젝트 루트 `.env`의 `KAKAO_REST_API_KEY`에서 읽는다. 키는 URL, 로그, 오류 메시지, CSV에 포함하지 않는다.

보완 후보의 상태는 `pending` 또는 `needs_recheck`뿐이다. 제외 규칙과 일치한 장소는 후보 CSV에서 제외하고 유형별 건수만 실행 요약에 남긴다. 기존 reviewed의 `rejected` 장소와 일치하면 기존 판단을 수정하지 않고 `conflictWithReviewed=true`로 표시한다. 이 결과는 Flutter 데이터나 영구 매장 DB로 직접 가져오지 않는다.

## Phase 4C-B1R 버거 스타일 검수표

`build_burger_style_review.py`는 staging 24곳과 게시 검수표의 내부 UUID를 결합해 로컬 스타일 검수표를 생성한다. 원본 입력과 hold report는 수정하지 않으며 출력은 Git에서 제외되는 `data/review/yongsan_burger_style_review.csv`다.

```powershell
python scripts/data/build_burger_style_review.py
```

새 행은 안전하게 `unclassified + needs_recheck + low`로 생성된다. 기존 B1 출력은 1차 근거를 보존한 채 B1R 열을 추가하며, 교차 검증 전 `proposed` 행은 안전하게 재확인 상태로 낮춘다. 기존 B1R 출력이 있으면 `proposedBurgerStyle`, 1차·2차 근거와 검토 메모 등 사람이 입력한 필드를 보존한다.

비공식 근거로 `proposed`를 유지하려면 서로 다른 URL의 1차·2차 근거가 모두 있어야 한다. `single_source`, `conflict`, `low`, `needs_manual_check`는 제안 또는 자동 승인을 허용하지 않는다. candidateId 집합·행 순서·UUID·주소·좌표가 달라져도 중단하며 생성기는 `approved`를 만들지 않고 기존 사용자의 승인 값만 검증·보존한다.

검수표의 허용 상태와 근거 유형, 사람 승인 절차는 `docs/phase-4c-burger-style-review.md`에 정리돼 있다. 좌표는 staging과 게시 검수표의 연결 검증에만 사용하며 로컬 스타일 검수표에는 다시 기록하지 않는다.

명시적인 사용자 승인만 `reviewNumber=style` 형식으로 반영한다. 승인 목록은 실행 시 직접 전달하며 스크립트가 후보를 자동 승인하지 않는다.

```powershell
python scripts/data/apply_burger_style_approvals.py --approve 1=other --approve 2=chicken
```

승인 스타일을 development용 staging asset에 결합한다. `--style-review`가 없으면 모든 버거 스타일을 기존 `미분류` 값으로 만드는 이전 동작을 유지한다.

```powershell
python scripts/data/build_flutter_staging_asset.py `
  --input data/staging/yongsan_burger_stores_staging.csv `
  --output assets/dev/yongsan_burger_stores_staging.json `
  --style-review data/review/yongsan_burger_style_review.csv `
  --overwrite
```

향후 게시 INSERT SQL을 새로 만들 때만 `generate_store_publish_sql.py --style-review <path>`를 선택적으로 사용한다. 이 인수는 `burger_style`만 승인 값으로 치환하며 `publishDecision`과 `isActive`를 변경하지 않는다.

이미 게시된 `verified + active` 매장의 승인 스타일 UPDATE SQL은 별도 생성기로 만든다.

```powershell
python scripts/data/generate_store_style_update_sql.py
```

출력 `data/staging/yongsan_burger_style_update.sql`은 Git에서 제외된다. SQL은 `public.stores`의 `burger_style`만 변경하고 각 UUID가 정확히 한 행에 영향을 주지 않으면 예외로 transaction 전체를 중단한다. 생성기는 SQL을 실행하거나 Supabase에 접속하지 않는다.

## Phase 6A-1 공개 매장 확대 검수표

`build_publish_expansion_review.py`는 staging, 게시 검수표, 스타일 검수표와
hold report를 교차 검증하고, 로컬 근거 JSON을 23개 pending 매장 검수표로
결합한다. 이미 공개된 verified + active 매장과 hold 매장은 출력하지 않는다.

```powershell
C:\Users\jeong\anaconda3\python.exe scripts\data\build_publish_expansion_review.py
```

근거 입력 `data/review/yongsan_burger_publish_expansion_evidence.json`과 출력
`data/review/yongsan_burger_publish_expansion_review.csv`는 모두 Git에서 제외된다.
생성기는 추천 조건과 최대 9곳 제한을 검증하지만 `publishDecision`, `isActive`,
SQL, Flutter asset 또는 Supabase를 변경하지 않는다.

## Phase 6A-2 공개 확대 승인과 게시 SQL

수정된 사용자 승인 목록은 Git에서 제외되는
`data/review/yongsan_burger_publish_expansion_approvals.json`에 이름,
`storeId`, `candidateId`, 검수표 번호, 승인 스타일과 실제 근거 기준일을 함께
기록한다. 번호만으로 승인하지 않으며 allowlist 9곳과 명시적 denylist를 모두
검증한다.

```powershell
C:\Users\jeong\anaconda3\python.exe scripts\data\apply_publish_expansion_approvals.py
```

승인 적용기는 게시 검수표 24행 중 정확히 9행만 `verified + active`로 바꾸고,
기존 공개 매장과 나머지 14행을 그대로 보존한다. 이름·UUID·candidateId,
staging 주소·좌표, 승인 스타일과 Phase 6A-1 추천 상태가 모두 맞아야 한다.
실패 시 CSV를 교체하지 않으며 같은 입력으로 재실행하면 최초 `verifiedAt`을
보존한다.

검수표 반영 후 신규 9곳 전용 SQL을 생성한다.

```powershell
C:\Users\jeong\anaconda3\python.exe scripts\data\generate_publish_expansion_sql.py
```

출력 `data/staging/yongsan_burger_store_publish_expansion.sql`은 Git에서 제외된다.
SQL은 신규 UUID가 DB에 0개일 때만 9행을 INSERT하고, 영향 행 수와
`verified + active + burger_style` 사후 조건이 맞지 않으면 transaction을
중단한다. 기존 공개 매장은 INSERT하지 않으며 UPDATE, DELETE, UPSERT, RPC,
`ON CONFLICT`를 사용하지 않는다. 생성기는 SQL을 실행하거나 Supabase에
접속하지 않는다.

## Phase 6B-1 공개 매장 25곳 확대 검수표

현재 공개 10곳을 제외한 pending 14곳과 hold 4곳을 안정 ID로 결합하고, 로컬 근거
JSON의 안전 판정을 검증해 25곳 확대 검수표를 만든다.

```powershell
C:\Users\jeong\anaconda3\python.exe scripts\data\build_25_store_expansion_review.py
```

입력 CSV는 수정하지 않는다. 근거 JSON과 생성 CSV는 `data/review/`의 Git 제외 파일이며,
생성기는 행 번호를 식별자로 사용하거나 `verified`, `rejected`, `isActive=true`를 만들지
않는다. 승인 제안은 최대 15곳이고, 부족분은 현재 공개 수와 안전 게이트 통과 수로만
계산한다. 이 명령은 SQL 생성, Supabase 접속, Flutter asset 변경을 수행하지 않는다.

## Phase 6B 승인 반영과 13행 게시 SQL

사용자가 안정 `reviewItemId`로 승인한 13곳은 Git에서 제외되는
`data/review/yongsan_burger_25_store_expansion_approvals.json`에 기록한다. 일반 후보는
`storeId + candidateId + 이름 + 주소 + 좌표`, hold 해소 후보는 사용 가능한 원천 ID와
hold 자료까지 교차 검증한다.

```powershell
C:\Users\jeong\anaconda3\python.exe scripts\data\apply_25_store_expansion_approvals.py
```

승인 적용기는 기존 공개 10행과 미승인 pending 2행을 변경하지 않는다. hold 해소 후보의
내부 UUID는 최초 적용 때 한 번 생성해 게시 검수표에 저장하고, 재실행 시 UUID와
`verifiedAt`을 보존한다. `sourceAsOf`는 Phase 6B 근거 검수표의 실제 기준일을 사용한다.

```powershell
C:\Users\jeong\anaconda3\python.exe scripts\data\generate_25_store_expansion_sql.py
```

출력 `data/staging/yongsan_burger_store_publish_25_expansion.sql`은 Git에서 제외된다. 기존
공개 10곳을 제외한 신규 승인 13곳만 INSERT하며, 실행 전 10행·실행 후 23행, 신규 UUID,
신규 값 일치와 최종 스타일 분포를 transaction 안에서 검증한다. 동일 SQL 재실행은
사전 조건에서 실패한다. 출력 SQL 파일이 이미 있으면 현재 생성 결과와 내용을 비교한다.
내용이 같으면 정상 통과하고, 다르면 기존 파일을 덮어쓰지 않고 중단한다. 두 스크립트
모두 Supabase에 접속하거나 SQL을 실행하지 않는다.
