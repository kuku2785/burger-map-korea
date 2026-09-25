# 용산 공개 메뉴 파일럿 근거 우선 심사 — 2026-09-24

대상 Production은 `burger-map-korea-dev` (`eoiwfprghyyguthdtayx`)다. 이 문서는 INSERT 승인 전 검토 기록이며, 실제 메뉴 데이터는 변경하지 않았다. 메뉴별 원문 URL·판정·가격은 [검토 CSV](menu-pilot-evidence-first-2026-09-24.csv)에 있다. 기존 [5개 매장 예비 조사](menu-pilot-evidence-review-2026-09-24.md)는 그대로 보존했다.

## 후보 풀과 선정

운영 DB의 `verified + active` 공개 매장은 237곳, 그중 주소가 용산구인 매장은 21곳이다. 21곳을 온라인 공식 채널·실제 주문 페이지 중심으로 넓게 검색했다. 아래 5곳에서 13개 버거 메뉴 후보를 확보했다. 이 중 가격 확정은 더백테라스의 셔틀 주문 페이지에 표시된 5개다. 나머지 8개 가격은 `NULL`로 둔다. 현재 운영 `menus`는 0건이다.

| 매장 | Store ID | 운영 DB 주소 | 가격 확인 | 가격 미확인 |
| --- | --- | --- | ---: | ---: |
| 더백테라스 신용산점 | `4632fe97-56f9-4aac-8f28-b9c916fa925d` | 서울 용산구 한강대로40길 26 | 5 | 0 |
| PPS | `3ae148d2-a483-4268-9655-70ecbcb36d9d` | 서울 용산구 한강대로50길 24 | 0 | 3 |
| 노스트레스버거 | `45ea2502-223c-45b3-9bc1-ca2465faa354` | 서울 용산구 신흥로 62 | 0 | 3 |
| N버거 | `d81b00f3-a142-42ad-b676-225122a5abb7` | 서울 용산구 남산공원길 105 | 0 | 1 |
| 더백푸드트럭 해방촌점 | `8bd06746-55ac-4cda-8621-6adf0f8dc312` | 서울 용산구 신흥로20길 45-1 | 0 | 1 |

## 근거 판정과 한계

- **Tier A, 더백테라스:** [셔틀 지점별 주문 페이지](https://www.shuttledelivery.co.kr/ko/restaurant/menu/1020)에서 매장 주소와 담기 가격을 확인했다. [메뉴명이 표시된 동일 페이지의 검색 색인](https://www.shuttledelivery.co.kr/ko/restaurant/menu/1020/zlib/lib/inftrees) 및 현재 페이지의 설명·가격 순서를 함께 대조했다. 웹 추출에서는 현재 페이지의 일부 메뉴명 제목이 비어 보인다. CSV의 가격은 **셔틀 주문 채널 표시가**이며 현장 가격과 같다고 주장하지 않는다. 더백버거의 `is_signature=true`는 페이지의 시그니쳐 버거 분류에 근거한다.
- **Tier B, PPS:** [주소가 일치하는 당근 동네업체 비즈프로필](https://www.daangn.com/kr/local-profile/pps-%ED%94%BC%ED%94%BC%EC%97%90%EC%8A%A4-aaask55ajnq3/)의 2026-09-04 수정 메뉴명 세 개를 사용한다. 당근은 [비즈프로필을 업체용 등록·관리 수단](https://business.daangn.com/business-profile/about)으로 설명한다. 직접 페이지 접근은 403이어서 검색 색인 내용으로 확인했다. `12,900원~` 등의 세트 시작가는 단품 확정 가격이 아니므로 저장하지 않는다. FRITAS BURGER의 대표 표시는 비즈프로필 근거다.
- **Tier B, 노스트레스버거:** [신흥로 62 비즈프로필](https://www.daangn.com/kr/local-profile/%EB%85%B8%EC%8A%A4%ED%8A%B8%EB%A0%88%EC%8A%A4%EB%B2%84%EA%B1%B0-sq9ttm4vov5h/)의 세 가지 치즈버거 메뉴명과 2026-06-02 수정 표시를 확인했다. 직접 접근은 403이고 검색 색인에서 관찰했다. `원~` 표시는 확정 가격으로 쓰지 않는다.
- **Tier B, N버거:** [CJ푸드빌의 2026년 공식 발표](https://www.nseoultower.co.kr/media/news/view.asp?idx=72)가 서울 불고기 버거를 대표 메뉴로 명시한다. [공식 매장 페이지](https://www.nseoultower.co.kr/eng/visit/restaurant5.asp)와 N서울타워 주소가 운영 DB에 부합한다. 공식 페이지가 연결한 메뉴 PDF는 존재하지만 본문을 읽지 못해 가격은 비워 둔다.
- **Tier B, 더백푸드트럭 해방촌점:** 더백테라스 [실제 주문 페이지의 매장 설명](https://www.shuttledelivery.co.kr/ko/restaurant/menu/1020)은 본점에서 판매하는 버거를 테라스에서도 판매한다고 말하며 더백버거를 현재 주문 메뉴로 표시한다. [본점의 지점별 대기 페이지](https://www.tabling.co.kr/restaurant/4862)가 신흥로20길 45-1과 더백버거를 교차 확인한다. **두 자료의 결합 추론**이므로 사용자 검토가 필요하고, 테라스 가격을 본점에 적용하지 않는다.

르프리크·벅벅·브루클린더버거조인트의 제3자 메뉴 3건은 `REJECT_UNVERIFIED`로 분리했다. 특히 브루클린더버거조인트 자료의 이촌로 177과 운영 DB의 179는 해결되지 않았다. 자코비버거의 주문 페이지에는 메뉴별 가격과 설명이 있지만 웹 추출에서 정확한 메뉴명이 보이지 않아 후보 행으로 옮기지 않았다. 다른 조사 매장은 현재 공식 메뉴 근거를 확보하지 못했다.

## 읽기 전용 dry run

검토 CSV는 총 16행: `VERIFIED_MENU_WITH_PRICE` 5행, `VERIFIED_MENU_PRICE_UNKNOWN` 8행, `REJECT_UNVERIFIED` 3행이다. 승인 검토 후보 13행은 매장 5곳에 걸친다. 로컬 CSV 형식 검사에서 UUID·메뉴명·가격/NULL·URL·표시 순서 오류 0, 후보 정규화 이름 중복 0이었다. Production에서는 `VALUES` 기반 **SELECT만** 실행했다.

| 검사 | 결과 |
| --- | ---: |
| 후보 / 대상 매장 | 13행 / 5곳 |
| 가격 확인 / 가격 미확인 | 5행 / 8행 |
| 존재하지 않는 FK / 비공개 매장 | 0 / 0 |
| 기존 메뉴 중복 / 후보 메뉴 중복 | 0 / 0 |
| 이름·가격·순서 형식 오류 / 매장별 순서 중복 | 0 / 0 |
| Production 메뉴 | 0행 |

숫자 조건인 매장 5곳, 검토 후보 13행, 가격 확인 5행은 충족한다. 근거 품질과 채널 가격의 표현 방식은 위 한계를 포함하여 **사용자 승인 대상**이다. `public.menus`에는 근거 URL·확인일이 없어 이 CSV를 별도 보존한다. 승인 전 Production INSERT는 **0행**, Flutter 코드·migration 변경은 **없다**.

## 로컬 검증 및 기기 상태

`flutter analyze --no-pub`는 문제 0건, `flutter test --no-pub`는 325/325 통과했다. 테스트는 메뉴를 Production에 넣거나 Android 실기기에서 메뉴를 표시한 결과가 아니다. 연결된 휴대폰은 `adb devices -l`에서 `unauthorized`로 표시되어 새 실기기 E2E를 수행하지 못했다. 앱 실행·Google 계정 선택·로그인/로그아웃·지도→상세→운영 메뉴 확인은 이번 실행에서 통과로 기록하지 않는다.
