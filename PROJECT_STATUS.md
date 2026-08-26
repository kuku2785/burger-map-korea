# Burger Map Korea Project Status

최종 갱신: 2026-08-26

이 문서는 구현 단계 번호와 실제 출시 준비 상태를 구분하는 단일 진행 현황이다. `완료`는 해당 범위의 구현·검증이 끝났다는 뜻이며 Google Play 또는 App Store 출시 완료를 의미하지 않는다.

## 완료

- Phase 2 데이터 후보 추출, 수동 검수, staging 통합 파이프라인
- Phase 3 Supabase 공개 읽기와 사람 승인 기반 안전 게시 흐름
- Phase 4 로컬 검색, 매장 상세, 버거 스타일 필터
- Phase 5B production/release Supabase 전용 runtime과 개발 데이터 fallback 차단
- Phase 5C-A Android application ID, 앱 이름, release signing 구성
- Phase 5D-A 외부 길찾기: 구현·자동 검증·수동 검증 완료
- Phase 6A: 용산구 공개 검수 매장 10곳 확보 및 앱 수동 검증 완료
- 로컬 upload key로 signed release AAB 생성 및 서명 자동 검증
- 새 Android package의 development staging 모드에서 Google 지도와 마커 24개 사용자 수동 확인
- 사용자 보고 기준 Supabase의 `verified + active` 공개 매장 10곳
- development + Supabase 모드에서 마커 10개와 필터·검색·상세·길찾기 사용자 수동 확인

## 진행 중

- Phase 6B-1: 잔여 pending 14곳·hold 4곳 재검수 완료
- 안정 ID 기준 후보 13곳 사용자 승인 및 로컬 게시 검수표 반영 완료
- 신규 13행 전용 INSERT SQL을 2026-08-26 원격 Supabase에 수동 적용 완료
- 원격 `verified + active` 공개 매장 10곳에서 23곳으로 증가 확인
- Phase 6B-2에서 스태커버거샵과 잭잭 2곳 사용자 승인 및 로컬 검수표 반영 완료
- 신규 2행 전용 INSERT SQL 생성 완료, 원격 Supabase에는 아직 적용하지 않음
- 원격 현재 공개 23곳, SQL 적용 후 예상 25곳이며 아직 25곳 달성으로 표시하지 않음
- 아메리칸치즈버거는 `pending + inactive`와 `needs_manual_check` 유지

## 미완료·미검증

- Play Console 개발자 계정 생성
- Play App Signing 활성화
- Play 배포 인증서 SHA-1의 Google Maps 제한 등록
- Google Play 내부·비공개 테스트 트랙
- 해당 개인 개발자 계정에 요구될 수 있는 12명·14일 비공개 테스트
- Android 실제 기기 3종 QA
- iOS Bundle ID, signing, 지도 키와 App Store 출시 게이트
- 공개 개인정보처리방침과 지원 페이지
- 공개 검수 매장 25곳 중간 목표
- 검수 완료 공개 매장 100곳
- 서울 검수 범위를 벗어난 전국 확대는 현재 금지
- 성능, 접근성, 느린 네트워크·오프라인, 장애 복구 종합 검증

## 출시 판단

현재 빌드·서명과 핵심 기능 기반은 준비 중이지만 스토어 출시 상태가 아니다. 자동 테스트, 에뮬레이터 수동 확인, 실제 기기 확인, Play 설치본 검증을 각각 별도로 기록한다.
