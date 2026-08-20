# Phase 4C-B2 버거 스타일 승인 및 파생 데이터

## 목적과 범위

용산구 staging 매장 24곳의 대표 버거 스타일 검수 결과 중 사용자가 명시적으로 승인한 20곳만 `approved`로 반영한다. #6, #10, #18, #22는 승인하지 않았으며 `unclassified + needs_recheck + low`를 유지한다.

검수표 경로는 `data/review/yongsan_burger_style_review.csv`이며 Git에서 제외된다. 생성기는 staging, 게시 검수표, hold report를 읽어 ID와 입력 무결성을 검사하고 기존 검수 내용을 `candidateId` 기준으로 보존한다.

```powershell
python scripts/data/build_burger_style_review.py
```

Phase 4C-B1에서는 24곳 모두 비공식 출처 1개만 사용했고 `proposed 21`, `needs_recheck 3`, 공식 출처 0건이었다. B1R에서는 공식 출처 재탐색과 독립 출처 교차 검증을 거쳐 `ready_for_user_approval` 20곳을 만들었다. B2에서 사용자가 그 20곳의 제안 스타일을 그대로 승인했다.

## 분류 기준

한 매장에는 MVP용 대표 스타일 하나만 제안한다.

| 코드 | 의미 | 판정 기준 |
| --- | --- | --- |
| `classic` | 클래식 | 소고기 패티 중심의 일반 버거가 핵심이며 다른 전문 스타일 근거가 없음 |
| `smash` | 스매시 | 스매시 명칭 또는 얇게 눌러 굽는 조리 방식이 메뉴·설명에서 명확함 |
| `chicken` | 치킨 | 치킨버거가 매장의 핵심 콘셉트 또는 대표 메뉴군임 |
| `plant_based` | 비건·식물성 | 비건·식물성 버거가 핵심 콘셉트 또는 대표 메뉴군임 |
| `other` | 기타 | 슬라이더, 지역 특화, 퓨전 등 다른 명확한 대표 스타일이 있음 |
| `unclassified` | 미분류 | 근거 부족, 충돌, 최신성 또는 동일 지점 확인이 불충분함 |

매장명과 업종명만으로 분류하지 않는다. 사진만 보고 패티 조리법을 추측하지 않으며 여러 스타일이 비슷한 비중이거나 다른 지점의 근거만 확인되면 `unclassified`로 둔다.

## 근거와 상태 기준

출처 우선순위는 공식 메뉴·홈페이지, 공식 SNS, 공개 장소 플랫폼, 최근 메뉴 자료와 기사 순이다.

- 기준 A: 공식 홈페이지·메뉴·SNS에서 대표 스타일을 직접 확인하고 다른 근거와 충돌하지 않음
- 기준 B: 공식 출처가 없지만 서로 독립적인 공개 출처 2개 이상이 같은 대표 스타일을 지지하며 최소 1개에 실제 메뉴 정보가 있음
- `proposed`: 기준 A 또는 B를 만족하지만 아직 사용자가 승인하지 않은 제안
- `needs_recheck`: 출처가 하나뿐이거나 출처가 충돌하거나 대표 스타일 근거가 부족함
- `approved`: 사용자가 명시적으로 승인한 값. 생성기가 자동으로 만들지 않음

신뢰도 `high`는 공식 근거가 명확하거나 지점·주소·메뉴가 복수 출처에서 매우 구체적으로 일치한 경우다. `medium`은 공식 출처 없이 독립 출처 2개가 충돌 없이 일치한 경우다. `low`는 반드시 `needs_recheck + unclassified`와 함께 사용한다.

검수표에는 1차 근거에 더해 `secondaryEvidenceSourceType`, `secondaryEvidenceSourceName`, `secondaryEvidenceUrl`, `sourceAgreement`, `freshnessNote`, `approvalRecommendation`을 기록한다. `ready_for_user_approval`은 사용자 검토를 받을 준비가 됐다는 뜻일 뿐 자동 승인이 아니다.

## B2 승인 결과

| 번호 | 매장 | 제안 스타일 | 상태 | 신뢰도 | 출처 수 | 출처 일치 | 승인 권고 |
| ---: | --- | --- | --- | --- | ---: | --- | --- |
| 1 | 빌리언박스 이태원본점 | 기타 | approved | medium | 2 | consistent | ready_for_user_approval |
| 2 | 르프리크 용산 | 치킨 | approved | medium | 2 | consistent | ready_for_user_approval |
| 3 | 캘프 효창 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 4 | 바스버거 후암점 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 5 | 브루클린더버거조인트 동부이촌점 | 클래식 | approved | high | 2 | consistent | ready_for_user_approval |
| 6 | 아메리칸치즈버거 | 미분류 | needs_recheck | low | 1 | single_source | needs_manual_check |
| 7 | N버거 | 기타 | approved | high | 1 | consistent | ready_for_user_approval |
| 8 | PPS | 스매시 | approved | medium | 2 | consistent | ready_for_user_approval |
| 9 | 버거스낵 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 10 | 노스트레스버거 | 미분류 | needs_recheck | low | 2 | conflict | needs_manual_check |
| 11 | 더백테라스 신용산점 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 12 | 바나나그릴 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 13 | 더백푸드트럭 해방촌점 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 14 | 버거인 | 기타 | approved | medium | 2 | consistent | ready_for_user_approval |
| 15 | 더리얼치즈버거 이태원 | 클래식 | approved | high | 2 | consistent | ready_for_user_approval |
| 16 | 한강버거 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 17 | 로우로우 버거샵 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 18 | 스태커버거샵 | 미분류 | needs_recheck | low | 1 | single_source | needs_manual_check |
| 19 | 롸카두들 이태원점 | 치킨 | approved | high | 2 | consistent | ready_for_user_approval |
| 20 | 벅벅 이태원점 | 클래식 | approved | high | 2 | consistent | ready_for_user_approval |
| 21 | 노머시버거 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 22 | 노스트레스버거 한남점 | 미분류 | needs_recheck | low | 2 | single_source | needs_manual_check |
| 23 | 자코비버거 이태원점 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |
| 24 | 바스버거 신용산점 | 클래식 | approved | medium | 2 | consistent | ready_for_user_approval |

집계는 다음과 같다.

- 공식 출처 확보: 1곳
- 공식 출처 없음: 23곳
- 독립 출처 2개 이상 확보: 21곳
- 독립 출처 2개가 같은 스타일을 지지해 기준 B 충족: 19곳
- 단일 출처만 확보: 2곳
- 출처 충돌: 1곳
- 메뉴 스타일을 뒷받침하는 출처가 사실상 1개뿐인 2출처 행: 1곳
- 승인 권고: `ready_for_user_approval 20`, `needs_manual_check 4`
- 상태: `approved 20`, `needs_recheck 4`, `proposed 0`
- 신뢰도: `high 5`, `medium 15`, `low 4`
- 스타일: `classic 14`, `smash 1`, `chicken 2`, `plant_based 0`, `other 3`, `unclassified 4`

N버거는 2026년 공식 리뉴얼 자료가 기존 플랫폼 메뉴보다 최신이어서 1차 근거를 교체했다. 공식 자료의 서울불고기버거와 K-스타일 시그니처 설명을 근거로 기존 `classic` 제안 대신 `other`를 제안한다. 교체 이유는 `reviewerNote`에 남겼다.

## 승인 및 재확인 구분

`ready_for_user_approval` 20곳은 사용자가 제안 스타일을 명시적으로 승인해 `approved`로 변경했다. 각 행의 `reviewerNote`에는 Phase 4C-B2 사용자 승인 사실과 승인 스타일을 기록했다. 승인 권고 필드는 근거 검토 당시 상태를 보존한다.

다음 4곳은 `needs_manual_check`다.

- #6 아메리칸치즈버거: 매장과 주소만 확인됐고 최신 메뉴·대표 콘셉트 근거가 1개뿐임
- #10 노스트레스버거: 스매시 소개와 클래식 치즈버거 메뉴 사이 충돌이 남음
- #18 스태커버거샵: 출처가 1개이고 치킨·새우·치즈버거 비중이 비슷해 대표 스타일을 정하기 어려움
- #22 노스트레스버거 한남점: 출처는 2개지만 메뉴 스타일을 뒷받침하는 근거는 1개뿐이고 다른 지점 정보를 대신 적용할 수 없음

## 한계와 최신성

공식 출처가 없는 매장은 공개 장소 플랫폼과 독립 보조 자료를 사용했다. 이런 페이지는 운영 주체가 아니며 메뉴·주소·영업 상태가 늦게 갱신되거나 사용자 작성 내용이 섞일 수 있다. 같은 플랫폼의 복제 페이지는 독립 출처로 세지 않았고 검색 결과 제목만으로 판정하지 않았지만 비공식 출처 기반 분류에는 여전히 한계가 있다.

출처 정보는 시간이 지나면 달라질 수 있다. 실제 데이터 반영 직전에 지점·주소·대표 메뉴·영업 상태를 다시 확인하고 오래되거나 사라진 근거는 `needs_recheck`로 되돌린다.

## 파생 데이터 반영 구조

1. 원본 staging CSV와 스타일 검수표를 `candidateId`로 1:1 연결한다.
2. 이름·주소·UUID 연결을 검증하고 `approved` 스타일만 개발용 JSON에 반영한다.
3. 미승인 행은 파생 JSON에서도 `unclassified`로 유지한다.
4. 게시 INSERT SQL을 향후 생성할 때도 선택적 style-review 입력으로 승인 스타일만 사용할 수 있다.
5. 스타일 승인은 매장의 `publishDecision`, `isActive`, `verification_status`를 변경하지 않는다.

원본 staging CSV와 게시 검수표는 수정하지 않았다. 개발용 asset은 `assets/dev/yongsan_burger_stores_staging.json`에 파생 생성했으며 24행의 스타일 분포는 `classic 14`, `smash 1`, `chicken 2`, `other 3`, `unclassified 4`다.

현재 Supabase에 게시된 매장과 교차하면 노머시버거 1곳만 `approved + verified + active` 조건을 만족한다. `data/staging/yongsan_burger_style_update.sql`은 해당 UUID의 `burger_style`만 `classic`으로 변경하도록 생성했다. 나머지 승인 매장 19곳은 게시되지 않았으므로 UPDATE 대상이 아니다.

## B2 자동 검증

- Python 데이터 파이프라인 테스트: 95개 통과
- `dart format .`: 변경 없음
- `flutter analyze`: 이슈 0건
- Flutter 테스트: 75개 통과
- development + staging Android debug APK 빌드 성공
- 승인 검수표·개발 asset·UPDATE SQL 재실행 전후 SHA-256 동일

## B2 staging 수동 검증

2026-08-20 사용자가 Android 에뮬레이터의 development + staging 모드에서 다음을 직접 확인했다.

- 매장 마커 24개 로딩
- 필터 순서 `전체 → 클래식 → 스매시 → 치킨 → 기타 → 미분류`
- 스타일별 필터링
- `PPS` 검색과 `스매시` 필터의 AND 결합
- 승인 매장의 상세 화면에 승인 스타일 표시
- 미승인 4곳의 상세 화면에 `아직 분류되지 않았습니다.` 표시
- 검색·필터·상세 화면 왕복 후 상태 유지

`plant_based`로 승인된 매장이 없어 `비건·식물성` 필터가 표시되지 않는 것도 확인했다.

## Supabase 적용 결과

사용자가 개발용 Supabase SQL Editor에서 생성된 UPDATE SQL을 정확히 한 번 실행했다. UPDATE 대상은 노머시버거 1행이며 변경 필드는 `burger_style`뿐이다.

- `burger_style = classic`
- `verification_status = verified` 유지
- `is_active = true` 유지
- INSERT, DELETE, UPSERT 미실행
- 다른 매장 데이터, migration, RLS 변경 없음

이후 development + supabase 모드에서 노머시버거 마커, `전체·클래식` 필터, 상세 화면의 `클래식·검수 완료`, 검색과 뒤로가기 상태 유지를 사용자가 확인했다. 이미 적용한 UPDATE SQL은 재실행하지 않는다.

## 안전 장치

생성기는 B1 검수표를 B1R 스키마로 이관할 때 기존 근거와 수동 입력을 보존하고 교차 검증 전 제안을 안전하게 `needs_recheck`로 낮춘다. 24행과 순서, UUID·candidateId 중복, 이름·주소, 좌표, staging과 게시 검수표 연결, hold 4곳 미포함을 검증한다.

또한 `single_source + proposed`, `conflict + proposed`, `low + proposed`, 근거 없는 비공식 `proposed`, `needs_manual_check + proposed`, 사용자 메모 없는 `approved`를 차단한다. 오류 시 임시 파일을 최종 출력으로 교체하지 않으며 입력 CSV의 SHA-256이 바뀌면 중단한다.

구현과 자동 검증 과정에서는 외부 장소 API와 Supabase 원격 접속을 사용하지 않았다. 원격 UPDATE는 생성된 SQL을 사용자가 SQL Editor에서 한 번 수동 실행했으며 기존 게시 INSERT SQL은 재생성하거나 재실행하지 않았다. 실제 프로젝트 이름, 프로젝트 식별자, URL, 키와 DB 비밀번호는 문서와 추적 파일에 기록하지 않는다.
