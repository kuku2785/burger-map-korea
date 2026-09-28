# Review MVP 구현 준비 감사 — 2026-09-25

**판정: `REVIEW_MVP_SCHEMA_CHANGE_REQUIRED`.** 5단계 선호도는 현재 `reviews.rating smallint CHECK (rating BETWEEN 1 AND 5)`에 저장할 수 있다. 그러나 요구한 **선택형 텍스트**는 현재 `reviews.content text NOT NULL` 및 10–2,000자 제약과 충돌한다. 이 문서는 최소 마이그레이션을 **제안만** 한다. Review 기능 코드, Production 스키마·데이터·RLS는 변경하지 않았다.

2026-09-28 저장소의 `supabase/migrations/20260922050439_auth_menu_reviews.sql`과 Flutter 코드를 확인하고 Production 프로젝트 `eoiwfprghyyguthdtayx`의 컬럼·제약·정책·뷰 옵션을 읽기 전용으로 대조했다. Production은 매장 280, verified+active 237, 공개 메뉴 28, 메뉴 근거 29, 리뷰 0행이었다. 저장소 branch는 `nearby-store-sort`, HEAD는 `8668124f82dd159fbe48e0fa63573d58cae11930`이었다.

## 현재 스키마와 대상 모델

| 객체 | 실제 컬럼·제약 중 MVP와 관련된 부분 |
| --- | --- |
| `public.profiles` | `id uuid` → `auth.users(id)` PK, `nickname text NOT NULL`, `is_suspended boolean NOT NULL DEFAULT false`, 생성·수정 시각. 닉네임 길이·문자·예약어 검사. |
| `public.reviews` | `id uuid` PK, `store_id uuid NOT NULL` → `stores(id)`, `user_id uuid NOT NULL DEFAULT auth.uid()` → `profiles(id)`, `rating smallint NOT NULL` 1–5, `content text NOT NULL` 공백 제거·10–2,000자, `is_hidden`, moderation 메타데이터, 생성·수정 시각. `UNIQUE(store_id,user_id)`로 한 사용자·매장에 리뷰 1개. |
| `public.review_reports` | `id`, `review_id` → `reviews(id)`, `reporter_user_id DEFAULT auth.uid()` → `profiles(id)`, `reason`, 선택형 `detail`, `status`, resolution 메타데이터, 시각. 신고자·리뷰 조합 유일. 사유는 `spam`, `harassment`, `personal_information`, `irrelevant`, `other`; `other`는 설명 필수. |
| `public.public_reviews` | 공개 매장의 숨기지 않은 리뷰를 읽는 `security_invoker=true`, `security_barrier=true` 뷰. `id,store_id,user_id,rating,content,created_at,updated_at`. |
| `public.store_review_stats` | 공개 매장별 `review_count`와 `average_rating`을 계산하는 같은 보안 옵션의 뷰. 선호도 MVP에서 평균을 별점처럼 표시하면 오해를 부르므로 이번 UI에서는 사용하지 않는다. |

**리뷰 대상은 현재 매장 단위뿐이다.** `reviews`에는 `store_id` FK가 있고 `menu_id` 또는 메뉴 FK는 없다. `UNIQUE(store_id,user_id)` 역시 매장별 1건을 강제한다. 메뉴 단위 리뷰를 같은 테이블에 추가하면 대상 FK, 유일성, 공개 조건, 신고 및 통계 의미를 함께 재설계해야 한다. 따라서 이번 MVP는 매장 리뷰만 대상으로 하고 메뉴 단위는 별도 단계로 둔다.

## 5단계 선호도와 필요한 최소 변경

| 내부 `rating` | 사용자 표시 |
| ---: | --- |
| 5 | 매우 선호 |
| 4 | 선호 |
| 3 | 보통 |
| 2 | 비선호 |
| 1 | 매우 비선호 |

새 enum/컬럼 없이 기존 1–5 범위 검사를 사용할 수 있다. Flutter 모델은 이 숫자를 `PreferenceLevel` 같은 타입으로 감싸고 별 모양 UI나 `average_rating`을 선호도 라벨로 오인하지 않도록 한다. 값 1–5의 DB 내부 이름이 `rating`인 점은 코드 매핑에서 명시한다.

**필수 최소 마이그레이션: YES, 제안만.** 텍스트를 쓰지 않는 사용자는 `content=NULL`로 저장하고 공백만 입력하면 trim 후 NULL로 전환하는 방식을 권장한다. 현재 제약에서는 NULL도 빈 문자열도 허용되지 않는다. 기존 10–2,000자 규칙을 텍스트가 있을 때 유지하려면 다음과 같은 변경을 별도 마이그레이션으로 작성·로컬 RLS/REST 검증한 뒤, Production 적용 승인을 받아야 한다. 아래 SQL은 이번 작업에서 실행하지 않았다.

```sql
ALTER TABLE public.reviews ALTER COLUMN content DROP NOT NULL;
ALTER TABLE public.reviews DROP CONSTRAINT reviews_content_length;
ALTER TABLE public.reviews ADD CONSTRAINT reviews_content_length CHECK (
  content IS NULL OR (
    content = btrim(content, E' \t\r\n')
    AND char_length(content) BETWEEN 10 AND 2000
    AND content ~ '[^[:space:]]'
  )
);
```

기존 `public.public_reviews` 뷰의 `content`도 NULL이 될 수 있으므로 읽기 모델·UI를 같이 변경해야 한다. 이 변경은 `rating` 범위, `store_id` FK, 소유자 RLS를 바꾸지 않는다. 대안인 가짜 기본 문장으로 10자 제약을 채우는 방식은 실제 사용자가 쓴 텍스트처럼 보여 채택하지 않는다.

## 현재 접근 제어

- `reviews_public_read`: anon/authenticated는 **숨기지 않았고 verified+active 매장에 속한** 리뷰만 읽는다. `reviews_owner_manage_read`: authenticated 작성자는 본인 리뷰를 읽는다. 공개 뷰는 `security_invoker`로 이 권한을 따른다.
- `reviews_owner_insert`: `auth.uid() = user_id`, `can_contribute()`, 공개 매장, 숨김·모더레이션 값의 기본 상태를 요구한다. `reviews_owner_update`: 본인·기여 가능·공개 매장에 대해 `USING`과 `WITH CHECK`를 모두 적용한다. 클라이언트의 INSERT/UPDATE 컬럼 권한은 `store_id,rating,content` / `rating,content`로 제한된다. `reviews_owner_delete`는 본인 행만 허용한다.
- `can_contribute()`는 private schema의 고정 `search_path=pg_catalog`인 security-definer 함수다. 비익명 Auth 사용자에게 활성 상태의 본인 profile이 있고 `is_suspended=false`여야 한다. PUBLIC/anon에게 함수 실행 권한이 없다. 프로필은 닉네임 공개 읽기와 본인 관리 정책이 분리돼 있다.
- `review_reports_owner_insert`는 기여 가능한 로그인 사용자가 **자신이 쓰지 않은 공개 리뷰**를 신고할 때만 허용한다. 클라이언트에 신고 테이블 조회·수정·삭제 권한은 없다. Report UI는 MVP 뒤로 분리 가능하다.

## 현재 Flutter 연결과 다음 구현 단위

현재 `StoreDetailScreen`은 매장 정보·즐겨찾기·읽기 전용 메뉴만 표시한다. `lib/features/reviews/` 구현은 없으며 리뷰 Repository, 모델, 화면, 작성 동작도 없다. `AuthGate`는 공개 지도를 유지하면서 로그인 화면을 열고, 세션 생성 후 로그인 route를 닫는다. 닉네임이 없는 세션에는 `signedInNeedsProfile`과 별도 닉네임 화면이 있다. 그러나 현재 상세 화면은 로그인 콜백이나 로그인 후 돌아갈 리뷰 작성 의도를 전달받지 않는다. Review MVP에서 **선택한 매장 UUID를 유지한 로그인·닉네임 완료 후 복귀 경로**를 작게 연결해야 한다. 진입 시와 저장 직전 공개 매장 여부를 재검증하고, Auth 오류를 빈 리뷰 목록으로 취급하지 않아야 한다.

다음 phase의 권장 순서:

1. 위 선택형 `content` 마이그레이션을 새 파일로 작성하고 fresh local Supabase에서 실제 JWT/REST/RLS 테스트를 수행한다. Production에는 별도 승인 전 적용하지 않는다.
2. 기존 Supabase client와 Auth 상태를 사용해 매장별 공개 리뷰 읽기 및 본인 리뷰 조회·작성·수정·삭제 Repository와 1–5 선호도 모델을 추가한다. 공개 읽기는 `public_reviews`/현재 RLS, 작성은 `public.reviews`의 제한된 컬럼을 사용한다. 한 매장에 본인 리뷰가 있으면 새 INSERT 대신 수정 흐름을 보여주고, 실패·0건을 구분한다.
3. 상세 화면에 공개 리뷰 목록과 로그인 사용자 작성 UI를 최소 범위로 연결한다. 텍스트는 선택형, 선호도는 필수로 표시한다. 로그인·닉네임 복귀, 본인 소유권, 삭제 확인, 오류·재시도, 접근성, 권한 없는 시도와 매장 비공개 전환을 테스트한다. RLS를 우회하는 클라이언트 쓰기 경로를 만들지 않는다.

## 후속 기능과 신뢰 경계

`review_reports` 스키마와 INSERT 정책은 이미 있으므로 신고 UI와 운영 처리 흐름은 별도 phase로 둘 수 있다. `is_hidden` 및 moderation 메타데이터는 숨김의 기초를 제공하지만 운영자 도구·감사 기록은 아직 없다. `receipt_verified`, 점주 계정·권한, 메뉴 단위 리뷰 FK, 신뢰 가중치와 선호도 분포 통계는 현 스키마에 없으며 각각 실제 요구가 확정될 때 설계한다. 기존 `store_review_stats.average_rating`을 별점으로 노출하지 않는다.

이번 feature-unit의 Flutter 변경은 메뉴 섹션의 제목을 “확인된 메뉴”로, 성공 안내를 “현재 확인된 메뉴 정보입니다. 일부 메뉴가 누락되었거나 변경되었을 수 있습니다.”로, 빈 상태를 “아직 확인된 메뉴 정보가 없습니다.”로 바꾼 것뿐이다. `NULL` 가격의 “가격 정보 없음”, `is_signature=true`의 “대표”, 로딩·오류·재시도는 유지한다.
