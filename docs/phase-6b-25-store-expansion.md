# Phase 6B-1: 공개 매장 25곳 확대 가능성 평가

기준일: 2026-08-25

## 목표와 범위

현재 개발용 Supabase의 공개 매장은 `verified + active` 10곳이다. Phase 6B-1은
게시 검수표의 pending 14곳과 기존 hold 4곳, 총 18곳을 다시 조사하여 중간 목표
25곳까지 안전하게 확대할 수 있는지 평가한다.

Phase 6B-1은 조사와 제안만 수행했다. 이후 사용자가 안정 ID 기준 후보 13곳을 모두
명시적으로 승인했고, Phase 6B 승인 반영 단계에서 로컬 게시 검수표와 신규 INSERT SQL을
생성했다. SQL은 아직 원격에 실행하지 않았으며 Supabase와 Flutter 데이터는 변경하지
않았다.

## 안정 식별 원칙

- CSV 행 번호나 서로 다른 검수표의 번호를 매장 식별자로 사용하지 않는다.
- pending 매장은 `storeId + candidateId + sourcePlaceId`를 사용한다.
- hold 매장은 사용 가능한 `candidateId + discoveryId + sourcePlaceId`를 사용한다.
- `reviewItemId`는 위 안정 ID 조합의 SHA-256에서 결정적으로 생성한다.
- 이름이 같더라도 안정 ID, 주소, 좌표가 다르면 자동 연결하지 않는다.

## 입력과 출력

읽기 전용 입력은 게시 검수표, 스타일 검수표, staging CSV, hold report, Kakao 수동
검수 CSV와 상가정보 수동 검수 CSV다. 생성기는 실행 전후 SHA-256이 같은지 검사한다.

로컬 출력:

- `data/review/yongsan_burger_25_store_expansion_review.csv`
- `data/review/yongsan_burger_25_store_expansion_evidence.json`

두 파일은 Git에서 제외한다. 근거 URL, 매장별 판단 메모와 외부 장소 식별자는 Flutter
asset, 게시 SQL, 추적 문서로 복사하지 않는다.

## 조사 기준

현재 영업, 매장 동일성, 주소, 기존 좌표와의 충돌, 버거 전문성, 폐업·이전·교체 위험을
각각 판정했다. 공식 현재 매장 안내가 있거나 서로 독립된 최근 또는 현재 운영 신호 두
개가 일치할 때만 승인 제안을 허용했다. 주소·좌표·동일성에 중요한 충돌이 있거나 근거가
한 개뿐이면 목표 수를 채우기 위해 올리지 않았다.

버거 스타일은 게시 가능성과 별도다. 기존 스타일 검수가 완료된 값은 보존하고,
`unclassified + needs_recheck` 매장은 영업·주소·버거 전문성이 충분하면 스타일을
`unclassified`로 유지한 채 게시 승인 후보가 될 수 있다.

## 조사 결과

대상은 pending 14곳과 hold 4곳으로 정확히 18곳이며 중복은 없다. 기존 공개 10곳은
검수표에 포함되지 않았다.

| 추천 상태 | 수 |
| --- | ---: |
| `ready_for_user_approval` | 12 |
| `hold_resolved_ready_for_user_approval` | 1 |
| `needs_manual_check` | 2 |
| `hold_still_needs_manual_check` | 1 |
| `likely_closed_needs_user_decision` | 1 |
| `duplicate_or_replacement_needs_user_decision` | 1 |

승인 제안은 총 13곳이다. pending에서는 아메리칸치즈버거가 동명 매장 혼동 때문에,
스태커버거샵이 독립적인 최근 근거 부족 때문에 수동 확인으로 남았다.

hold에서는 다운타우너 한남의 기존 대사관로5길 주소가 두 공식 매장 안내와 일치하여
hold 해소 승인 후보가 됐다. 잭잭은 현재 공개 주소와 기존 주소·좌표가 충돌해 이전
가능성으로 hold를 유지한다. 버거운녀석들은 동일 주소의 다른 음식점 노출로 교체 가능성이
있고, 로스니버거는 최근 영업과 버거 전문성을 확인할 근거가 부족하다.

Phase 6B-1 조사 당시 어떤 행도 `verified`, `rejected`, `isActive=true`로 자동 변경하지
않았다.

## 25곳 가능성

현재 공개 10곳에 안전 게이트를 통과한 13곳을 모두 사용자가 승인해도 최대 23곳이다.
따라서 목표 25곳까지 2곳이 부족하다. 이번 단계에서 근거가 약한 매장을 승격하지 않는다.

다음 발견 단계는 용산구로 제한하고 최소 신규 후보 2곳보다 여유 있는 5곳만 수집한다.

1. 검색어는 `용산구 수제버거`, `효창 수제버거`, `후암 수제버거`, `이촌 수제버거`,
   `한남 수제버거`로 제한한다.
2. 결과 주소가 서울 용산구인지 다시 검사한다.
3. 현재 공개 10곳, 이번 검수 18곳, 기존 rejected·hold와 이름·주소·좌표를 대조한다.
4. 외부 장소 API를 사용하게 되면 사전 호출량 계산 후 최대 10회로 제한하고 원문 응답은
   저장하지 않는다.
5. 신규 후보는 항상 pending으로 만들고 사람의 별도 검수 전 승인·게시하지 않는다.

## 사용자 승인 결과와 로컬 반영

사용자는 2026-08-25에 승인 제안 13곳을 `reviewItemId` 기준으로 모두 승인했다. 승인
적용기는 일반 pending 후보 12곳의 `storeId + candidateId + 이름 + 주소 + 좌표`를
교차 검증하고, hold 후보 다운타우너 한남은 `candidateId + discoveryId + sourcePlaceId +
이름 + 주소 + 좌표 + hold 해소 판정`을 검증했다.

- 로컬 게시 검수표: 25행
- `publishDecision=verified + isActive=true`: 23행
- `publishDecision=pending + isActive=false`: 2행
- 기존 공개 승인: 10행, 모든 필드 불변
- 이번 신규 승인: 13행
- 자동 rejected: 0행
- 원격 공개 매장: 아직 10곳
- SQL 적용 후 예상 공개 매장: 23곳

기존 게시 검수표에는 중복 DB 상태 컬럼을 두지 않는다. `publishDecision=verified`는 SQL
생성 시 DB의 `verification_status=verified`로 매핑된다. `sourceAsOf`는 임의의 실행일이
아니라 Phase 6B 검수표의 `latestEvidenceAsOf`를 사용했고, `verifiedAt`은 한 번 결정한
KST 시각을 재실행에서도 보존한다.

노스트레스버거 해방촌점과 한남점은 서로 다른 `storeId`와 `candidateId`로 유지한다. 두
매장의 스타일은 게시 승인과 별개로 `unclassified`를 유지한다. 한남점에 대한 Phase 6A의
이전 제외 이력은 삭제하지 않았으며, 이번 사용자의 명시적 승인으로 철회됐음을 검수 메모에
기록했다.

다운타우너 한남은 기존 hold 자료와 공식 주소 검수 결과가 일치하는지 확인한 후 게시
검수표에 새 내부 UUID를 한 번만 부여했다. UUID와 승인 시각은 게시 검수표에 보존되며
재실행해도 바뀌지 않는다. 기존 hold report 원본은 수정하지 않았다.

## 신규 13행 INSERT SQL

생성 파일은 `data/staging/yongsan_burger_store_publish_25_expansion.sql`이며 Git에서
제외된다. SQL에는 이번 승인 13곳만 포함되고 기존 공개 10곳, pending 2곳과 hold 3곳은
포함되지 않는다. 내부 `candidateId`, `reviewItemId`, 외부 장소 ID·URL, 근거 메모와
비밀정보도 포함하지 않는다.

SQL은 명시적 컬럼 목록과 transaction을 사용하며 다음을 강제한다.

1. 실행 전 `public.stores` 전체 및 `verified + active` 행이 각각 10개여야 한다.
2. 신규 UUID 13개가 원격에 하나도 없어야 한다.
3. INSERT 영향 행이 정확히 13개여야 한다.
4. 실행 후 전체 및 `verified + active` 행이 각각 23개여야 한다.
5. 신규 이름·주소·좌표·스타일·출처·기준일·검수 시각이 로컬 값과 모두 같아야 한다.
6. 승인 후 공개 23곳 전체의 최종 스타일 분포가 `classic 14`, `other 3`,
   `chicken 2`, `smash 1`, `unclassified 3`이어야 한다. 이는 신규 13곳만의
   분포가 아니다.

조건이 하나라도 다르면 transaction 전체가 실패한다. 같은 SQL의 두 번째 실행은 전체
행 수 또는 기존 신규 UUID 사전 조건에서 안전하게 실패한다. UPDATE, DELETE, UPSERT,
RPC와 `ON CONFLICT`는 사용하지 않는다.

## 현재 중단점

사용자 승인, 로컬 검수표 반영과 SQL 생성은 완료됐다. 원격 Supabase SQL Editor 실행은
사용자가 SQL 해시와 사전 조건을 확인한 뒤 별도로 수행해야 한다. 원격 적용 후 23행과
스타일 분포를 조회하고 development + Supabase 모드에서 마커·필터·검색·상세·길찾기를
수동 검증하기 전까지 Phase 6B 전체를 완료로 표시하지 않는다. 목표 25곳까지 부족한 2곳의
제한된 용산구 신규 후보 조사도 아직 시작하지 않았다.

## 자동 검증

생성기 테스트는 pending 14·hold 4 추출, 공개 10곳 제외, 안정 ID, 이름만으로 연결 금지,
hold 사유 보존, 주소 충돌 차단, 약한 근거의 승인 제안 차단, 멱등성, 입력 불변, 부족분
계산과 최대 15곳 제한을 검증한다. 승인·SQL 테스트는 정확한 안정 ID 13개만 변경,
다중 식별 검증, hold UUID와 승인 시각 보존, 이전 제외 철회 기록, 기존 공개·미승인·hold
불변, 13행 전용 SQL, 사전·사후 조건과 재실행 방지를 검증한다. Flutter 코드·asset·패키지·
Android 설정은 변경하지 않았으므로 APK/AAB 빌드는 생략한다.

최종 자동 검증은 Python 149개와 Flutter 102개 테스트 통과, `flutter analyze` 이슈
0건, Dart 포맷 변경 0건이다. 로컬 SQL SHA-256은
`af4ecb3099906c8e8624ecb61f4fbe3d066346553e62fe6e1c32345f284ba312`다.
