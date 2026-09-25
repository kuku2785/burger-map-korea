# 용산 공개 매장 메뉴 MVP 근거 심사 — 2026-09-24

대상은 `burger-map-korea-dev` (`eoiwfprghyyguthdtayx`)이다. 이번 문서는 **등록용 데이터가 아닌 검토 기록**이다. Production `menus`는 작업 전후 0건이며, INSERT·UPDATE·DELETE는 하지 않았다.

## 현재 계약

`public.menus`는 `store_id`, `name`, nullable `price`, nullable `category`·`description`, `is_signature`, `is_active`, `display_order` 등을 지원한다. 메뉴별 근거 URL·확인일·가격 검증 상태를 담는 컬럼은 없다. 근거는 이 검토 문서에만 남긴다. 공개 SELECT는 `menus.is_active`와 소속 매장의 `verification_status = verified AND is_active = true`를 요구한다. Anon REST GET은 정상 응답으로 빈 목록을 반환했다.

Production에는 매장 280개, 공개 매장 237개가 있고, 현재 주소에 용산구가 포함된 공개 매장은 21개다. 이전 문서의 용산 25개 수치 대신 이 조회 결과를 사용했다.

## 파일럿 조사 대상

다음 5곳은 모두 현재 Production에서 verified + active로 확인됐다. 후보 메뉴는 매장당 1개씩만 기술적 dry run에 사용했고, 실제 등록 승인 데이터가 아니다.

| Store ID | 매장 | Production 주소 | 공개 메뉴 근거 후보 | 판정 |
| --- | --- | --- | --- | --- |
| `3ae148d2-a483-4268-9655-70ecbcb36d9d` | PPS | 서울 용산구 한강대로50길 24 | [테이블링](https://www.tabling.co.kr/place/677ccf0c66de5f069883cbde), [업체 페이지](https://www.daangn.com/kr/local-profile/pps-%ED%94%BC%ED%94%BC%EC%97%90%EC%8A%A4-aaask55ajnq3/) | 메뉴·가격 기준일 확인 불가, 플랫폼 표시 간 구성·금액 차이 |
| `2bfaa67c-0d29-4584-b4a7-372d3cadb637` | 르프리크 용산 | 서울 용산구 한강대로 37 | [테이블링](https://www.tabling.co.kr/place/677cd6eb66de5f069891d8a7), [뽈레](https://polle.com/place/5xAJQx/%EB%A5%B4%ED%94%84%EB%A6%AC%ED%81%AC), [다이닝코드](https://www.diningcode.com/profile.php?rid=BnxyUACBsNlQ) | 2026 특별 메뉴 이름·가격이 플랫폼 간 충돌 |
| `07ec2d49-9064-4814-9c37-2afa82e43836` | 롸카두들 이태원점 | 서울 용산구 녹사평대로40나길 9 | [테이블링](https://www.tabling.co.kr/place/677ccc4e66de5f06987ed7b3) | 가격 갱신일 없음 |
| `b91ee491-ff0d-4e16-8db8-f12847b8fd29` | 로우로우 버거샵 | 서울 용산구 신흥로 41-1 | [테이블링](https://www.tabling.co.kr/place/677cd88166de5f069894a0d3) | 가격 갱신일 없음 |
| `c86805d5-5f23-4776-8fa8-30ca8afce481` | 브루클린더버거조인트 동부이촌점 | 서울 용산구 이촌로 179 | [테이블링 주문 목록](https://www.tabling.co.kr/restaurant/12819) | 가격 갱신일 없음, 플랫폼 주소 177과 DB 주소 179 차이 재확인 필요 |

일부 공개 페이지는 현재 자동 조회가 제한됐다. 접근 가능한 페이지도 갱신 시점이 메뉴별 가격 기준일임을 보여주지 않는다. **현재 가격으로 확정한 메뉴는 0건**이다. `is_signature`도 독립 근거가 없으면 설정하지 않는다.

## Dry run과 적용 판정

Production SELECT와 후보 5행의 읽기 전용 `VALUES` 검증 결과: 대상 5행·매장 5곳, invalid FK 0, 비공개 매장 0, 기존/후보 중복 0, 이름 형식 오류 0, 후보 숫자 가격의 타입·범위 오류 0. 이는 후보 숫자의 **현재 가격 정확성**을 검증한 결과가 아니다. 가격 근거 승인 0/5이므로 전체 판정은 **FAIL**이다.

Production INSERT **0행**, 대상 매장 **0곳**, 보류 **5행**. 메뉴 0건의 다른 매장은 기존 빈 상태를 유지한다. 5곳의 지점별 최신 메뉴명·KRW 가격을 매장 공식 채널 또는 실제 주문 화면으로 확인하고, 출처 URL/화면·확인일·지점 주소를 검토한 뒤 새 dry run을 해야 한다. 게시용 행을 만들기 전까지 후보 가격을 앱에 노출하지 않는다.
