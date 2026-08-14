# Phase 2.0 Implementation Report

## 1. 목표

Phase 2.0의 목표는 외부 장소 API나 데이터베이스 없이, 사용자가 직접 검수해 제공한 이태원 햄버거 매장 3개의 이름, 주소, 좌표를 로컬 데이터로 넣고 Google Maps 위에 정확히 표시할 수 있는지 검증하는 것이다.

이번 단계에서는 Supabase, 공공데이터 수집, 외부 장소 API, 검색, 필터, 현재 위치, 마커 클러스터링, 로그인, 리뷰, 즐겨찾기, 광고, 결제, 관리자 기능을 구현하지 않았다.

## 2. 사용한 실제 매장 3개

| id | name | address | latitude | longitude | burgerStyle |
| --- | --- | --- | --- | --- | --- |
| itaewon-001 | 잭잭 이태원점 | 서울특별시 용산구 이태원로 134 | 37.5339066 | 126.988832 | 미분류 |
| itaewon-002 | 더리얼치즈버거 이태원 | 서울특별시 용산구 이태원동 453-14 | 37.5344938 | 126.9888993 | 미분류 |
| itaewon-003 | 노머시버거 | 서울특별시 용산구 보광로59길 26 1층 | 37.5339891 | 126.992491 | 미분류 |

## 3. 각 데이터의 검수 방식

세 매장의 id, 이름, 주소, 위도, 경도는 사용자가 직접 확인해 제공한 값을 그대로 사용했다. Codex는 Google Places API, Kakao Local API, NAVER 지역 검색 API를 호출하지 않았고, 웹 크롤링도 수행하지 않았다.

`burgerStyle`은 Phase 2.0에서 직접 확인된 값이 없으므로 임시 값인 `미분류`로 기록했다.

향후에는 각 매장별로 검수자, 검수일, 원본 확인 방식, 좌표 확인 방식, 변경 이력 등을 기록할 수 있는 단순한 provenance 필드를 별도로 설계하는 것이 좋다. 이번 단계에서는 복잡한 provenance 시스템을 구현하지 않았다.

## 4. 생성/수정 파일

생성:

- `lib/features/stores/data/itaewon_store_locations.dart`
- `test/features/stores/itaewon_store_locations_test.dart`
- `docs/phase-2-0-implementation-report.md`

수정:

- `lib/features/map/presentation/map_screen.dart`
- `lib/features/map/presentation/store_preview_card.dart`
- `test/features/map/map_marker_mapping_test.dart`
- `test/features/map/map_screen_widget_test.dart`

기존 Phase 1 더미 데이터 파일은 삭제하지 않았다.

## 5. 지도 초기 위치 변경

지도 초기 카메라는 서울 일반 중심 위치에서 이태원 파일럿 매장 주변으로 변경했다.

- center: `37.53415, 126.99007`
- zoom: `16`

## 6. 테스트 결과

검증 명령 결과는 다음과 같다.

- `dart format .`: 성공. 14개 파일 확인, 추가 포맷 변경 없음.
- `flutter analyze`: 성공. 이슈 없음.
- `flutter test`: 성공. 전체 테스트 통과.
- `flutter build apk --debug`: 성공.

## 7. 빌드 결과

Android debug APK가 생성되었다.

- output: `build/app/outputs/flutter-apk/app-debug.apk`

Codex 실행 세션에는 `GOOGLE_MAPS_API_KEY` 환경변수가 없어 실제 지도 렌더링까지 자동 실행 검증하지 않았다. API 키 값을 코드나 문서에 기록하지 않았다.

## 8. 사용자 수동 검증 항목

실제 지도 렌더링은 API 키와 에뮬레이터 화면 확인이 필요하므로 사용자가 직접 확인해야 한다.

- 초기 화면이 이태원 중심인지
- 실제 매장 마커 3개가 적절한 위치에 표시되는지
- 각 마커 위치가 사용자가 확인한 실제 주소와 맞는지
- 각 마커가 선택되는지
- 선택한 매장명과 주소가 상세 카드에 맞게 표시되는지
- 빈 지도 영역을 탭하면 상세 카드가 닫히는지
- 카메라 이동 후 debug center와 zoom 표시가 갱신되는지

## 9. 발견된 데이터 문제

- `burgerStyle`은 아직 직접 검수되지 않아 `미분류`로 남겨두었다.
- 주소 형식이 도로명 주소와 지번 주소로 섞여 있다.
- 좌표 검수 근거는 현재 문서에만 남아 있으며, 구조화된 검수 이력 필드는 아직 없다.
- 외부 장소 API의 응답, source_id, 전화번호, 장소 상세 값은 약관 확인 전까지 저장하지 않았다.

## 10. Phase 2.1 진행 전 권장사항

- 매장 데이터에 최소 검수 메타데이터를 붙일지 결정한다.
- 주소 표준을 도로명 주소 중심으로 정리할지 결정한다.
- 이태원 파일럿 데이터를 10개 내외로 늘리기 전에 좌표 검수 절차를 고정한다.
- 외부 길찾기 연결을 시작하기 전에 각 지도 사업자의 URL scheme 및 이용약관을 다시 확인한다.
- Supabase로 옮기기 전 로컬 데이터 모델과 DB 테이블 필드 매핑을 확정한다.
