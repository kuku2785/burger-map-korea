# Phase 1 Manual Test Checklist

작성일: 2026-08-06

최근 갱신: 2026-08-10 Phase 1 최종 Android 사전 검증

완료 표시는 실제로 검증한 항목에만 적용한다.

| 항목 | 상태 | 메모 |
| --- | --- | --- |
| 앱 실행 | 완료 | 2026-08-10 `Medium_Phone_API_36.1`, Android 16/API 36 에뮬레이터에서 실행 확인 |
| API 키 미설정 안내 | 완료 | 2026-08-10 에뮬레이터 화면에서 안내 문구와 더미 매장 3개 목록 확인. 민감정보 노출 없음 |
| 지도 표시 | 미검증 | 로컬 `GOOGLE_MAPS_API_KEY` 미설정으로 실제 Google Maps 렌더링 미검증 |
| 서울 중심 카메라 | 미검증 | 실제 지도 렌더링 후 확인 필요 |
| 마커 3개 | 미검증 | 실제 지도 렌더링 후 확인 필요 |
| 마포구 마커 선택 | 미검증 | 실제 지도 렌더링 후 확인 필요 |
| 용산구 마커 선택 | 미검증 | 실제 지도 렌더링 후 확인 필요 |
| 성동구 마커 선택 | 미검증 | 실제 지도 렌더링 후 확인 필요 |
| 상세 카드 | 미검증 | 2026-08-06 위젯 테스트로 카드 내용만 확인. 지도 마커 탭은 미검증 |
| 빈 지도 선택 시 카드 닫힘 | 미검증 | Google Maps 플랫폼 뷰 실기기 확인 필요 |
| 카메라 이동 이벤트 | 미검증 | Google Maps 플랫폼 뷰 실기기 확인 필요 |
| Android debug APK 빌드 | 완료 | 2026-08-10 `flutter build apk --debug` 성공. `build\app\outputs\flutter-apk\app-debug.apk` 생성 |
| Android 에뮬레이터 | 완료 | 2026-08-10 `Medium_Phone_API_36.1`, Android 16/API 36 실행 및 `emulator-5554` Flutter device 감지 확인 |
| Package / debug SHA-1 | 완료 | Package `com.burgermap.burger_map_korea`, debug SHA-1 확인 |
| API key Git 미포함 | 완료 | `.env` 없음, `.gitignore`에서 `.env` 제외, Git 추적 파일 내 실제 Google API key 패턴 미발견 |
| Android 실기기 | 미검증 | Android toolchain 정리 및 기기 연결 필요 |
| iOS Simulator | 미검증 | macOS 필요 |
| iPhone 실기기 | 미검증 | macOS, Xcode, Apple Developer 설정 필요 |
