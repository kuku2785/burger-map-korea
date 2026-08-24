# Burger Map Korea Phase 5A Production 출시 준비 감사

- 확인일: 2026-08-20 (KST)
- 기준 커밋: `21a3699d582878a04462c1d771ff8d7fcb9754a5`
- 감사 범위: 코드, Android 설정, 데이터 게시 절차, 보안, 개인정보, Google Play 준비 상태
- 작업 범위: 조사와 문서화만 수행. 코드, Android 설정, 원격 서비스, 데이터는 변경하지 않음

> Phase 5B 후속 상태(2026-08-21): production/release의 Supabase 강제 선택, pilot/staging fallback 차단, Supabase 설정 검증, production 기술 UI 차단, release staging asset 제거가 구현·수동 검증됐다. 이 문서의 현재 상태는 `docs/phase-5b-production-runtime.md`와 함께 본다.

상태는 `ready`, `blocked`, `needs_user_action`, `deferred`로 표시한다. 우선순위는 출시 차단 또는 보안 필수인 `P0`, 비공개 테스트 전 필수인 `P1`, 공개 출시 전 권장인 `P2`, 출시 후 개선 가능한 `P3` 순이다.

## 1. 현재 출시 준비 상태 요약

| 영역 | 상태 | 우선순위 | 감사 결과 |
| --- | --- | --- | --- |
| 지도 중심 MVP 기능 | ready | P1 | 지도, 로컬 검색, 스타일 필터, 상세 화면, 주소 복사, 빈 상태, 오류, 재시도가 구현됨 |
| production 데이터 모드 | ready | P0 | Phase 5B에서 production/release를 Supabase로 고정하고 로컬 fallback을 차단함 |
| Supabase 읽기 보안 | ready | P0 | Publishable key와 RLS를 사용하며 `verified + active`만 SELECT함 |
| Android release 서명 | ready | P0 | 로컬 upload key로 signed AAB 생성·검증, debug fallback 없음 |
| 최종 application ID | ready | P0 | `com.burgermapkorea.app`으로 확정하고 Android production source에 적용함 |
| Google Maps release key | needs_user_action | P0 | 최종 package name과 Play App Signing SHA-1에 제한된 release key가 필요함 |
| 공개 매장 데이터 | blocked | P1 | 사용자 보고 기준 원격 공개 매장이 1곳뿐이라 지도 탐색 MVP로서 효용이 부족함 |
| 앱 이름·아이콘·스플래시 | partial | P1 | 정식 Android label 적용 완료. Flutter 기본 아이콘과 무브랜드 시작 화면은 남아 있음 |
| Play 정책·스토어 자료 | needs_user_action | P1 | 개인정보처리방침, Data safety, 콘텐츠 등급, 스크린샷 등 입력이 필요함 |
| Android API 수준 | ready | P0 | 현재 환경에서 compile/target SDK 36, min SDK 24로 해석됨 |
| 자동 테스트·빌드 안전장치 | ready | P1 | Python 112개, Flutter 87개, analyze·debug APK·signed release AAB 검증 성공 |
| 실제 기기·Play 설치 검증 | blocked | P1 | 에뮬레이터 검증만 기록되어 있고 실제 Android 기기와 Play 배포 AAB 검증이 없음 |
| release asset 분리 | ready | P0 | debug 전용 generated source set으로 분리하고 release AAB entry·manifest·식별 값 0건 확인 |

Phase 5B 이후 release는 production Supabase만 선택하며 설정 누락 시 로컬 매장을 표시하지 않는다. 다만 release는 여전히 debug 인증서로 서명되므로 생성된 release AAB는 진단 산출물일 뿐 Play 업로드용 산출물이 아니다.

## 2. 지도 중심 MVP 범위

첫 Google Play 공개 범위는 다음으로 고정한다.

| 기능 | 상태 | 우선순위 | 범위 |
| --- | --- | --- | --- |
| Google 지도와 공개 매장 마커 | ready | P0 | Supabase의 `verified + active` 매장만 표시 |
| 매장명·주소 검색 | ready | P1 | 이미 로딩한 목록의 로컬 검색이며 검색 중 추가 API 호출 없음 |
| 버거 스타일 필터 | ready | P1 | 검색과 AND 조건으로 동작 |
| 매장 기본 상세 | ready | P1 | 이름, 주소, 버거 스타일, 검수 상태만 표시 |
| 주소 복사 | ready | P2 | Clipboard 쓰기만 사용 |
| 로딩·빈 상태·오류·재시도 | ready | P1 | Supabase 0행은 정상 빈 상태로 처리 |
| 계정·로그인 | deferred | P3 | 첫 출시 제외 |
| 리뷰·평점·메뉴·사진 | deferred | P3 | 데이터 스키마, 검수, 신고 정책 준비 후 별도 단계 |
| 즐겨찾기·알림·광고·결제 | deferred | P3 | 첫 출시 제외 |
| 관리자 기능 | deferred | P3 | 공개 Flutter 클라이언트가 아닌 안전한 운영 도구로 설계 필요 |

## 3. 출시 차단 요소

### P0

1. **Production Supabase 실행 경로** (`ready`)
   - Phase 5B에서 release 여부를 입력받는 순수 resolver를 추가했다.
   - production/release는 요청된 data mode와 무관하게 Supabase를 사용한다.
   - 설정 누락이나 오류가 있어도 pilot/staging으로 fallback하지 않는다.

2. **Release upload keystore 준비** (`ready`)
   - Phase 5C-A에서 release의 debug signing fallback을 제거했다.
   - 사용자가 upload key와 key.properties를 로컬에서 생성했고 signed AAB를 검증했다.
   - 로컬 signing 파일은 Git에서 제외한다. Play App Signing 활성화와 별도 안전 백업은 사용자 운영 작업으로 남는다.

3. **최종 application ID 확정** (`ready`)
   - 사용자가 `com.burgermapkorea.app`을 최종 승인했고 Phase 5C-A에서 application ID, namespace, MainActivity package에 적용했다.
   - Play에 처음 업로드한 뒤에는 application ID 변경을 새 앱으로 취급하므로 이 값을 장기적으로 유지한다.

4. **Google Maps production key 미준비** (`needs_user_action`)
   - release 빌드용 별도 키를 최종 application ID와 Play App Signing 인증서 SHA-1로 제한해야 한다.
   - API 제한은 Maps SDK for Android만 허용한다. Billing 활성화와 quota/예산 알림도 확인한다.
   - 키는 앱에서 완전히 숨길 수 없으므로 애플리케이션·API 제한이 핵심 통제다.

### P1

1. **공개 매장이 1곳뿐임** (`blocked`)
   - 기술적으로는 표시되지만 지도 탐색 서비스의 초기 효용이 매우 낮다.
   - 비공개 사용성 테스트에는 용산구의 검수 완료 매장 10~15곳, 공개 MVP에는 20~30곳을 권장한다. 이는 자동 승인 기준이 아니라 운영 권장치다.

2. **출시 브랜드 자료 미완성** (`blocked`)
   - Android label은 `버거맵 코리아`로 적용했지만 launcher icon은 Flutter 기본 아이콘이다.
   - adaptive icon, 브랜드 스플래시, Play 아이콘, feature graphic, 스크린샷이 필요하다.

3. **실제 기기 및 Play 설치 검증 없음** (`blocked`)
   - 최소 1대 이상의 실제 Android 기기와 Play internal/closed track 설치본에서 지도, Supabase, 검색, 필터, 상세 화면을 확인해야 한다.

4. **정책 입력과 공개 문서 미완성** (`needs_user_action`)
   - 공개 개인정보처리방침 URL, 지원 이메일, Data safety, 콘텐츠 등급, 대상 연령, 광고 여부, 앱 액세스 선언이 필요하다.

5. **Production 기술 UI와 원시 오류 차단** (`ready`)
   - Development 배지와 카메라 center/zoom 진단은 development에서만 표시된다.
   - production 설정·지도 오류는 일반 문구만 표시하며 URL, key, 원시 오류를 노출하지 않는다.
   - 2026-08-21 production runtime과 설정 누락 수동 검증에서 차단 동작을 확인했다.

## 4. 기술 설정 감사

### 실행 모드와 환경 분리

| 항목 | 상태 | 우선순위 | 결과 |
| --- | --- | --- | --- |
| pilot 모드 | ready | P3 | 로컬 파일럿 3곳 사용 |
| staging 모드 | ready | P2 | development + non-release에서만 24곳 로컬 asset 사용 |
| supabase 모드 | ready | P1 | development + non-release에서만 동작 |
| production + supabase | ready | P0 | production/release에서 Supabase로 고정 |
| 설정 누락 처리 | ready | P0 | 초기화 전 검증하고 로컬 fallback 없이 일반 설정 오류 표시 |
| 비밀정보 주입 | ready | P0 | dart-define/Gradle property/환경변수 구조이며 저장소 하드코딩 없음 |

production debug는 `APP_ENV=production`을 기준으로 Supabase를 강제한다. release는 요청된 `APP_ENV`와 `STORE_DATA_MODE`를 무시하고 production/Supabase로 고정한다. Supabase URL 또는 Publishable key가 누락되거나 잘못되면 시작 단계에서 일반 설정 오류를 표시하며 pilot/staging으로 복귀하지 않는다.

### Supabase

| 항목 | 상태 | 우선순위 | 결과 |
| --- | --- | --- | --- |
| 공개 클라이언트 key | ready | P0 | Publishable key만 입력받음 |
| Secret/service-role 경로 | ready | P0 | Flutter 코드에 없음 |
| 읽기 조건 | ready | P0 | 클라이언트 쿼리와 RLS 모두 `verified + active` |
| 쓰기 경로 | ready | P0 | Flutter INSERT/UPDATE/DELETE/UPSERT/RPC 없음 |
| 빈 결과 | ready | P1 | 정상 empty state 표시 |
| 오류·재시도 | ready | P1 | 일반 오류 문구와 재시도 제공 |
| production 자격정보 전달 | needs_user_action | P0 | CI/로컬 비밀 저장소에서 Project URL과 Publishable key 주입 필요 |
| 비활성화/rollback | ready | P1 | 관리자 SQL로 `is_active=false` 처리해 공개에서 숨기는 원칙 문서화됨 |

`SUPABASE_URL`에는 `/rest/v1`이 없는 Project URL을 사용해야 한다. `/rest/v1`을 포함하면 SDK가 REST 경로를 중복 생성해 `PGRST125` 오류가 발생한 이력이 있다.

### Google Maps

| 항목 | 상태 | 우선순위 | 결과 |
| --- | --- | --- | --- |
| 공식 Flutter 패키지 | ready | P1 | `google_maps_flutter` 사용 |
| Android manifest metadata | ready | P0 | 빌드 시 주입 구조 존재 |
| release key 제한 | partial | P0 | 새 package + debug 인증서 제한 완료. upload/Play App Signing SHA-1은 사용 시 추가 필요 |
| API 제한 | ready | P0 | 사용자가 Maps SDK for Android로 제한 완료 |
| 불필요한 위치 권한 | ready | P0 | 위치 권한 선언 없음, My Location 비활성화 |
| 키 미설정 처리 | ready | P1 | 안내 화면 존재. production 문구는 비기술적 표현으로 조정 권장 |
| 실제 release key 지도 렌더링 | blocked | P1 | Play 설치본으로 확인되지 않음 |

현재 앱은 Places, Routes, Kakao, NAVER 장소 API를 호출하지 않는다. Maps SDK for Android는 Billing 연결이 필요하며 현재 공식 문서상 모바일 SDK 지도 표시는 unlimited SKU이나, quota와 예산 알림은 별도로 설정하는 편이 안전하다.

### Android

| 항목 | 상태 | 우선순위 | 결과 |
| --- | --- | --- | --- |
| application ID/namespace | ready | P0 | 모두 `com.burgermapkorea.app`으로 확정·적용 |
| 앱 표시 이름 | ready | P1 | Android label을 `버거맵 코리아`로 적용 |
| 버전 | ready | P1 | `1.0.0+1`; 매 업로드마다 versionCode 증가 필요 |
| SDK 수준 | ready | P0 | min 24, target/compile 36 |
| release 서명 | ready | P0 | 로컬 upload key로 signed AAB 생성·검증, debug fallback 없음 |
| keystore 비밀정보 제외 | ready | P0 | keystore와 key properties가 ignore되고 추적 파일 없음 |
| Android 12 exported | ready | P0 | launcher Activity에 `exported=true` |
| 권한 | ready | P0 | INTERNET/네트워크 상태 외 고위험 앱 권한 없음 |
| cleartext | ready | P1 | 별도 허용 없음; target 36에서는 기본 차단 |
| backup | needs_user_action | P2 | `allowBackup` 미지정으로 플랫폼 기본값 사용. 앱 데이터 범위에 맞춰 명시 결정 권장 |
| shrink/minify | ready | P2 | release 빌드에서 R8 mapping 산출물 확인 |
| Dart obfuscation | deferred | P3 | 현재 비활성. 보안 경계가 아니며 필요 시 별도 판단 |
| 아이콘/splash | blocked | P1 | Flutter 기본 아이콘, 무브랜드 시작 화면 |

## 5. 데이터 준비 상태

| 데이터 집합 | 수량 | 상태 | 게시 여부 |
| --- | ---: | --- | --- |
| 로컬 staging | 24 | pending 기반 개발 데이터 | 미게시 |
| 스타일 사용자 승인 | 20 | 스타일만 승인 | 게시 승인과 무관 |
| 스타일 미분류 | 4 | `unclassified + needs_recheck` | 미게시 |
| 게시 검수표 | 24 | verified 1, pending 23 | 1곳만 SQL 생성·적용됨 |
| hold report | 4 | 재확인 필요 | 미게시 |
| 원격 Supabase 공개 데이터 | 1 | 사용자 보고 기준 `verified + active` | 노머시버거만 공개 |

스타일 승인은 게시 승인이 아니다. 공개 전에는 매장별로 현재 영업 여부, 버거 전문성, 최신 이름·주소·좌표, 대표 스타일, 출처 기준일을 사람이 다시 확인하고 게시 결정을 별도로 내려야 한다. pending과 hold를 자동으로 verified로 바꾸면 안 된다.

권장 운영 기준:

- 비공개 사용성 테스트: 한 지역에서 검수 완료 10~15곳
- 공개 지도 MVP: 검수 완료 20~30곳
- 게시 직전 전체 재검수, 이후 90일마다 정기 재확인
- 폐업·이전·오류 신고는 1~3영업일 내 확인하고 필요 시 즉시 `is_active=false`

위 수량과 주기는 법적 의무가 아니라 작은 운영팀을 위한 보수적 권장안이다.

## 6. 보안 상태

| 항목 | 상태 | 우선순위 | 결과 |
| --- | --- | --- | --- |
| API key/URL/JWT 하드코딩 | ready | P0 | 추적 파일 패턴 검사에서 실제 값 없음 |
| `.env` 추적 | ready | P0 | Git 제외, 추적되지 않음 |
| 실제 CSV/생성 SQL/staging JSON | ready | P0 | Git 제외, 추적되지 않음 |
| APK/AAB/build | ready | P0 | Git 제외, 추적되지 않음 |
| Supabase RLS | ready | P0 | 활성화, 공개 읽기 정책 1개, 공개 쓰기 정책 없음 |
| Maps key 제한 | partial | P0 | debug package/인증서와 API 제한 완료. upload/Play App Signing 인증서 제한은 후속 등록 필요 |
| release signing key | ready | P0 | 로컬 upload key와 key.properties 준비, Git 제외, signed AAB 검증 완료 |
| 사용자 오류 메시지 | ready | P1 | production에서 일반 오류만 표시하고 기술 세부사항 차단 |

Google Maps Android 키는 앱 바이너리에서 추출 가능하므로 저장소 비공개화나 난독화만으로 보호되지 않는다. application restriction과 API restriction, 키 분리, quota/예산 알림을 함께 적용한다. Supabase Publishable key는 공개 클라이언트용이지만 RLS가 실제 권한 경계이며, secret/service-role key는 Flutter에 절대 넣지 않는다.

## 7. 개인정보·법적 확인 사항

### 코드 기준 데이터 처리

| 항목 | 상태 | 우선순위 | 결과 |
| --- | --- | --- | --- |
| 위치 권한·현재 위치 | ready | P0 | 사용하지 않음 |
| 계정·사용자 식별정보 | ready | P0 | 수집하지 않음 |
| 리뷰·평점·사진 | ready | P0 | 수집하지 않음 |
| 광고·분석·Crash SDK | ready | P1 | 현재 없음 |
| Clipboard | ready | P2 | 사용자가 누른 매장 주소를 쓰기만 하며 읽지 않음 |
| 네트워크 | needs_user_action | P1 | Google Maps와 Supabase 통신을 Data safety/개인정보처리방침에 반영해야 함 |

Maps SDK 공식 고지에 따르면 SDK는 기기·요청 메타데이터, SDK/앱 빌드 정보, crash stack trace와 metrics, IP 주소, Maps SDK별 pseudonymous identifier를 자동 수집할 수 있고 지도 pan/zoom 같은 상호작용 이벤트도 다룰 수 있다. 따라서 “아무 데이터도 수집하지 않는다”라고 단정하면 안 되며, 실제 SDK 사용과 Google Play Data safety 정의에 따라 사용자가 선언을 완성해야 한다.

Supabase 요청도 서비스 제공 과정에서 IP와 요청 메타데이터가 서버 로그에 남을 수 있으므로 정확한 보관 기간과 처리 주체는 사용 중인 Supabase 플랜·계약·설정을 확인한 뒤 고지한다. 이는 법률 자문이 아니며 공개 전 정책 검토가 필요하다.

개인정보처리방침 최소 항목:

- 앱·개발자 명칭과 공개 연락처
- 앱이 직접 계정, 위치 권한, UGC, 광고 데이터를 수집하지 않는 현재 범위
- Google Maps와 Supabase 사용 목적 및 전송될 수 있는 데이터 범주
- 주소 복사는 사용자의 기기 Clipboard에 사용자가 선택한 주소를 쓰는 기능이라는 설명
- 데이터 보관·삭제·정정 요청 절차와 연락처
- 공공데이터 출처와 실제 이용조건에 따른 표시·재배포 범위
- 정책 변경일과 시행일

정책은 공개 접근 가능한 활성 URL에 HTML로 제공하는 것이 안전하며 PDF만 두는 방식은 피한다. 앱 내 또는 스토어 설명에서 매장 정보 정정·폐업 신고 연락처도 제공한다. 사용한 공공데이터의 정확한 라이선스와 출처 표시 문구는 원본 데이터셋 이용조건을 다시 확인해야 한다. 오픈소스 의존성 고지 화면 또는 공개 notices 파일도 P2로 준비한다.

## 8. Google Play 준비 상태

| 항목 | 상태 | 우선순위 | 사용자 작업 |
| --- | --- | --- | --- |
| Play 개발자 계정 | needs_user_action | P0 | 개인/조직 유형과 생성일 확인 |
| 12명·14일 비공개 테스트 | needs_user_action | P0 | 2023-11-13 이후 생성된 개인 계정인지 확인 후 해당되면 수행 |
| Production access 신청 | needs_user_action | P0 | 대상 개인 계정이면 비공개 테스트 이후 신청 |
| AAB | ready | P0 | 로컬 upload key로 signed release AAB 생성·서명 검증 완료. Play 업로드 전 최종 설정값 빌드 필요 |
| Play App Signing | needs_user_action | P0 | Play Console에서 활성화하고 배포 인증서 제한 등록 |
| target API | ready | P0 | 2026-08-31 시행 API 36 요구에 현재 target 36이 부합 |
| 개인정보처리방침 | blocked | P1 | 공개 URL 작성·게시 |
| Data safety | needs_user_action | P1 | Maps/Supabase 실제 처리를 반영해 작성 |
| 앱 액세스 | needs_user_action | P1 | 로그인 없음, 모든 핵심 기능 공개로 선언 |
| 광고 | needs_user_action | P1 | 현재 광고 없음으로 선언 |
| 대상 연령·콘텐츠 등급 | needs_user_action | P1 | 타깃 연령 선택 및 questionnaire 완료 |
| 지원 연락처 | blocked | P1 | 스토어 지원 이메일 필수, 웹사이트 권장 |
| 앱 아이콘 | blocked | P1 | 512x512 PNG/JPEG, 1MB 이하 |
| feature graphic | blocked | P1 | 1024x500 준비 |
| 휴대전화 스크린샷 | blocked | P1 | 최소 2장, 핵심 지도·검색·상세 상태를 정직하게 표시 |
| 앱 설명 | blocked | P1 | 실제 MVP 범위만 설명하고 제외 기능을 암시하지 않음 |
| 내부/비공개 테스트 | blocked | P1 | Play 설치본과 실제 기기 검증 필요 |

Google Play 심사는 최대 7일 이상 걸릴 수 있으므로 출시일 직전 제출을 피한다. 계정 생성일과 유형은 저장소에서 확인할 수 없으므로 사용자가 Play Console에서 확인해야 한다.

## 9. 테스트 공백

### 완료된 자동 검증

- `dart format --output=none --set-exit-if-changed .`: 25개 파일, 변경 0
- `flutter analyze --no-pub`: 이슈 0
- `flutter test --no-pub`: 87개 통과
- Python 전체 테스트: 112개 통과
- debug APK 빌드: 성공, 약 182.7 MiB
- Phase 5B release AAB 진단 빌드와 bundle 검사는 당시 성공
- Phase 5C-A signed release AAB 빌드와 `jarsigner -verify`: 성공
- release bundle 검사: staging entry 0, AssetManifest staging 참조 0, staging 식별 값 0, 비밀 패턴 0
- Android 환경: Flutter 3.44.8, Dart 3.12.2, Android SDK 36.1, licenses 동의 완료
- 현재 연결 에뮬레이터: Android 15/API 35

새 signed AAB는 로컬 upload key로 서명됐고 release runtime은 production/Supabase로 고정되며 pilot/staging으로 복귀하지 않는다. Play 배포 전에는 production 설정값, Play App Signing, 스토어 메타데이터와 정책 검증이 별도로 필요하다.

### 남은 검증

| 검증 | 상태 | 우선순위 | 완료 조건 |
| --- | --- | --- | --- |
| production release mode | ready | P0 | Supabase 전용, pilot/staging fallback 없음, 설정 누락 fail-closed 자동·수동 검증 완료 |
| release Maps key | partial | P0 | debug 설치본 지도·마커 확인 완료. upload/Play App Signing 인증서로 각각 제한 후 확인 필요 |
| release signing | partial | P0 | upload key signed AAB 검증 완료. Play App Signing과 Play 설치본 확인 필요 |
| 실제 Android 기기 | blocked | P1 | 최소 1대, 권장 2대에서 핵심 흐름 확인 |
| 느린 네트워크·오프라인 | blocked | P1 | 시작·재시도·복귀에서 crash/무한 loading 없음 |
| Supabase 401·5xx | blocked | P1 | 사용자에게 일반 오류와 재시도, 민감정보 미노출 |
| Maps 권한 거부/키 오류 | blocked | P1 | 빈 검은 화면 대신 안전한 오류 경험 |
| background/resume | blocked | P1 | 지도와 검색·필터·선택 상태가 합리적으로 유지 |
| 긴 텍스트·작은 화면 | ready | P2 | widget test와 기존 emulator 수동 검증 있음 |
| TalkBack·font scaling·contrast | blocked | P2 | 실제 접근성 수동 검증 필요 |
| Play internal track 설치 | blocked | P1 | 스토어에서 받은 앱으로 설치·업데이트·실행 확인 |
| crash monitoring | deferred | P2 | 개인정보 고지와 함께 도입하거나 초기에는 Android vitals 집중 |

## 10. 사용자 직접 작업

1. Play Console에서 개발자 계정 유형과 생성일을 확인한다.
2. 확정된 application ID `com.burgermapkorea.app`을 Play·Google Maps 설정에 동일하게 사용한다.
3. 생성한 upload key를 별도 안전 장소에 백업하고 Play App Signing을 설정한다.
4. Google Cloud 제한에 Play App Signing SHA-1을 추가하고, 로컬 release 지도 테스트 시 upload 인증서 SHA-1도 추가한다.
5. Maps Billing, quota, 예산 알림을 확인한다.
6. production Supabase Project URL과 Publishable key를 저장소 밖의 빌드 비밀값으로 준비한다.
7. 공개 후보 매장을 사람이 재검수하고 게시를 개별 승인한다.
8. 공개 개인정보처리방침 URL과 지원 이메일을 준비한다.
9. Data safety, 앱 액세스, 광고 여부, 대상 연령, 콘텐츠 등급을 Play Console에서 작성한다.
10. 브랜드 앱 이름, adaptive icon, splash, feature graphic, 스크린샷, 설명을 승인한다.
11. 실제 Android 기기와 필요한 비공개 테스터를 확보한다.
12. 매장 오류·폐업·정정 요청을 받을 운영 연락처와 처리 절차를 정한다.

## 11. 단계별 출시 계획

### Phase 5B: Production runtime과 환경 분리

- 상태/우선순위: `ready`, P0
- 목표: release가 production Supabase와 Google Maps를 사용하고 잘못된 설정은 fail-closed 처리
- 완료 내용: production/release Supabase 고정, 로컬 fallback 제거, 환경 검증, production 일반 오류 UI, 기술 UI development 한정, debug 전용 staging asset 패키징과 release bundle 검증
- 사용자 작업: production URL/Publishable key와 새 application ID에 제한된 Maps key 준비
- 완료 조건: release mode에서 Supabase 데이터만 표시, 누락 설정 시 로컬 데이터 미표시, 키 없는 자동 빌드 테스트 유지
- 예상 시간: 개발 2~4일, 사용자 설정 0.5~1일
- 선행조건: 완료된 application ID 확정 유지

### Phase 5C: 공개 매장 데이터 확장

- 상태/우선순위: `blocked`, P1
- 목표: 실제 탐색에 유용한 최소 공개 데이터 확보
- 코드 작업: 기존 검수표·SQL 생성기의 안전성 회귀 확인만 수행
- 사용자 작업: 10~15곳 비공개 테스트용, 권장 20~30곳 공개용 매장의 영업·주소·좌표·전문성·스타일·출처일 검수와 개별 승인
- 완료 조건: approved/verified 근거가 있는 매장만 SQL 생성·수동 게시, 앱에서 위치 표본 검사
- 예상 시간: 검수 5~10영업일
- 선행조건: 검수 담당자와 게시 기준 확정

### Phase 5D: Android release·브랜드·법적 자료

- 상태/우선순위: `blocked`, P0/P1
- 목표: Play 업로드 가능한 서명 AAB와 정식 브랜드·정책 자료 준비
- 코드 작업: release signing 구조, 앱 label, adaptive icon, splash, backup 결정, privacy/notices 접근 경로, version 관리
- 사용자 작업: upload key 생성·백업, 브랜드 자산 승인, 개인정보처리방침 게시, 지원 연락처 확정
- 완료 조건: 비밀값 미추적, upload key 서명 AAB, 정식 이름/아이콘/스플래시, 활성 privacy URL
- 예상 시간: 개발 3~5일, 디자인·정책 2~5일
- 선행조건: application ID와 앱 이름 확정

### Phase 5E: Play Console과 비공개 테스트

- 상태/우선순위: `needs_user_action`, P0/P1
- 목표: Play 배포 경로에서 기능·정책 검증
- 코드 작업: 발견된 결함만 최소 수정, versionCode 증가
- 사용자 작업: 스토어 등록정보, Data safety, 콘텐츠 등급, 대상 연령, 광고/앱 액세스 선언, internal/closed track 운영
- 완료 조건: Play 설치본 실제 기기 핵심 흐름 통과, 대상 개인 계정이면 12명 연속 14일 비공개 테스트와 production access 요건 충족
- 예상 시간: 최소 14일(해당 계정) + 수정 2~5일
- 선행조건: Phase 5B~5D 완료

### Phase 5F: 공개 출시

- 상태/우선순위: `deferred`, P1
- 목표: production track 배포와 초기 운영 안정화
- 코드 작업: 최종 versionCode, release notes, 치명 결함 수정
- 사용자 작업: production access 신청/출시 제출, 단계적 배포, Play vitals와 매장 정정 요청 확인
- 완료 조건: 원격 production 데이터, 지도, 검색, 필터, 상세 화면 정상; crash/ANR 기준 양호; rollback 절차 확인
- 예상 시간: 심사 1~7일 이상, 단계적 배포 3~7일
- 선행조건: Phase 5E 통과

## 12. 예상 일정

### 지도 중심 MVP

- 12명·14일 요건이 적용되지 않는 계정: 약 2~3주
- 12명·14일 요건이 적용되는 신규 개인 계정: 약 4~6주
- 데이터 검수, 브랜드 자산, 개인정보처리방침 준비가 늦으면 1~2주 이상 추가될 수 있다.

권장 경로는 Phase 5B를 즉시 시작하고, Phase 5C 데이터 검수와 Phase 5D 브랜드·정책 준비를 병렬 진행하는 것이다. 비공개 테스트 중 발견된 결함을 고친 뒤 Phase 5F로 이동한다.

### 메뉴·리뷰 포함 버전

첫 공개 후 최소 8~12주를 별도로 예상한다. 실제로는 메뉴 데이터 모델과 출처/최신성 관리, Auth, 계정 삭제, UGC 신고·차단·관리자 검수, 개인정보 고지, 앱 심사 재검증까지 포함해 10~16주가 더 현실적이다. 현재 MVP 일정에 이 기능을 끼워 넣지 않는다.

## 13. 공식 출처

모든 링크는 2026-08-20에 확인했다.

- [Google Play 개인 계정 비공개 테스트 요건](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en)
- [Google Play target API 수준 요구사항](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-GB_ALL)
- [Google Play Data safety 작성 안내](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
- [Google Play 앱 콘텐츠와 심사 준비](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en-EN)
- [Google Play 스토어 등록정보·그래픽 자산](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
- [Google Play 앱 심사 시간](https://support.google.com/googleplay/android-developer/answer/9859751?hl=en_EN)
- [Google Play 지원 연락처 요구사항](https://support.google.com/googleplay/android-developer/answer/13634081?hl=en)
- [Google Play 콘텐츠 등급](https://support.google.com/googleplay/android-developer/answer/9859655?hl=en)
- [Android 앱 서명과 Play App Signing](https://developer.android.com/studio/publish/app-signing)
- [Android application ID 구성](https://developer.android.com/build/configure-app-module)
- [Android application manifest 기본값](https://developer.android.com/guide/topics/manifest/application-element.html)
- [Flutter Android release 빌드](https://docs.flutter.dev/deployment/android)
- [Google Maps API key 보안 권장사항](https://developers.google.com/maps/api-security-best-practices)
- [Maps SDK for Android 데이터 공개 안내](https://developers.google.com/maps/documentation/android-sdk/play-data-disclosure)
- [Maps SDK for Android 사용량과 Billing](https://developers.google.com/maps/documentation/android-sdk/usage-and-billing)
- [Supabase 데이터베이스 보안과 RLS](https://supabase.com/docs/guides/database/secure-data)
- [Supabase API key 유형](https://supabase.com/docs/guides/getting-started/api-keys)

## 감사 결론

지도 중심 MVP, production Supabase fail-closed 경로, release staging asset 제거, Android application ID, 로컬 upload signing은 준비됐다. 다만 Play App Signing 인증서 제한, production Supabase 결정, 공개 매장 확장과 Play Console 자료가 남아 아직 출시 가능한 최종 상태는 아니다.
