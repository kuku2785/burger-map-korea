# Phase 1 Implementation Report

작성일: 2026-08-06

## 1. Phase 1 목표

Google Maps 공식 Flutter 패키지를 사용해 Android/iOS 앱 기반에서 서울 더미 매장 좌표를 지도 마커로 표시할 수 있는지 검증한다.

## 2. 구현 기능

- Flutter Android/iOS 프로젝트 구조 확인
- 공식 `google_maps_flutter` 연결
- 단일 지도 화면
- API 키 미설정 안내 화면
- 지도 로딩 오버레이
- 기본 오류 안내 위젯
- 서울 중심 초기 카메라
- 서울 마포구/용산구/성동구 가상 매장 3개
- 마커 선택 시 임시 상세 카드 표시
- 빈 지도 탭 시 선택 해제
- 카메라 이동 완료 이벤트 상태 표시
- debug 모드 카메라 중심/zoom 표시
- StoreLocation 좌표 검증

## 3. 제외 기능

Supabase, SQL migration, 공공데이터 다운로드, 실제 매장 데이터, Google Places API, Kakao Local API, NAVER 지역 API, Geocoding, 로그인, 회원가입, 검색, 필터, 현재 위치, 마커 클러스터링, 즐겨찾기, 방문 기록, 리뷰, 사진 업로드, 사용자 제보, 관리자 기능, 외부 지도 길찾기, AdMob, 결제, 분석 SDK, 푸시, CI/CD, 앱스토어 배포는 구현하지 않았다.

## 4. 생성 및 수정 파일

생성:

- `lib/features/map/presentation/store_preview_card.dart`
- `docs/phase-1-implementation-report.md`
- `docs/phase-1-manual-test-checklist.md`
- `test/features/map/map_screen_widget_test.dart`

수정:

- `README.md`
- `.env.example`
- `docs/phase-0-technical-plan.md`
- `pubspec.yaml`
- `pubspec.lock`
- `lib/main.dart`
- `lib/app/app.dart`
- `lib/app/app_theme.dart`
- `lib/core/config/app_config.dart`
- `lib/features/map/presentation/map_screen.dart`
- `lib/features/stores/domain/store_location.dart`
- `lib/features/stores/data/dummy_store_locations.dart`
- `test/core/config/app_config_test.dart`
- `test/features/map/map_marker_mapping_test.dart`
- `test/features/stores/dummy_store_locations_test.dart`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `ios/Runner/AppDelegate.swift`
- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`

## 5. 설치 패키지와 버전

- `google_maps_flutter`: 2.18.0
- `cupertino_icons`: 1.0.9
- `flutter_lints`: 6.0.0

## 6. 패키지 선택 이유

`google_maps_flutter`는 Google Maps 공식 Flutter 패키지라 Phase 1 기술 스파이크의 핵심 검증 대상이다. `cupertino_icons`와 `flutter_lints`는 Flutter 기본 프로젝트 수준의 최소 의존성이다.

## 7. API 키 설정 구조

- Flutter UI: `--dart-define=GOOGLE_MAPS_API_KEY=...`
- Android native SDK: Gradle property 또는 OS 환경변수 `GOOGLE_MAPS_API_KEY`
- iOS native SDK: Xcode build setting 또는 비공개 xcconfig `GOOGLE_MAPS_API_KEY`

실제 API 키는 저장소에 작성하지 않는다. API 키가 없으면 Google Maps 위젯을 생성하지 않고 안내 화면을 표시한다.

## 8. 실행한 명령과 결과

최종 검증일: 2026-08-10

- `flutter --version`: 성공. Flutter 3.44.8, Dart 3.12.2
- `flutter doctor -v`: 성공적으로 실행. Flutter/Dart PATH 경고와 Android license 경고가 남아 있음
- `flutter devices`: 성공. Windows/Chrome/Edge만 감지, Android 에뮬레이터 또는 실기기는 미연결
- `dart format .`: 성공. 12개 파일 확인, 변경 없음
- `flutter clean`: 성공
- `flutter pub get`: 성공
- `flutter analyze`: 성공. 이슈 없음
- `flutter test`: 성공. 15개 테스트 통과
- `flutter build apk --debug`: 성공. `build\app\outputs\flutter-apk\app-debug.apk` 생성
- `flutter emulators`: 성공. `Medium_Phone_API_36.1`, `Pixel_3a` 감지
- `flutter emulators --launch Medium_Phone_API_36.1`: 성공
- `flutter devices`: 성공. `emulator-5554` Android 실행 대상 감지
- `flutter run -d emulator-5554 --dart-define=APP_ENV=development --no-resident`: 성공. API 키 미설정 안내 화면 확인
- `gradlew :app:signingReport --console=plain --info`: 성공. debug SHA-1 확인
- `flutter doctor --android-licenses`: 사용자 입력 대기 상태로 타임아웃. 임의 동의하지 않음

## 9. Android 검증 상태

Android debug APK 빌드는 성공했다. 이전 실패 원인이었던 손상된 NDK 설치는 복구했다.

복구한 항목:

- Android command-line tools 설치
- 손상된 NDK `28.2.13676358` 제거 후 공식 r28c 패키지 설치
- NDK `source.properties` 확인: `Pkg.Revision = 28.2.13676358`
- 빌드 중 필요한 Android SDK Platform 36 자동 설치 확인
- 빌드 중 필요한 CMake 3.22.1 자동 설치 확인

생성된 APK:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

APK 크기:

```text
148,721,736 bytes
```

남은 Android 환경 이슈:

- `flutter doctor -v` 기준 Flutter/Dart binary가 PATH에 없음
- `flutter doctor -v` 기준 일부 Android license가 아직 수락되지 않음
- Google Maps API 키가 제공되지 않아 실제 지도 타일 렌더링은 미검증
- Google Maps API 키가 제공되지 않아 마커 탭, 지도 탭, 카메라 이동 완료 이벤트는 실제 플랫폼 뷰에서 미검증

Android package와 debug 서명:

```text
Package: com.burgermap.burger_map_korea
Debug SHA-1: 91:C0:F9:F3:3A:0B:27:5A:82:4D:86:0B:B8:CB:BC:80:48:47:67:E1
```

Google Maps API key 상태:

- OS 환경변수 `GOOGLE_MAPS_API_KEY`: 미설정
- `.env`: 없음
- `android/gradle.properties`: 실제 API key 없음
- Git 추적 파일 내 실제 Google API key 패턴: 발견되지 않음
- AndroidManifest는 `${GOOGLE_MAPS_API_KEY}` placeholder를 사용
- Gradle은 `GOOGLE_MAPS_API_KEY`를 Gradle property, OS 환경변수, 또는 Dart define에서 읽어 native SDK에 전달
- Dart AppConfig는 `--dart-define=GOOGLE_MAPS_API_KEY=...` 존재 여부로 지도 화면과 미설정 안내 화면을 분기

## 10. iOS 검증 상태

Windows 환경이므로 iOS 빌드는 실행하지 않았다. `Info.plist`, `AppDelegate.swift`, Debug/Release xcconfig에 API 키 주입 구조만 준비했다. 실제 검증은 macOS와 Xcode에서 수행해야 한다.

## 11. 테스트 결과

단위 테스트:

- 정상 좌표 StoreLocation 생성
- 잘못된 위도 거부
- 잘못된 경도 거부
- 더미 데이터 3개 확인
- 더미 데이터 ID 중복 없음
- 더미 데이터 좌표 유효성 확인

위젯 테스트:

- 선택 전 상세 카드 미표시
- 선택 카드에 이름/주소/버거 스타일 표시
- API 키 미설정 안내 표시
- 오류 안내 표시

## 12. 발견된 문제

- `AGENTS.md`가 저장소에 없음
- Flutter binary와 Dart binary가 PATH에 없음
- Android license 일부가 아직 수락되지 않음
- API 키가 없어 실제 지도 렌더링은 미검증
- Android 에뮬레이터 앱 실행은 확인했지만 Google Maps API 키가 없어 실제 지도 화면은 미검증
- Windows 환경이므로 iOS 빌드와 iOS 지도 렌더링은 미검증

## 13. 남은 위험

- Google Maps 실제 렌더링은 API 키와 Android/iOS 네이티브 설정 후 확인 필요
- Android application restriction용 SHA-1 지문 등록 필요
- iOS Bundle ID와 API key restriction 확정 필요
- Google Maps 한국 지도 품질은 실사용 기기에서 확인 필요

## 14. Phase 2 전 권장 작업

- `flutter doctor --android-licenses`를 사용자가 직접 실행하고 필요한 라이선스 동의
- Google Maps API 키를 Android/iOS 제한 설정과 함께 발급
- Android 에뮬레이터 또는 실기기에서 지도 표시, 마커 3개, 상세 카드, 카메라 이동 이벤트 수동 검증
- macOS에서 iOS Simulator/실기기 빌드와 지도 렌더링 검증
- 이후 승인 후 서울 검수 매장 100개용 로컬 데이터 구조 설계

## 15. Phase 1.1 Android 환경 진단 및 복구 시도

진단 명령:

- `flutter --version`: 성공. Flutter 3.44.8, Dart 3.12.2
- `flutter doctor -v`: 성공적으로 실행. Android toolchain 경고 있음
- `flutter devices`: 성공. Windows, Chrome, Edge만 감지
- `flutter config --list`: 성공. 주요 기능 플래그는 기본값
- `flutter emulators`: 성공. `Medium_Phone_API_36.1`, `Pixel_3a` 감지

Android SDK 상태:

- SDK 경로: `C:\Users\jeong\AppData\Local\Android\sdk`
- `local.properties`의 `sdk.dir`: `C:\Users\jeong\AppData\Local\Android\sdk`
- Android Platform: `android-36.1`
- Build-Tools: `36.0.0`, `36.1.0`
- cmdline-tools: 미설치
- sdkmanager: 없음
- license 확인: `Android sdkmanager not found`

NDK 상태:

- 설치 목록: `28.2.13676358`
- `source.properties`: 없음
- 폴더 내용: `.installer`만 확인
- 결론: 해당 NDK 폴더는 불완전 설치 또는 손상 상태
- 프로젝트는 `android/app/build.gradle.kts`에서 `ndkVersion = flutter.ndkVersion`을 사용하므로 특정 버전을 임의 고정하지 않았다.

자동 복구 결과:

- Android 공식 Command line tools Windows 패키지를 다운로드하고 SHA-256을 검증한 뒤 설치했다.
- `sdkmanager.bat` 실행을 확인했다.
- 손상된 NDK 폴더를 삭제했다.
- `sdkmanager --install "ndk;28.2.13676358"`는 저장소 목록 다운로드 실패로 완료하지 못했다.
- Android 공식 NDK r28c Windows 패키지를 직접 다운로드하고 SHA-1을 검증했다.
- 검증된 NDK를 `C:\Users\jeong\AppData\Local\Android\sdk\ndk\28.2.13676358`에 설치했다.

API 키 구조 검토:

- Dart UI: `--dart-define=GOOGLE_MAPS_API_KEY=...`
- Android native SDK: Gradle property, OS 환경변수, 또는 Dart define에서 manifest placeholder로 전달
- AndroidManifest: `${GOOGLE_MAPS_API_KEY}` placeholder 사용
- iOS: `Info.plist`의 `$(GOOGLE_MAPS_API_KEY)`를 `AppDelegate.swift`에서 읽어 `GMSServices.provideAPIKey` 호출
- `.gitignore`: `.env` 제외
- `.env.example`: placeholder만 포함
- `android/gradle.properties`, `android/local.properties`, `.env.example`에서 Google API 키 패턴은 발견되지 않음

Phase 1.1 최종 검증 명령:

- `dart format .`: 성공
- `flutter clean`: 성공
- `flutter pub get`: 성공
- `flutter analyze`: 성공, 이슈 없음
- `flutter test`: 성공, 15개 테스트 통과
- `flutter build apk --debug`: 성공

Phase 1 최종 자동 검증:

- 검증일: 2026-08-10
- `dart format .`: 성공. 12개 파일 확인, 변경 없음
- `flutter analyze`: 성공. 이슈 없음
- `flutter test`: 성공. 15개 테스트 통과
- `flutter build apk --debug`: 성공. `build\app\outputs\flutter-apk\app-debug.apk` 생성

이전 APK build 실패 원인:

```text
[CXX1101] NDK at C:\Users\jeong\AppData\Local\Android\sdk\ndk\28.2.13676358 did not have a source.properties file
```

구분:

- 코드 문제: 현재 확인되지 않음. format/analyze/test/debug APK build 통과
- 환경 문제: NDK 손상은 복구됨. Android license 일부 미수락은 남아 있음

에뮬레이터/실기기 검증:

- `Medium_Phone_API_36.1` 에뮬레이터 실행과 Flutter device 감지를 확인했다.
- API 키 없이 앱을 실행해 Google Maps API 키 미설정 안내 화면과 더미 매장 3개 목록 표시를 확인했다.
- Android 실기기는 연결되지 않았다.
- Google Maps API 키가 제공되지 않아 실제 렌더링은 검증하지 못했다.

남은 수동 절차:

1. `flutter doctor --android-licenses` 실행 및 사용자 직접 동의
2. Google Cloud 프로젝트와 Billing 확인
3. `Maps SDK for Android` 활성화
4. Android용 API key 생성
5. Application restriction을 `Android apps`로 설정
6. package `com.burgermap.burger_map_korea` 등록
7. debug SHA-1 `91:C0:F9:F3:3A:0B:27:5A:82:4D:86:0B:B8:CB:BC:80:48:47:67:E1` 등록
8. API restrictions를 `Maps SDK for Android`로 제한
9. `flutter run --dart-define=APP_ENV=development --dart-define=GOOGLE_MAPS_API_KEY=...`
10. 지도 표시, 마커 선택, 상세 카드, 카메라 이동 이벤트 확인
