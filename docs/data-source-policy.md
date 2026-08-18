# 데이터 출처 정책

## 후보 생성 원천

Burger Map Korea는 소상공인시장진흥공단의 상가(상권)정보 공공데이터를 매장 후보 생성의 기본 원천으로 사용한다. 원본 파일마다 다음 정보를 별도로 확인해 기록한다.

- 제공 기관과 데이터셋 이름
- 다운로드 경로
- 원본 기준일(`sourceAsOf`)
- 다운로드 또는 확인 일자
- 적용한 추출기 버전 또는 Git commit

추출기는 기준일을 자동으로 추측하지 않는다. 실행자는 원본 자료에서 확인한 실제 기준일을 명시해야 한다.

## 원본과 파생 데이터

- `data/raw/`: 공공데이터 원본이며 로컬 처리 전용이다. Git에 포함하지 않는다.
- `data/review/`: 자동 생성한 검수 후보다. `pending` 또는 `needs_recheck` 상태이며 앱에 노출하지 않는다.
- `data/staging/`: Flutter 반영 전 통합 검수 데이터다. 개발·staging 검증 전용이며 Git과 production에서 제외한다.
- `data/verified/`: 향후 사람의 검수를 통과한 데이터만 저장할 위치다. Phase 3A에서는 실제 파일이나 seed를 생성하지 않는다.

공공데이터의 상호명, 주소, 업종, 좌표는 출력 과정에서 임의로 고치거나 보완하지 않는다. 비교용 문자열 정규화는 필터와 중복 후보 판정에만 사용한다.

## 외부 장소 API

Google Places API, Kakao Local API, NAVER Local/Search API를 영구 매장 DB의 기본 원천으로 사용하지 않는다.

Phase 2.1B의 Kakao 키워드 장소검색은 공공데이터에서 누락된 후보를 발견하고 기존 후보와 대조하기 위한 보조 검수 도구로만 사용했다. 원본 JSON은 저장하지 않고 검수에 필요한 최소 필드만 로컬 `data/review` CSV에 기록했다. 전화번호, 리뷰, 사용자 정보는 수집하지 않았으며 Kakao 결과를 공공데이터 CSV나 Flutter 데이터 또는 영구 매장 DB에 자동 병합하지 않았다.

외부 API 결과를 장기 보관, 재배포 또는 앱에 노출하려면 해당 시점의 이용약관을 별도로 확인한다. API 결과만으로 실제 매장 여부를 확정하거나 `verified`로 승격하지 않는다.

## 공개 노출 원칙

자동 추출 결과를 실제 매장으로 간주하지 않는다. 사람이 영업 상태, 버거 전문성, 주소와 좌표를 확인해 `verified`로 승인한 매장만 향후 앱에 노출한다.

## Phase 3A 데이터베이스 반영 정책

Phase 3A에서는 `stores` 스키마와 RLS만 정의한다. Phase 2의 staging 매장 24개와 보류 매장 4개는 Supabase에 업로드하지 않으며, `pending` 상태를 `verified`로 승격하지 않는다. 실제 매장 seed도 생성하지 않는다.

Supabase의 공개 조회 대상은 사람이 검수해 `verification_status = verified`가 되었고 운영상 활성화된 `is_active = true` 행으로 제한한다. `pending`, `needs_recheck`, `rejected` 행은 익명 사용자와 로그인 사용자 모두 조회할 수 없다.

외부 장소 API의 원문 응답, Kakao 또는 Google place id, 외부 장소 URL은 `stores`에 저장하지 않는다. 향후 약관 검토 후 외부 출처 연결이 필요해지면 공개 매장 엔터티와 분리된 별도 구조를 다시 설계한다.

Flutter에는 Supabase `service_role` 키, secret key, 데이터베이스 비밀번호를 절대 포함하지 않는다. Phase 3B에서 공개 읽기 연결을 추가하더라도 클라이언트에는 공개용 설정만 주입하고 쓰기는 신뢰할 수 있는 백엔드에서 처리한다.
