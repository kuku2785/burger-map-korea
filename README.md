# Burger Map Korea

버거맵 코리아 Phase 1은 전체 앱 구현이 아니라 Google Maps 기술 스파이크입니다.

## 목적

이 단계에서는 Flutter 앱이 Android/iOS 프로젝트 구조를 갖추고, 공식 `google_maps_flutter` 패키지로 자체 더미 매장 좌표를 지도 마커로 표시할 수 있는지만 검증합니다.

Google Places API, Supabase, 공공데이터 수집, 로그인, 검색, 필터, 현재 위치, 즐겨찾기, 리뷰, 광고, 결제, 관리자 기능은 구현하지 않습니다.

## 현재 Phase 1 범위

- 단일 지도 화면
- 서울 중심 카메라
- 서울 마포구/용산구/성동구의 가상 햄버거 매장 3개
- 마커 선택 시 테스트 데이터 상세 카드
- 빈 지도 선택 시 상세 카드 닫힘
- 카메라 이동 완료 이벤트 상태 표시
- debug 모드에서 카메라 중심과 zoom 표시
- 지도 로딩 상태
- API 키 미설정 안내 화면
- 기본 오류 안내 화면
- Android/iOS Google Maps API 키 주입 구조

## Flutter 요구 버전

현재 확인된 환경:

- Flutter 3.44.8
- Dart 3.12.2

Flutter가 PATH에 없다면 로컬 SDK 경로를 직접 사용합니다.

```powershell
C:\Users\jeong\flutter\bin\flutter.bat --version
```

## API 키 관리

실제 API 키와 비밀정보를 Git에 커밋하지 마세요.

`.env.example`은 예시 파일입니다. 현재 앱은 환경변수 패키지를 사용하지 않고 `--dart-define`을 우선 사용합니다.

```dotenv
APP_ENV=development
GOOGLE_MAPS_API_KEY=your-google-maps-api-key
```

API 키가 없으면 Google Maps 위젯을 생성하지 않고 안내 화면을 표시합니다.

## Google Cloud 설정

1. Google Cloud Console에서 프로젝트를 생성합니다.
2. Billing 계정을 연결합니다.
3. APIs & Services에서 다음 API를 활성화합니다.
   - Maps SDK for Android
   - Maps SDK for iOS
4. API key를 생성합니다.
5. Android 키는 Android application restriction을 설정합니다.
   - Package name: 현재 임시 application ID `com.burgermap.burger_map_korea`
   - SHA-1 certificate fingerprint: debug/release keystore에 맞게 등록
6. iOS 키는 iOS application restriction을 설정합니다.
   - Bundle ID: Xcode의 Runner target에서 확인 및 출시 전 확정

현재 application ID와 Bundle ID는 기술 검증용입니다. 출시 전 최종 ID를 확정해야 합니다.

Phase 1 Android debug 검증용 값:

- Package name: `com.burgermap.burger_map_korea`
- Debug SHA-1: `91:C0:F9:F3:3A:0B:27:5A:82:4D:86:0B:B8:CB:BC:80:48:47:67:E1`

Android용 API key는 Application restriction을 `Android apps`로 설정하고 위 package name과 debug SHA-1을 등록합니다. API restrictions는 `Maps SDK for Android`로 제한합니다.

## Android 실행방법

Android는 `--dart-define=GOOGLE_MAPS_API_KEY=...` 값을 Gradle에서 읽어 native Google Maps SDK에도 전달합니다. 따라서 로컬 개발 중에는 보통 한 번만 입력하면 됩니다.

```powershell
flutter pub get
flutter run --dart-define=APP_ENV=development --dart-define=GOOGLE_MAPS_API_KEY=your-google-maps-api-key
```

대안으로 Gradle property 또는 OS 환경변수 `GOOGLE_MAPS_API_KEY`를 사용할 수 있습니다. 이 경우 실제 키는 Git에 커밋하지 마세요.

로컬 전용 `android/gradle.properties` 예시:

```properties
GOOGLE_MAPS_API_KEY=your-google-maps-api-key
```

키 없이 실행하면 안내 화면만 확인할 수 있습니다.

```powershell
flutter run --dart-define=APP_ENV=development
```

### Android SDK 상태 참고

2026-08-10 기준 로컬 Android debug APK 빌드와 에뮬레이터 앱 실행은 성공했습니다.

복구된 항목:

- Android SDK command-line tools 설치
- 손상된 NDK `28.2.13676358` 재설치
- debug APK 생성 확인: `build\app\outputs\flutter-apk\app-debug.apk`
- `Medium_Phone_API_36.1` 에뮬레이터 실행 확인
- API 키 없이 앱 실행 후 Google Maps API 키 미설정 안내 화면 확인

남은 로컬 환경 이슈:

- Flutter/Dart binary가 PATH에 없음
- 일부 Android license가 아직 수락되지 않음
- Google Maps API 키가 없어 실제 지도 타일, 마커 선택, 지도 탭, 카메라 이동 이벤트는 아직 미검증

터미널에서 라이선스를 확인하려면 다음 명령을 실행합니다. 라이선스 동의는 사용자가 직접 확인해야 합니다.

```powershell
flutter doctor --android-licenses
flutter doctor -v
```

## iOS 실행방법

Windows에서는 iOS 빌드를 실행할 수 없습니다. macOS와 Xcode가 필요합니다.

macOS에서 확인할 항목:

1. `ios/Runner.xcworkspace`를 Xcode로 엽니다.
2. Runner target의 Bundle Identifier를 확인합니다.
3. Signing Team을 설정합니다.
4. 비공개 xcconfig 또는 Xcode build setting에 `GOOGLE_MAPS_API_KEY`를 추가합니다.
5. Simulator 또는 iPhone 실기기에서 실행합니다.

명령 예시:

```bash
flutter pub get
cd ios
pod install
cd ..
flutter run --dart-define=APP_ENV=development --dart-define=GOOGLE_MAPS_API_KEY=your-google-maps-api-key
```

## 테스트방법

```powershell
python -m unittest discover -s tests/data -p "test_*.py" -v
dart format .
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Phase 2.1A 후보 추출기

공공 상가정보 CSV에서 용산구 버거 매장 후보를 생성하는 로컬 도구는 `scripts/data/extract_burger_candidates.py`에 있습니다. 실제 CSV와 생성된 검수 CSV는 Git에서 제외되며, 후보는 자동 승인되거나 Flutter 앱에 표시되지 않습니다.

입력 파일 준비, 기준일 입력, 실행 명령과 검수 규칙은 `scripts/data/README.md`를 확인합니다.

## 알려진 제한사항

- API 키 없이 실제 Google Maps 렌더링은 확인할 수 없습니다.
- 현재 Windows 환경에서는 iOS 빌드를 검증하지 않습니다.
- Android debug build와 API 키 미설정 상태의 Android 앱 실행은 2026-08-10 기준 성공했습니다.
- 더미 매장은 모두 테스트용 가상 정보입니다.
- 실제 매장 데이터, 장소 API, Supabase 연결은 없습니다.

## Phase 1 완료 상태

코드 구현 완료, 실기기 검증 필요.

자동 검증 결과와 Android/iOS 검증 상태는 `docs/phase-1-implementation-report.md`에 기록합니다.
