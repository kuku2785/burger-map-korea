# Burger Map Korea Project Status

최종 갱신: 2026-08-24

이 문서는 구현 단계 번호와 실제 출시 준비 상태를 구분하는 단일 진행 현황이다. `완료`는 해당 범위의 구현·검증이 끝났다는 뜻이며 Google Play 또는 App Store 출시 완료를 의미하지 않는다.

## 완료

- Phase 2 데이터 후보 추출, 수동 검수, staging 통합 파이프라인
- Phase 3 Supabase 공개 읽기와 사람 승인 기반 안전 게시 흐름
- Phase 4 로컬 검색, 매장 상세, 버거 스타일 필터
- Phase 5B production/release Supabase 전용 runtime과 개발 데이터 fallback 차단
- Phase 5C-A Android application ID, 앱 이름, release signing 구성
- Phase 5D-A 외부 길찾기: 구현·자동 검증·수동 검증 완료
- 로컬 upload key로 signed release AAB 생성 및 서명 자동 검증
- 새 Android package의 development staging 모드에서 Google 지도와 마커 24개 사용자 수동 확인
- 사용자 보고 기준 Supabase의 `verified + active` 공개 매장 1곳

## 진행 중

- 실제 검수·공개 매장 확대

## 미완료·미검증

- Play Console 개발자 계정 생성
- Play App Signing 활성화
- Play 배포 인증서 SHA-1의 Google Maps 제한 등록
- Google Play 내부·비공개 테스트 트랙
- 해당 개인 개발자 계정에 요구될 수 있는 12명·14일 비공개 테스트
- Android 실제 기기 3종 QA
- iOS Bundle ID, signing, 지도 키와 App Store 출시 게이트
- 공개 개인정보처리방침과 지원 페이지
- 검수 완료 공개 매장 100곳
- 성능, 접근성, 느린 네트워크·오프라인, 장애 복구 종합 검증

## 출시 판단

현재 빌드·서명과 핵심 기능 기반은 준비 중이지만 스토어 출시 상태가 아니다. 자동 테스트, 에뮬레이터 수동 확인, 실제 기기 확인, Play 설치본 검증을 각각 별도로 기록한다.
