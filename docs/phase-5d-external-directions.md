# Phase 5D-A 외부 길찾기

## 목적

지도에서 검수 매장을 선택하고 상세 정보를 확인한 사용자가 외부 Google Maps에서 해당 매장까지의 길찾기를 이어갈 수 있게 한다. 이번 단계는 별도 경로 계산 API나 앱 내 위치 기능을 추가하지 않고 기존 지도 → 선택 카드 → 상세 흐름에 단일 행동을 연결한다.

## 사용자 흐름

1. 지도 마커 또는 검색 결과에서 매장을 선택한다.
2. 기존 선택 카드에서 `상세보기`를 누른다.
3. 상세 화면에서 `길찾기`를 누른다.
4. 외부 Google Maps 또는 지원되는 브라우저가 매장명과 주소를 목적지로 열어 준다.
5. 사용자가 출발지와 이동 수단을 직접 선택한다.
6. 앱으로 돌아오면 기존 지도, 검색어, 스타일 필터, 선택 카드 상태를 유지한다.

상세 화면은 이미 로딩된 동일 `StoreLocation`을 사용한다. 진입이나 길찾기 실행 때문에 Supabase 또는 store loader를 다시 호출하지 않는다.

## Google Maps URL 규격

Google Maps URLs 공식 directions 형식을 사용한다.

```text
https://www.google.com/maps/dir/?api=1&destination=<store name, full address>
```

- `api=1`: 포함
- `destination`: 선택 매장의 화면 표시용 매장명과 전체 주소 포함
- `origin`, `travelmode`, `dir_action`: 제외
- 내부 ID, 외부 Place ID, API key: 제외

매장명과 주소는 사용자가 목적지를 식별할 수 있도록 `destination`에 포함한다. 이름 또는 주소가 비어 있으면 검증된 위도·경도만 fallback으로 사용한다. Google Place ID가 없으므로 `destination_place_id`를 만들거나 Kakao Place ID를 대신 사용하지 않는다.

URL은 문자열 연결 대신 Dart `Uri.https`와 `queryParameters`로 생성한다. Google Maps URLs는 별도 Directions API 또는 Routes API 호출이 아니며 추가 Google API key가 필요하지 않다.

참고:

- https://developers.google.com/maps/documentation/urls/get-started
- https://pub.dev/packages/url_launcher

## 구조

- `google_maps_directions.dart`: 매장명·주소 우선 목적지, fallback 좌표 검증, directions `Uri` 생성 순수 로직
- `external_uri_launcher.dart`: 외부 URL 실행 추상화와 `url_launcher` 어댑터
- `store_detail_screen.dart`: 버튼 상태, 중복 탭 방지, 사용자 실패 안내

`url_launcher 6.3.2`를 직접 의존성으로 사용한다. `canLaunchUrl`로 미리 차단하지 않는다. 먼저 `externalNonBrowserApplication`으로 지도 앱 실행을 시도하고 성공하면 종료한다. 지원되지 않거나 `false` 또는 예외가 발생하면 같은 HTTPS URL을 `externalApplication`으로 한 번만 fallback한다.

## 좌표 및 실패 처리

정상 매장은 trim한 매장명과 주소를 `매장명, 주소` 형식으로 사용한다. 이름 또는 주소가 비어 좌표 fallback이 필요할 때 위도는 유한한 `-90..90`, 경도는 유한한 `-180..180`만 허용한다. NaN, Infinity, 범위 밖 값은 launcher 호출 전에 거부한다. fallback 좌표 문자열은 Dart의 locale 비의존 소수점 형식으로 만들고 불필요한 후행 0을 제거한다.

launcher가 `false`를 반환하거나 예외가 발생하면 상세 화면을 유지하고 다음 SnackBar만 표시한다.

```text
지도 앱을 열 수 없습니다. 잠시 후 다시 시도해 주세요.
```

URL, 좌표, 예외 원문, stack trace는 사용자 화면이나 production 로그에 노출하지 않는다. 실행 중에는 버튼을 비활성화해 여러 외부 창이 열리는 것을 방지한다.

## 개인정보·비용 영향

- 앱은 출발지를 지정하지 않는다.
- 위치 권한을 추가하거나 현재 위치를 수집·저장하지 않는다.
- 위치 추적과 분석 이벤트를 추가하지 않는다.
- Google Directions API, Routes API, 장소 API 또는 Supabase 추가 요청이 없다.
- Google Maps URL 실행 자체를 위한 별도 API key와 API 사용료가 없다.

외부 Google Maps가 처리하는 위치·계정·사용 기록은 해당 외부 서비스의 설정과 정책을 따른다.

## 자동 검증

- URL parameter 포함·제외와 좌표 경계 검증
- launcher 성공, `false`, 예외, 중복 탭 검증
- 비브라우저 앱 우선 실행과 HTTPS 외부 application fallback 검증
- 완료된 첫 번째·두 번째·세 번째 탭에서 동일 목적지 재전달 검증
- 주소 복사와 상세 표시 회귀
- 작은 화면과 2배 텍스트 크기 overflow 검증
- 상세 진입·길찾기·복귀 중 store loader 1회 유지
- 위치 권한, 경로 계산 API, Supabase 쓰기 경로 부재 검증
- Flutter/Python 전체 테스트, analyze, debug APK, signed release AAB 검증
- release AAB staging asset과 비밀 패턴 부재 검증

2026-08-24 결과:

- `dart format .`: 29개 파일, 변경 0
- `flutter analyze --no-pub`: 이슈 0
- Flutter 테스트: 102개 통과
- Python 테스트: 116개 통과
- debug APK: `build/app/outputs/flutter-apk/app-debug.apk` 빌드 성공
- signed release AAB: `build/app/outputs/bundle/release/app-release.aab` 빌드 성공
- release application ID: `com.burgermapkorea.app`
- `jarsigner -verify`: `jar verified`
- release staging entry, AssetManifest staging 참조, staging 식별 값: 모두 0
- release Google API key, Supabase URL·key·JWT 패턴: 모두 0
- release key.properties, keystore, CSV, SQL entry: 모두 0
- Flutter Supabase 쓰기 경로, 위치 권한, Directions/Routes API HTTP 호출: 모두 0

## 수동 검증 이력

### 최초 검증 실패

2026-08-24 사용자가 development staging의 PPS 상세 화면에서 확인했다.

- 첫 실행에서 외부 Google Maps는 열렸지만 목적지에는 위도·경도만 전달되어 `PPS` 이름이 표시되지 않았다.
- 앱으로 돌아온 뒤 두 번째 실행에서 Google Maps는 열렸지만 목적지가 다시 적용되지 않았다.
- 에뮬레이터 현재 위치가 미국으로 표시된 것은 기본 GPS 위치 문제이며 앱 결함으로 판정하지 않았다.

당시 구현은 좌표-only `destination`과 단일 `externalApplication` 호출을 사용했다. UI의 중복 방지 상태는 성공·실패·예외 모두 `finally`에서 해제되고 있었으므로 버튼 고착은 확인되지 않았다. 그러나 반복 완료 실행을 검증하는 테스트가 없었고, 일반 외부 application 실행만으로 지도 앱 우선 전달과 재적용을 보장하지 못했다.

### 교정

- 정상 목적지를 `매장명, 전체 주소`로 변경
- 이름 또는 주소가 비어 있을 때만 검증된 좌표 fallback
- `externalNonBrowserApplication` 성공 시 종료
- primary 실패 또는 예외 시 `externalApplication` HTTPS fallback
- 첫 번째·두 번째·세 번째 실행과 실패 후 재시도 자동 테스트 추가

교정 후 자동 테스트를 먼저 완료한 뒤 실제 Google Maps 반복 실행을 다시 수동 검증했다.

### 교정 후 staging 재검증 성공

2026-08-24 사용자가 development staging에서 다음을 직접 확인했다.

- staging 매장 24개 표시
- `PPS` 검색, 선택, 상세 화면 진입
- 첫 번째 `길찾기`에서 외부 Google Maps 목적지에 `PPS` 매장명과 전체 주소 표시
- 앱 복귀 후 두 번째와 세 번째 실행에서도 목적지가 매번 다시 적용
- 외부 앱 복귀 후 상세 화면 유지
- 지도 화면 복귀 후 검색어, 스타일 필터, 선택 카드 유지
- 주소 복사 기능 유지

### Supabase 공개 매장 검증 성공

2026-08-24 사용자가 development Supabase 모드에서 다음을 직접 확인했다.

- 현재 공개 매장인 노머시버거 마커 표시
- 노머시버거 상세 화면 진입과 `길찾기` 실행
- 외부 Google Maps 목적지에 노머시버거 매장명과 주소 표시
- 외부 앱 복귀 후 상세 화면 유지
- 지도 복귀 후 선택 카드 유지

수동 검증에는 사용자의 로컬 설정을 사용했으며 실제 API key, Supabase URL, Publishable key, 인증서 정보는 저장소에 기록하지 않았다. staging 24개는 개발 검증 데이터이며 공개 매장 수에 포함하지 않는다.

## 자동·수동 검증 범위

- 자동 검증: URL 구성과 인코딩, 좌표 fallback, primary/fallback 실행 분기, 성공·실패·예외 후 상태 초기화, 1·2·3회 반복 호출, 빠른 중복 탭 차단, loader 재호출 방지, 화면 overflow와 보안 회귀
- 사용자 수동 검증: 설치된 Google Maps에서 PPS 1·2·3회 목적지 재적용, 노머시버거 목적지 표시, 외부 앱 복귀 후 상세·지도 상태 보존
- 자동 검증만 수행: Google Maps 앱이 없는 환경의 HTTPS 브라우저 fallback

이번 기능은 위치 권한, 현재 위치 수집·저장, Directions API·Routes API, 새 Google API key 또는 추가 Supabase 요청을 사용하지 않는다.

## 수동 검증 절차

실제 값은 저장소나 명령 기록에 남기지 않고 사용자의 기존 로컬 주입 방식을 사용한다. 아래 값은 실행 형식만 보여 주는 placeholder다.

```cmd
cd /d C:\Users\jeong\burger-map
C:\Users\jeong\flutter\bin\flutter.bat run -d emulator-5554 --dart-define=APP_ENV=development --dart-define=STORE_DATA_MODE=staging --dart-define=GOOGLE_MAPS_API_KEY=로컬_값
```

Supabase 모드에서는 위 명령의 data mode를 `supabase`로 바꾸고 Project URL과 Publishable key를 기존 로컬 방식으로 추가 주입한다. Project URL에는 `/rest/v1`을 붙이지 않는다.

### Development staging

1. staging 매장 24개 표시
2. `PPS` 검색
3. PPS 결과 선택
4. 상세보기 진입
5. `길찾기` 선택
6. 외부 Google Maps 목적지에 `PPS`와 전체 주소가 표시되는지 확인
7. 앱으로 돌아와 두 번째와 세 번째 `길찾기`에서도 목적지가 매번 다시 적용되는지 확인
8. 앱 복귀 후 검색어·필터·선택 카드 유지 확인
9. 주소 복사 유지 확인

### Supabase

1. 노머시버거 마커 표시
2. 상세보기 진입
3. `길찾기` 선택
4. 외부 Google Maps 목적지에 노머시버거 이름과 전체 주소가 표시되는지 확인
5. 앱 복귀 후 두 번째 실행에서도 목적지가 다시 적용되는지 확인
6. 앱 복귀 후 상태 유지 확인

에뮬레이터의 현재 위치가 부정확한 것은 실패가 아니다. 목적지 매장명과 주소가 매번 전달되는지를 확인한다.

## 현재 상태와 미검증 항목

Phase 5D-A의 구현, 자동 검증, development staging 및 Supabase 사용자 수동 검증을 완료했다. 이는 길찾기 사용자 여정의 완료이며 앱 출시 준비 완료를 의미하지 않는다. Google Maps 앱이 없는 환경의 브라우저 fallback은 자동 테스트 범위이며, 실제 Android 기기와 iOS에서는 별도 확인이 필요하다.
