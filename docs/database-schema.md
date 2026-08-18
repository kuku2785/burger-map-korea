# Burger Map Korea 데이터베이스 스키마

## Phase 3A 범위

Phase 3A는 Supabase PostgreSQL의 `stores` 테이블과 RLS 정책만 정의한다. Codex 작업에서는 원격 프로젝트를 변경하지 않았고, 사용자가 개발용 원격 프로젝트에 migration을 직접 적용해 검증했다. Flutter 연결, 실제 매장 seed, staging 데이터 업로드는 수행하지 않는다.

## stores 테이블

`stores.id`는 외부 지도 사업자의 식별자와 무관한 내부 UUID다. Kakao place id, Google place id, 외부 장소 URL은 이 테이블에 저장하지 않는다.

| 컬럼 | 타입 | 필수 여부 | 설명 |
| --- | --- | --- | --- |
| `id` | `uuid` | 필수 | 내부 기본키, `gen_random_uuid()` 기본값 |
| `name` | `text` | 필수 | 공백만 있는 값 금지 |
| `address` | `text` | 필수 | 공백만 있는 값 금지 |
| `latitude` | `double precision` | 필수 | -90 이상 90 이하 |
| `longitude` | `double precision` | 필수 | -180 이상 180 이하 |
| `burger_style` | `text` | 선택 | 확인된 값만 저장하며 빈 문자열 금지 |
| `verification_status` | `text` | 필수 | `pending`, `needs_recheck`, `verified`, `rejected` |
| `is_active` | `boolean` | 필수 | 공개 노출 가능 여부, 기본값 `false` |
| `source_type` | `text` | 필수 | 데이터 생성 경로를 나타내는 제한된 값 |
| `source_as_of` | `date` | 선택 | 원천 데이터 기준일. API 조회 시각과 혼용하지 않음 |
| `verified_at` | `timestamptz` | 조건부 | `verified`일 때만 필수 |
| `created_at` | `timestamptz` | 필수 | 생성 시각 자동 설정 |
| `updated_at` | `timestamptz` | 필수 | 생성 시각 설정 및 UPDATE trigger로 갱신 |

`source_type` 허용값은 `public_data`, `manual_review`, `user_submission`, `owner_submission`, `mixed`다. 출처 사업자의 외부 식별자를 이 값에 넣지 않는다.

## 공개 조건과 RLS

`stores`에는 RLS가 활성화된다. `anon`과 `authenticated` 역할은 아래 조건을 모두 만족하는 행만 읽을 수 있다.

```text
verification_status = verified
is_active = true
```

두 역할의 기존 테이블 권한은 모두 회수하고 `SELECT`만 다시 부여한다. INSERT, UPDATE, DELETE 정책은 만들지 않는다. 따라서 공개 Flutter 클라이언트에서는 쓰기가 허용되지 않는다.

관리자 쓰기는 Phase 3A 범위 밖이다. 향후 신뢰할 수 있는 서버 또는 관리 백엔드에서만 수행하며 `service_role` 또는 secret key를 Flutter 앱에 포함하지 않는다.

## 인덱스

초기에는 기본키 인덱스 외에 공개 활성 매장의 좌표 조회를 위한 partial index 하나만 둔다. 실제 조회 패턴과 실행 계획을 확인하기 전에는 검색·출처·상태별 인덱스를 추가하지 않는다.

## Flutter 모델 매핑

Phase 3B에서 DB 행을 `StoreLocation`으로 변환할 때 snake_case DB 컬럼을 Dart 필드에 명시적으로 매핑한다. `burger_style`이 `null`인 경우 표시 문구는 UI 계층에서 결정하며 DB에 임의의 분류값을 채우지 않는다.

## 원격 개발 환경 적용 검증

2026-08-18 사용자가 개발용 원격 Supabase 프로젝트에서 Phase 3A migration 적용과 다음 항목을 직접 확인했다.

- migration 실행 성공
- `public.stores` 테이블 생성
- `stores` 데이터 0행
- RLS 활성화
- SELECT 정책 1개 존재
- 실제 데이터 업로드 없음

이 기록에는 프로젝트 이름이나 식별자, Project URL, API key, 데이터베이스 비밀번호를 포함하지 않는다. Flutter Supabase 연결과 실제 매장 데이터 반영은 Phase 3A 범위에 포함하지 않는다.
