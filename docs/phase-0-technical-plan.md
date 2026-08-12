# Burger Map Korea Phase 0 Technical Plan

작성일: 2026-08-06

현재 결정: Phase 1은 Google Maps 기술 스파이크로 축소한다.

## 0. 확정 사항

1. MVP의 기본 지도 제공자는 Google Maps로 한다.
2. Google Places API는 매장 DB의 원천으로 사용하지 않는다.
3. 매장 데이터는 공공데이터, 직접 검수, 사용자 및 점주 제보를 기반으로 별도의 Supabase DB에서 관리한다.
4. 네이버지도, 카카오맵, 구글지도는 향후 외부 길찾기 연결 대상으로 사용한다.
5. 초기 공개 데이터 범위는 전국이 아니라 서울의 검수된 수제버거 매장부터 시작한다.
6. 현재 단계에서는 Supabase, 공공데이터 수집, 로그인, 광고, 리뷰를 구현하지 않는다.

## 1. 지도 제공자 비교 요약

| 기준 | Google Maps | NAVER Maps | Kakao Maps |
| --- | --- | --- | --- |
| 공식 Flutter 지원 | 높음. `google_maps_flutter` 공식 패키지 사용 가능. | 낮음. 공식 Flutter SDK는 확인되지 않음. | 낮음~중간. 공식 Flutter 지도 SDK는 확인되지 않음. |
| Android/iOS 동시 출시 | 가장 낮은 난이도. | 커뮤니티 패키지 또는 네이티브 브리지 필요. | 커뮤니티 패키지 또는 네이티브 브리지 필요. |
| 지도/마커 | 공식 패키지로 지도와 마커 지원. | 네이티브 SDK는 강하지만 Flutter 연동 검증 필요. | 네이티브 SDK는 강하지만 Flutter 연동 검증 필요. |
| 국내 적합성 | POI/주소 품질은 검증 필요. | 국내 지도/장소 품질 강점. | 국내 지도/장소 품질 강점. |
| 비용 | Maps SDK는 현재 가격표상 무료 사용량이 크지만 결제 계정 필요. | 무료 한도는 크지만 NCP 과금 정책 확인 필요. | 무료 쿼터와 2026년 이후 과금 정책 확인 필요. |
| 장소 API 저장 위험 | Places 콘텐츠 장기 저장 제한이 강함. | 지역정보 별도 DB화 금지 예시 확인. | Local API 응답 별도 저장 금지 안내 사례 확인. |
| 장기 유지보수 | 공식 Flutter 패키지라 가장 유리. | Flutter 의존성 리스크 있음. | Flutter 의존성 리스크 있음. |

결론: Phase 1에서는 Google Maps 공식 Flutter 패키지의 Android/iOS 동작 가능성만 검증한다. 국내 지도 품질이나 장기 제공자 교체 여부는 Phase 1 결과를 보고 다시 판단한다.

## 2. 데이터 원칙

매장 DB의 영구 원천은 다음으로 제한한다.

- 공공데이터포털 상가업소 데이터
- 운영자가 직접 확인하고 검수한 사실 데이터
- 사용자가 제출하고 운영자가 승인한 제보
- 점주가 권한을 가지고 제공하고 운영자가 승인한 정보

외부 장소 API는 약관 검토가 끝나기 전까지 다음 데이터를 저장하지 않는다.

- API 원문 응답
- `source_id`, place id, kakao id, naver id 등 외부 장소 식별자
- API에서 받은 주소
- API에서 받은 좌표
- API에서 받은 전화번호
- API에서 받은 영업시간, URL, 카테고리, 사진, 리뷰, 평점

약관 확인 전 외부 장소 API는 호출하지 않는다. 특히 Google Places API, Kakao Local API, NAVER 지역/검색 API는 Phase 1 범위에서 제외한다.

## 3. 초기 데이터 목표

초기 공개 목표는 서울의 검수된 수제버거 매장 100개다.

전국 데이터는 내부 후보 데이터로만 다룬다. 운영자가 검수하기 전에는 사용자에게 노출하지 않는다. 전국 확장은 서울 100개 매장의 지도 표시, 상세 품질, 검수 흐름, 사용자 반응을 확인한 뒤 진행한다.

## 4. MapProvider 방침

Phase 1에서는 지도 위젯 자체를 범용 `MapProvider`로 과도하게 추상화하지 않는다.

대신 다음 원칙만 지킨다.

- 매장 도메인 모델은 Google Maps SDK 타입에 의존하지 않는다.
- 지도 화면 안에서만 `LatLng`, `Marker`, `GoogleMap` 같은 SDK 타입으로 변환한다.
- 지도 제공자 교체가 필요해졌을 때 추상화를 도입한다.
- 현재는 Google Maps 단일 구현으로 카메라 이동, 지도 로딩, 마커 탭, API 키 미설정 상태를 검증한다.

## 5. Phase 1 - Google Maps 기술 스파이크

목표:

1. Flutter 프로젝트 생성 또는 기존 Flutter 프로젝트 상태 점검
2. Android 및 iOS 프로젝트 기본 설정
3. Google Maps 공식 Flutter 패키지 연결
4. API 키를 코드와 분리할 수 있는 환경설정 구조
5. Google Maps를 표시하는 단일 지도 화면
6. 서울 지역의 더미 햄버거 매장 3개 표시
7. 마커 선택 시 매장명과 임시 상세 카드 표시
8. 카메라 이동 완료 이벤트 확인
9. 지도 로딩, 오류, API 키 미설정 상태 처리
10. 최소한의 테스트와 실행 문서 작성

제외:

- Supabase 연결
- 실제 공공데이터 다운로드
- 실제 매장 API 호출
- Google Places API
- Kakao Local API
- NAVER 지역 검색 API
- 로그인, 회원가입, 검색, 필터
- 마커 클러스터링
- 현재 위치 권한
- 즐겨찾기, 방문 기록, 리뷰, 매장 제보
- 관리자 기능, AdMob, 결제, 앱스토어 배포

## 6. Phase 1 기술 스파이크 파일 목록

- `pubspec.yaml`
- `README.md`
- `.env.example`
- `lib/main.dart`
- `lib/app/app.dart`
- `lib/app/app_theme.dart`
- `lib/core/config/app_config.dart`
- `lib/features/map/presentation/map_screen.dart`
- `lib/features/stores/domain/store_location.dart`
- `lib/features/stores/data/dummy_store_locations.dart`
- `test/core/config/app_config_test.dart`
- `test/features/stores/dummy_store_locations_test.dart`
- `test/features/map/map_marker_mapping_test.dart`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `ios/Runner/AppDelegate.swift`
- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`

## 7. 전체 개발 파일 목록

Phase 1 이후 승인을 받아 단계적으로 만든다.

### App Core

- `lib/core/network/*`
- `lib/core/result/*`
- `lib/core/logging/*`
- `lib/core/navigation/external_map_link_builder.dart`

### Store Data

- `lib/features/stores/domain/store.dart`
- `lib/features/stores/domain/store_source.dart`
- `lib/features/stores/data/store_repository.dart`
- `lib/features/stores/data/store_api.dart`
- `lib/features/stores/presentation/store_detail_screen.dart`

### Supabase

- `supabase/migrations/0001_init_store_schema.sql`
- `supabase/migrations/0002_rls_policies.sql`
- `supabase/seed/seoul_verified_sample.sql`
- `docs/database-schema.md`
- `docs/data-source-policy.md`

### Data Pipeline

- `scripts/data/README.md`
- `scripts/data/public_store_import.*`
- `scripts/data/normalization_rules.md`
- `scripts/data/deduplication_rules.md`
- `docs/data-dictionary.md`

### Future Features

- `lib/features/search/*`
- `lib/features/filters/*`
- `lib/features/favorites/*`
- `lib/features/visits/*`
- `lib/features/submissions/*`
- `admin/*`

## 8. 기술 검증 항목

Phase 1에서 확인한다.

- Android에서 Google Maps SDK 키 주입 후 지도 표시 여부
- iOS에서 Google Maps SDK 키 주입 후 지도 표시 여부
- API 키 미설정 시 앱이 크래시 없이 안내 화면을 표시하는지
- 서울 더미 매장 3개 마커 표시 여부
- 마커 선택 시 상세 카드 표시 여부
- 카메라 이동 완료 이벤트 수신 여부
- `dart format .`, `flutter analyze`, `flutter test`, 가능한 경우 Android debug build 통과 여부

Phase 2 이후 확인한다.

- 서울 검수 매장 100개를 로컬/원격 DB에서 로딩할 때 성능
- Supabase schema와 RLS
- 공공데이터 원천 이용허락과 출처 표시
- 외부 지도 앱 길찾기 링크
- 외부 장소 API 약관 공식 확인

## 9. 참고 자료

- Google Maps Flutter package: https://pub.dev/packages/google_maps_flutter
- Google Maps Platform pricing: https://developers.google.cn/maps/billing-and-pricing/pricing?hl=en
- Google Places API policies: https://developers.google.com/maps/documentation/places/web-service/policies
- Google Maps Platform service specific terms: https://cloud.google.com/maps-platform/terms/maps-service-terms/index-20240522
- NAVER API terms: https://developers.naver.com/products/terms/
- Kakao Local REST API: https://developers.kakao.com/docs/en/local/dev-guide
- 공공데이터포털 이용정책: https://www.data.go.kr/ugs/selectPortalPolicyView.do
