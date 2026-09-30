# Review Report + Minimal Moderation MVP

## 범위와 저장 계약

공개된 타인의 리뷰 카드에서 로그인한 사용자가 신고할 수 있다. 비로그인 사용자는 기존 로그인·닉네임 설정 흐름을 거쳐 같은 매장과 리뷰의 신고 화면으로 돌아온다. 신고 접수 자체는 리뷰를 숨기거나 삭제하지 않는다. 한 계정은 같은 리뷰를 한 번만 신고할 수 있으며, 자신의 리뷰 신고는 DB 정책으로도 거부된다.

기존 `20260922050439_auth_menu_reviews.sql`과 Production 확인 결과, `review_reports`는 신고 ID, 대상 리뷰 FK, 신고자 FK, 사유, 선택 설명, `pending/resolved/dismissed` 상태, 생성·수정 시각, 처리 메모·담당자·처리 시각을 갖는다. `(review_id, reporter_user_id)` UNIQUE와 타인·공개 리뷰에만 INSERT를 허용하는 RLS가 이미 있다. 일반 클라이언트에는 신고 INSERT의 `review_id`, `reason`, `detail` 열만 허용되고 SELECT/UPDATE/DELETE 권한은 없다. 운영 열과 신고자 ID는 클라이언트가 지정하지 않는다. 이번 작업의 신규 migration은 없다.

## 신고 사유

| 화면 사유 | 저장 reason | detail 규칙 |
| --- | --- | --- |
| 욕설·비방 | `harassment` | 선택 |
| 개인정보 노출 | `personal_information` | 선택 |
| 광고·도배 | `spam` | 선택 |
| 허위 정보 의심 | `other` | `허위 정보 의심` 접두어를 저장하고 추가 설명은 선택 |
| 매장/버거와 무관 | `irrelevant` | 선택 |
| 기타 | `other` | 설명 필수 |

현재 DB의 허용 reason은 위 다섯 값뿐이다. `false_information`을 새 값으로 추가하지 않고 `other` + 고정 접두어로 구분한다. detail은 양끝 공백을 제거하고 1000자 이내로 저장한다. 접두어 길이를 고려해 화면 입력은 990자로 제한한다. 신고 화면은 원시 DB 오류를 표시하지 않으며, 성공·이미 신고함·실패·결과 불확실을 구분한다. 결과 불확실 시 즉시 재제출을 막는다.

## 운영자 검토 절차

별도의 앱 관리자 화면은 만들지 않는다. 권한 있는 운영자가 Supabase Dashboard 또는 제한된 운영 도구에서 `review_reports.status = 'pending'`을 조회하고 대상 `reviews` 및 매장 공개 상태를 대조한다. 신고 사유와 설명만으로 결론 내리지 않고, 문제되는 표현·개인정보·광고·매장 무관 여부를 직접 확인한다. 허위 정보 의심은 근거를 추가 확인한다.

신고가 근거 없거나 단순한 부정적 경험·낮은 선호도·가격 불만이면 리뷰를 유지하고 신고를 `dismissed`로 기록한다. 정책 위반이 확인되면 리뷰 행을 삭제하지 않고 `is_hidden = true`, `moderation_note`, `moderated_at`, `moderated_by`를 함께 기록하고 신고를 `resolved`로 기록한다. 모든 비대기 상태에는 `resolution_note`, `resolved_at`, `resolved_by`를 남긴다. 운영자는 대상 리뷰와 신고 행을 다시 확인하고, 공개 목록과 통계에서 빠졌는지 확인한다. 이 절차는 권한 있는 운영 경로에서만 수행하며 앱 클라이언트나 일반 사용자 토큰에 운영 권한을 주지 않는다.

`public_reviews`와 `store_review_stats`는 DB에서 `NOT is_hidden`을 적용하며 `security_invoker` 뷰다. 숨긴 리뷰는 공개 조회·통계에서 제외되지만 원본 행과 신고 기록은 감사용으로 유지된다. 작성자는 기존 소유자 조회 정책에 따라 자신의 숨겨진 리뷰를 볼 수 있다. 실제 Production 운영 조치는 이번 단계에서 수행하지 않았다.

## 후속 범위

AI 자동 조정, 욕설 ML, 평판 점수, 영수증 인증, 점주 이의제기 화면, 좋아요, 댓글, DM, 공개 사용자 평판, 신고 수에 따른 자동 삭제는 이번 MVP에 포함하지 않는다.
