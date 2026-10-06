# Google Play Data Safety — 제출 준비용 초안

**Phase 2 ?? ?? ? 2026-10-06:** Flutter ?? ?? UI/client contract? **IMPLEMENTED_AND_TESTED_LOCAL**. Backend **IMPLEMENTED_LOCAL_NOT_DEPLOYED**, Production **NOT_DEPLOYED**. ?? ?? UI ??? ??? ????, ?????? ?? ??? ??? ???. [Flutter ?? ???](account-deletion-flutter-local-2026-10-06.md)

**Backend ?? ?? (2026-10-05): IMPLEMENTED_LOCAL_NOT_DEPLOYED.** ?? ?? Auth JWT E2E 57? ??? ?? ??? 7?? ????. ?? Auth/profile/reviews ? ?? reports CASCADE, ?? ?? ??, ?? JWT/RLS? ????. ?? ?? ?? ???? **?? production ? ??**??. Flutter UI??? ?? URL?production ??? ???? Play ??? ?? ?? ??? YES? ??? ???. Auth audit/??/SCIM ?? ???????? ?? ?? ????. [?? ???](account-deletion-backend-local-2026-10-05.md)

기준일: 2026-10-05. Android package `com.burgermapkorea.app`. HEAD `f152a65121f7488df89cd3324ca6401170b7a105`. **제출 불가 상태: NEEDS VERIFICATION 항목과 계정 삭제 경로를 해결한 뒤 확정한다.** 본 문서의 YES/NO는 현재 구현 기준이며 미래 계획을 완료로 표시하지 않는다.

## 1. 판정 규칙

정책 근거: [Google Play Data Safety 작성 지침](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en), [User Data](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en). 확인일 2026-10-05.

- Collected는 SDK를 포함한 기기 밖 전송을 기준으로 한다. 기기 내부 접근만으로 YES를 만들지 않는다.
- 메모리 내 일시 처리라도 기기 밖 전송이면 양식에 포함하고 ephemeral 요건을 별도로 판정한다. 앱의 메모리 보관과 공급자의 서버 보관을 혼동하지 않는다.
- Shared는 제3자 이전과 예외를 검토한다. 처리수탁자, 예상 가능한 사용자 주도 전송 등의 예외를 자동 적용하지 않는다.
- 게스트 탐색이 가능하므로 로그인할 때만 취득하는 계정 정보는 앱 전체 기준 Optional 후보다. 리뷰에 필요한 닉네임·평가 값의 필수성은 해당 기능의 입력 요건이다.
- 가명 UUID/SDK 식별자는 익명 정보가 아니다. 권한 선언만으로 수집이나 미수집을 결론내리지 않는다.

## 2. 근거 인덱스

| ID | 코드·스키마 근거 |
|---|---|
| E1 | `lib/main.dart:60`, `lib/features/auth/data/native_google_token_provider.dart:7` (`email`, `profile`, ID/access token), `lib/features/auth/data/supabase_auth_repository.dart:37` (이메일 링크), `:51` (Google token exchange), `:93` (프로필), `:147` (로그아웃) |
| E2 | `supabase/migrations/20260922050439_auth_menu_reviews.sql:5` profiles, `:40` reviews, `:65` reports; `20260928054821_optional_review_content.sql:3` 선택적 본문 |
| E3 | `lib/features/reviews/data/supabase_review_repository.dart:9` 공개 select, `:62` 작성자 조회, `:89` 생성, `:117` 삭제, `:130` 신고; `domain/review_report.dart:1`; `presentation/store_review_section.dart:632` 신고 대화상자 |
| E4 | `lib/features/location/data/geolocator_current_location_service.dart:63` 위치 요청, `:89` 정확도·캐시, `:128` 좌표 변환; `application/current_location_controller.dart:138` 배경 무효화 |
| E5 | `lib/features/map/presentation/map_screen.dart:205` 로컬 거리, `:300` lifecycle, `:595` My Location, `:1124` 위치 버튼·카메라; `stores/domain/google_maps_directions.dart:5` 외부 목적지 링크 |
| E6 | `lib/features/favorites/data/shared_preferences_favorite_store_ids_store.dart:8` 매장 ID 로컬 저장; `lib/features/info/presentation/app_info_screen.dart:119` 위치 안내·`:138` 방침 링크 |
| E7 | `lib/features/stores/data/supabase_store_locations_loader.dart:135` 개발 로그, `:149` Supabase 초기화 `debug:false`; `lib/core/config/app_config.dart:289` debug 설정 로그; `android/app/src/main/AndroidManifest.xml` |
| E8 | `pubspec.yaml`, `pubspec.lock`, `.dart_tool/package_config.json`; resolved SDK source: `supabase_flutter-2.17.2/lib/src/flutter_go_true_client_options.dart:37`, `supabase.dart:130`, `supabase_auth.dart:194`, `local_storage.dart:110`; `gotrue-2.27.2/lib/src/types/session.dart:58`, `user.dart:95` |
| E9 | `supabase/migrations/0001_init_store_schema.sql`, `20260924140656_menu_evidence_v1.sql`; 앱은 매장·메뉴를 읽고 개인 위치를 요청 인자로 넣지 않음 |

SDK source는 로컬 Pub cache에서 읽었다. 이 표의 위치는 감사 당시 버전 기준이며 사용자 token/metadata 값은 열람하지 않았다. 실제 production FK drift, 공급자 계약·리전·백업·로그 설정은 이번 감사에서 원격 조회하지 않았다.

## 3. 실제 데이터 흐름 전수표

표의 Collected는 Play 정의다. `NV`는 NEEDS VERIFICATION이며 미수집 의미가 아니다. `외부` 열은 실제 처리 주체이고 양식 Shared 예외 적용은 다음 표에서 별도로 판정한다. 앱 DB에 보유 기간/TTL 작업은 확인되지 않았다.

| Data type | Collected? | Stored? / Local or Server | Purpose | Required or Optional? | 외부 처리/공개 | Retention | Deletion behavior | Evidence |
|---|---|---|---|---|---|---|---|---|
| Google 계정 식별자, Supabase UUID | YES | Auth 서버 + SDK session/user JSON 로컬 | 인증·계정·작성자 식별 | Optional 로그인 | Google, Supabase; 리뷰 작성자 UUID는 공개 | Auth/로그 정책 NV, 로컬 session 유지 | 계정 삭제 경로 없음; logout은 로컬 세션 제거 | E1,E2,E8 |
| 이메일 | YES | Supabase Auth + 로컬 user JSON; 이메일 링크 입력은 UI 메모리 | 로그인/링크 전송 | Optional 로그인 | Google/Supabase/메일 전달자; 리뷰에 비공개 | 계정·메일 공급자 기간 NV | 계정 삭제 미구현 | E1,E8 |
| Google 표시 이름/사진 URL | YES, 제공되는 필드에 한함 | plugin 반환; Auth metadata/로컬 JSON의 구체적 필드 존재 NV | 인증 프로필 | Optional 로그인; 제공 여부 계정별 상이 | Google/Supabase; 앱의 공개 프로필 사진 표시 없음 | metadata/공급자 보유 NV | 계정 삭제 미구현; 사진 원본은 Google 관리 | E1,E8, Google OIDC |
| ID/access/refresh token | YES (인증 교환) | Supabase 세션 JSON 로컬, Auth 서버 session; provider token은 응답에 있을 때 포함 | 인증 유지·접근 통제 | Optional 로그인 | Google/Supabase; 일반 공개 없음 | token/session 만료·로그 설정 NV | logout 로컬 삭제; 원격 session/잔존 JWT 별도 관리 필요 | E1,E8 |
| 닉네임 | YES | profiles 서버·UI 메모리 | 리뷰 작성자 표시 | Optional 계정 기능; 리뷰 전에 필수 | Supabase, 공개 리뷰 작성자 이름 | 자동 TTL 없음 | 계정 삭제 미구현; FK상 Auth 삭제 시 cascade | E2,E3 |
| is_suspended 및 profile timestamps | YES, 서버 생성/관리 포함 | profiles 서버; 앱 select는 id/nickname만 | 운영·기여 제한 | 계정에 부수되는 기록 | Supabase 운영자 | TTL 없음 | profiles cascade 대상 | E2 |
| 평가 1~5, 선택 본문, user/store 관계, timestamps | YES | reviews 서버, 표시 메모리 | 공개 선호도·리뷰 | Optional 제출, rating 필수·본문 선택 | Supabase, 다른 이용자 | 본인 삭제까지; TTL 없음 | 본인 review DELETE 제공; 연결 reports cascade | E2,E3 |
| 숨김/운영 메모·시각·담당 | YES, 서버 생성 포함 | reviews 내부 관리 열 | 콘텐츠 관리 | 리뷰에 부수 | Supabase 운영자; 본인은 숨김 상태 확인 가능 | TTL 없음 | 리뷰 삭제와 함께 제거 | E2,E3 |
| 신고자·리뷰 ID, reason/detail, status/처리 metadata | YES | review_reports 서버 | 신고·안전·운영 | Optional 신고; 기타 사유 설명 필수 | Supabase 운영자; 신고자 공개 안 됨 | TTL 없음 | 신고자가 직접 삭제하는 경로 없음; review/profile 삭제 시 cascade | E2,E3 |
| 정확/대략 위치, 정확도·시각 | 앱 자체 off-device NO; 전체 NV | 앱 메모리, OS last-known 조회; Supabase/앱 저장 없음 | 위치·거리·가까운 순 | Optional 권한/기능 | Google Maps 카메라/My Location, OS 위치 provider | 앱 신선도 2분, 배경 무효화; SDK/OS NV | 앱 메모리 무효화; SDK 서버 보유 여부 NV | E4,E5 |
| 즐겨찾기 매장 IDs | 앱 서버 NO; OS 백업 NV | SharedPreferences 로컬 | 즐겨찾기 | Optional | 앱의 동기화 없음; OS backup 별도 | 해제/앱 데이터 삭제까지 | 항목 해제; 계정 logout과 별개 | E6 |
| 검색어·스타일·지역 필터·정렬 | 앱 자체 NO | 메모리 | 매장 탐색 | Optional | 자체 검색 API/분석 전송 없음 | 화면/프로세스 상태 수명 | 상태 초기화 | E5, `map_screen.dart` |
| 공개 stores/menus/menu_evidence | 이용자 데이터 NO (이 기능에서) | 서버 + 읽기 메모리; evidence는 private schema | 매장 정보 제공 | 탐색 데이터 | Supabase, 공개 메뉴/매장; evidence 직접 클라이언트 미노출 | 별도 운영 자료 | Auth 삭제와 무관; 사용자 데이터로 임의 삭제 금지 | E9 |
| 외부 길찾기/링크 | 목적지 전송 YES; 현재 사용자 위치 첨부 NO | 외부 앱·웹, 해당 서비스 정책 | 길찾기·지원·정책 열기 | Optional 탭 | Google Maps/브라우저/메일 앱 | 외부 NV | 외부 정책; 식별 데이터 분류는 목적지·문의내용별 판단 | E5,E6 |
| Maps 기기/요청 metadata, IP, SDK 식별자 | YES, 공식 SDK 안내 | Google 처리, 구체 보유 NV | 기능·서비스 개선·사용 측정 | 지도 사용 기본 수집 | Google | NV | 앱 계정 삭제로 SDK 기록까지 지워짐을 보장 못함 | E8, Maps 공식 안내 |
| Maps SDK crash/stack·지도 pan/zoom 이벤트 | YES (발생/Camera API 사용 시) | Google 처리 | 진단·분석·서비스 개선 | 앱에 수집 opt-out 없음 | Google | NV | 공급자 삭제 경로 NV | E5,E8, Maps 공식 안내 |
| Auth/접속 로그: 시각·IP·user agent·user ID·이벤트 | YES / 실제 서버 저장 옵션 NV | Supabase 서버 로그; DB 로그 저장은 설정별 | 보안·운영 | 서비스 통신에 부수 | Supabase 및 설정된 로그/메일 공급자 NV | 프로젝트 plan/설정 NV | 계정 삭제 cascade만으로 로그·백업 제거 보장 안 됨 | E7, Supabase audit logs 공식 안내 |
| 앱 자체 개발 진단 | release 전송 NO | debug 콘솔: 설정 상태/안전 오류 code | 개발 진단 | release 비활성 | 자체 외부 수집 sink 없음 | 개발 환경 | 기기/개발 로그 관리; 좌표 logger 경로 없음 | E7 |

Stores/menu 데이터에 일반 방문자 계정 FK는 없으나 공개 사업장 자료의 개인정보 가능성까지 부정하지 않는다. evidence의 source URL/notes에 제3자 개인정보가 있는지는 별도 데이터 검토이며 이 감사에서 원문 사용자 자료를 열람하지 않았다.

## 4. Data Safety 양식 답변 초안

`Shared=NV`는 실제 외부 전송은 확인됐지만 Google Play 예외와 계약 역할을 확정하지 못했다는 뜻이다. Supabase 위탁 처리와 사용자 주도 공개 게시의 예외를 검토한 뒤 NO로 확정할 수 있는지 결정한다. Google의 자체 서비스 개선 처리를 일괄 수탁 처리라고 가정하지 않는다.

| Category / type | Collected? | Shared? | Purpose 후보 | Required? | Ephemeral? | Deletion supported? |
|---|---|---|---|---|---|---|
| Personal info / Name (닉네임, 제공된 Google 이름) | YES | NV: 공개 닉네임의 사용자 주도 공유 예외·Google 역할 | App functionality, Account management | NO: 게스트 가능 | NO: profile 저장 | NO: 전체 계정 삭제 없음 |
| Personal info / Email | YES | NV: Auth·메일 공급자 역할 | Account management, App functionality | NO: 로그인 선택 | NO | NO |
| Personal info / User IDs | YES | NV: Google/Supabase 및 공개 author ID | Account management, App functionality, Fraud prevention/security | NO: 계정 ID 기준 | NO | NO |
| Location / Approximate | NEEDS VERIFICATION | NEEDS VERIFICATION | App functionality; SDK/로그 IP의 위치 사용 여부 확인 | NV: 권한 기능 선택이나 SDK IP 처리는 별도 | NV | NV |
| Location / Precise | NEEDS VERIFICATION | NEEDS VERIFICATION | App functionality | NO 후보: 위치 선택 | NV | NV |
| App activity / Other user-generated content (리뷰·신고) | YES | NV: 공개 게시 사용자 주도 예외, 비공개 신고 위탁 | App functionality, Fraud prevention/security | NO: 제출 선택 | NO | 부분: 본인 리뷰 YES; 신고/전체 계정 NO |
| App activity / App interactions | YES: Maps camera 이벤트 | NEEDS VERIFICATION | Analytics, App functionality 후보; 공급자 목적과 대조 | YES 후보: 지도 카메라 사용 시 별도 거부 없음 | NV | NV |
| App activity / In-app search history | NO: 앱 코드 검색어 전송/저장 없음 | NO: 해당 검색어 경로 | 해당 없음 | 해당 없음 | 해당 없음 | 해당 없음 |
| Device or other IDs | YES: Maps SDK 가명 ID | NEEDS VERIFICATION | Analytics, App functionality 후보 | YES 후보: 기본 SDK 처리 | NV | NV |
| App info and performance / Crash logs | YES: Maps SDK crash 발생 시 | NEEDS VERIFICATION | Analytics (안정성 진단) | YES 후보: 해당 오류 발생 시 opt-out 없음 | NV | NV |
| App info and performance / Diagnostics | YES: Maps 요청·기기/성능 정보 | NEEDS VERIFICATION | Analytics, App functionality 후보 | YES 후보 | NV | NV |
| App info and performance / Other performance data | NEEDS VERIFICATION: SDK별 경계 | NEEDS VERIFICATION | NV | NV | NV | NV |
| Photos and videos / Photos | NEEDS VERIFICATION: 사진 업로드 없음; Google picture URL 및 identity metadata 분류 확인 | NEEDS VERIFICATION | Account management 후보 | NO 후보 | NV | NO: account deletion 없음 |
| Personal info / Other info | NEEDS VERIFICATION: suspension/security metadata의 범주 | NEEDS VERIFICATION | Fraud prevention/security | 계정 기능 부수 | NO | NO |
| Financial, Health, Contacts, Calendar, Audio, Files/docs, Web browsing, SMS/in-app messages, Phone number, Race/religion/politics, Sexual orientation | NO: 현재 앱 기능·호출에 해당 전송 경로 없음 | NO: 해당 경로 | 해당 없음 | 해당 없음 | 해당 없음 | 해당 없음 |

마지막 NO는 임의의 리뷰 본문에 이용자가 개인정보를 적지 못한다는 보장이 아니다. 앱이 의도적으로 요청하는 데이터와 자유 텍스트 UGC를 구분한다. 리뷰를 메시징 서비스로 분류하지 않는다. SDK 전체 검증에서 새 수집이 확인되면 해당 답변을 갱신한다.

### 앱 수준 질문

| 질문 | 현재 답변 초안 | 이유 |
|---|---|---|
| 필수 공개 대상 데이터를 수집/공유하는가 | YES | 인증·프로필·리뷰·신고 및 Maps SDK 처리 |
| 모든 데이터가 전송 중 암호화되는가 | NEEDS VERIFICATION (앱 Supabase HTTPS PASS) | Google SDK·Auth·외부 링크 전체 확인 전 전역 YES 금지; E7 및 release config |
| 계정 생성 방법 | Google SSO + 이메일 로그인 링크 | 앱 내 신규 Auth identity 생성 가능; 비밀번호 입력 흐름 없음 |
| 계정 삭제 시작 가능 | NO (현재) | logout만 있음; 앱/웹 삭제 경로 미구현 |
| 계정 삭제 URL | TODO | 현재 검증된 public URL 없음 |
| 계정 삭제 없이 일부 데이터 삭제 가능 | YES: 본인 리뷰 / 로컬 즐겨찾기; 전체 범위 NV | 신고 삭제 및 Auth 데이터 삭제를 지원한다고 답하지 않음 |
| 독립 보안 심사 | NO evidence / NEEDS VERIFICATION | 심사받았다는 증거 없음 |
| Families 대상 | NEEDS USER DECISION | 목표 연령 미확정; 자동으로 아동용 또는 비아동용 선언 금지 |

양식의 실제 문항/선택지가 달라지면 의미에 맞게 대조한다. 확인되지 않은 곳에 추측한 YES/NO를 입력하지 않는다. 앱의 모든 활성 배포/지역별 동작을 포함해 최종 답변을 점검한다.

## 5. Dependencies 및 SDK별 처리

| 직접 dependency (locked) | 현재 역할과 데이터 영향 |
|---|---|
| flutter SDK, cupertino_icons 1.0.9 | UI/프레임워크. 앱 자체 analytics/crash 업로드 호출 없음; 도구 telemetry와 배포 앱 처리를 구분 |
| geolocator 14.0.3 / Android 5.0.3 | 전경 위치 조회, Play services location 21.2.0. 앱 저장·Supabase 전송 없음. OS/Fused provider의 실제 외부 처리는 별도 검증 |
| google_maps_flutter 2.18.0 / Android 2.19.12 | native Maps 20.0.0, maps-utils 4.1.0. Maps 공식 자동/조건부 수집을 반영; SDK 페이지는 최신 버전 기준이므로 출하 버전과 재대조 |
| google_sign_in 7.2.0 / Android 7.2.17 | credentials 1.6.0, credentials-play-services-auth 1.6.0, googleid 1.2.0, play-services-auth 21.6.0. email/profile 및 인증 tokens. 별도 Sign-In telemetry 세부 목록은 확인되지 않아 NO 단정 금지 |
| shared_preferences 2.5.5 / Android 2.4.27 | 즐겨찾기와 Supabase session 저장. 자체 앱 서버 동기화 없음; OS backup/기기 이전 검증 필요 |
| supabase_flutter 2.17.2 | gotrue 2.27.2, supabase 2.16.1, postgrest 2.9.1 등. Auth 및 DB 요청, 자동 session persistence. 자체 광고/제품 analytics sink는 발견되지 않았으나 서버 Auth/접속 로그 존재 |
| url_launcher 6.3.2 / Android 6.3.32 | 사용자가 선택한 외부 URL/지도/메일 앱. 자동 위치·계정 token 첨부 없음 |

전체 locked package 목록은 아래 부록에 자동 전사한다. 다른 OS용 구현과 dev/test 패키지도 lockfile에는 있으므로 Android release에서 모두 실행된다고 해석하지 않는다. Firebase Analytics/Crashlytics, Sentry, 광고 SDK는 pubspec/lock 및 lib 호출 검색에서 발견되지 않았다. 의존성 존재만으로 해당 기능의 사용을 선언하지 않는다.

Supabase에 포함된 `functions_client`, `realtime_client`, `storage_client`, `passkeys_platform_interface`, `package_info_plus`, `app_links`는 각각 기능 지원/앱 정보/딥링크용 전이 의존성이다. 현재 lib에는 파일 업로드, Realtime 구독, passkey 인증, Edge Function 호출 기능이 없다. HTTP/WebSocket/JSON/crypto/플랫폼 bridge 패키지는 상위 기능의 처리 경로로 분류한다. 단순 패키지명만으로 공급자 원격 수집이 없다고 보증하지 않는다.

공식 기술 근거:

- [Maps SDK 데이터 처리](https://developers.google.com/maps/documentation/android-sdk/play-data-disclosure): metadata, SDK ID, IP, crash, 카메라 상호작용.
- [Google OIDC](https://developers.google.com/identity/openid-connect/openid-connect): sub/email 및 조건부 name/picture. [Google Sign-In과 Supabase](https://supabase.com/docs/guides/auth/social-login/auth-google).
- [Play services core 공개 안내](https://developers.google.com/android/guides/play-data-disclosure): base/basement/tasks 등에 한정된 설명을 Auth/Maps/Location 전체로 확대하지 않는다.
- [Supabase 인증 로그](https://supabase.com/docs/guides/auth/audit-logs), [세션](https://supabase.com/docs/guides/auth/sessions).

## 6. 제출 전 확인해야 할 사실

1. 운영자·문의처·목표 연령·서비스 국가·보유/삭제 기한, Supabase 리전/계약/로그·백업/메일 전달자.
2. 개인정보 값이나 tokens를 출력하지 않고 Google metadata 필드 존재 여부와 공급자별 삭제 범위를 확인.
3. Maps 20.0.0 및 인증·위치 SDK의 location off-device 여부, retention, sharing 예외 적용, 전송 암호화 근거. 권한 거부/정확/대략 시나리오별로 비교.
4. 앱/웹 계정 삭제, 정책 링크, UGC 동의 및 사용자 신고/차단을 구현·검증한 최종 release와 양식을 일치시킴.
5. Release Maps PASS로 갱신(현재 사용자 확인). 실제 production Maps key 프로젝트의 package + release SHA-1 restriction 수정으로 해결됐으며 원인은 `MAPS_RELEASE_SHA_RESTRICTION`. 이번 backend 작업에서 실기기를 재검증한 것은 아니다. Maps SDK 데이터 처리는 계속 공개 범위에 포함한다.

관련 산출물: [개인정보처리방침](privacy-policy-draft-ko.md), [커뮤니티 가이드라인](community-guidelines-draft-ko.md), [정책 감사와 단계별 계획](android-release-readiness-2026-10-03.md#google-play-policy-readiness-audit--2026-10-05).

## 7. 전체 pubspec.lock inventory

아래는 의존성 존재/버전 재현용이다. 각 package의 독립적인 원격 telemetry 부재를 증명한 표가 아니다. `direct dev` 및 다른 플랫폼용 항목은 실제 Android release 활성 여부와 구분한다.

| Package | Version | Dependency |
|---|---|---|
| app_links | 7.2.1 | transitive |
| app_links_linux | 1.0.3 | transitive |
| app_links_platform_interface | 2.0.4 | transitive |
| app_links_web | 1.0.4 | transitive |
| args | 2.7.0 | transitive |
| async | 2.13.1 | transitive |
| boolean_selector | 2.1.2 | transitive |
| characters | 1.4.1 | transitive |
| clock | 1.1.2 | transitive |
| collection | 1.19.1 | transitive |
| convert | 3.1.2 | transitive |
| crypto | 3.0.7 | transitive |
| csslib | 1.0.2 | transitive |
| cupertino_icons | 1.0.9 | direct main |
| dart_jsonwebtoken | 3.4.1 | transitive |
| dbus | 0.7.15 | transitive |
| fake_async | 1.3.3 | transitive |
| ffi | 2.2.0 | transitive |
| ffi_leak_tracker | 0.1.2 | transitive |
| file | 7.0.1 | transitive |
| fixnum | 1.1.1 | transitive |
| flutter | 0.0.0 | direct main |
| flutter_driver | 0.0.0 | transitive |
| flutter_lints | 6.0.0 | direct dev |
| flutter_plugin_android_lifecycle | 2.0.35 | transitive |
| flutter_test | 0.0.0 | direct dev |
| flutter_web_plugins | 0.0.0 | transitive |
| fuchsia_remote_debug_protocol | 0.0.0 | transitive |
| functions_client | 2.7.1 | transitive |
| geoclue | 0.1.1 | transitive |
| geolocator | 14.0.3 | direct main |
| geolocator_android | 5.0.3 | transitive |
| geolocator_apple | 2.3.14 | transitive |
| geolocator_linux | 0.2.6 | transitive |
| geolocator_platform_interface | 4.3.0 | transitive |
| geolocator_web | 4.1.4 | transitive |
| geolocator_windows | 0.2.5 | transitive |
| google_identity_services_web | 0.3.3+1 | transitive |
| google_maps | 8.3.0 | transitive |
| google_maps_flutter | 2.18.0 | direct main |
| google_maps_flutter_android | 2.19.12 | transitive |
| google_maps_flutter_ios | 2.18.4 | transitive |
| google_maps_flutter_platform_interface | 2.16.0 | transitive |
| google_maps_flutter_web | 0.6.3 | transitive |
| google_sign_in | 7.2.0 | direct main |
| google_sign_in_android | 7.2.17 | transitive |
| google_sign_in_ios | 6.3.5 | transitive |
| google_sign_in_platform_interface | 3.1.0 | transitive |
| google_sign_in_web | 1.1.3 | transitive |
| gotrue | 2.27.2 | transitive |
| gsettings | 0.2.8 | transitive |
| gtk | 2.2.0 | transitive |
| html | 0.15.6 | transitive |
| http | 1.6.0 | transitive |
| http_parser | 4.1.2 | transitive |
| integration_test | 0.0.0 | direct dev |
| json_annotation | 4.12.0 | transitive |
| leak_tracker | 11.0.2 | transitive |
| leak_tracker_flutter_testing | 3.0.10 | transitive |
| leak_tracker_testing | 3.0.2 | transitive |
| lints | 6.1.0 | transitive |
| logging | 1.3.0 | transitive |
| matcher | 0.12.19 | transitive |
| material_color_utilities | 0.13.0 | transitive |
| meta | 1.18.0 | transitive |
| mime | 2.0.0 | transitive |
| package_info_plus | 10.2.1 | transitive |
| package_info_plus_platform_interface | 4.1.0 | transitive |
| passkeys_platform_interface | 2.9.0 | transitive |
| path | 1.9.1 | transitive |
| path_provider_linux | 2.2.2 | transitive |
| path_provider_platform_interface | 2.1.3 | transitive |
| path_provider_windows | 2.3.0 | transitive |
| petitparser | 7.0.2 | transitive |
| platform | 3.1.6 | transitive |
| plugin_platform_interface | 2.1.8 | transitive |
| pointycastle | 4.0.0 | transitive |
| postgrest | 2.9.1 | transitive |
| process | 5.0.5 | transitive |
| realtime_client | 2.13.0 | transitive |
| sanitize_html | 2.2.0 | transitive |
| shared_preferences | 2.5.5 | direct main |
| shared_preferences_android | 2.4.27 | transitive |
| shared_preferences_foundation | 2.5.6 | transitive |
| shared_preferences_linux | 2.4.1 | transitive |
| shared_preferences_platform_interface | 2.4.2 | transitive |
| shared_preferences_web | 2.4.3 | transitive |
| shared_preferences_windows | 2.4.1 | transitive |
| sky_engine | 0.0.0 | transitive |
| source_span | 1.10.2 | transitive |
| stack_trace | 1.12.1 | transitive |
| storage_client | 2.8.0 | transitive |
| stream_channel | 2.1.4 | transitive |
| stream_transform | 2.1.1 | transitive |
| string_scanner | 1.4.1 | transitive |
| supabase | 2.16.1 | transitive |
| supabase_common | 0.1.2 | transitive |
| supabase_flutter | 2.17.2 | direct main |
| sync_http | 0.3.1 | transitive |
| term_glyph | 1.2.2 | transitive |
| test_api | 0.7.11 | transitive |
| typed_data | 1.4.0 | transitive |
| url_launcher | 6.3.2 | direct main |
| url_launcher_android | 6.3.32 | transitive |
| url_launcher_ios | 6.4.1 | transitive |
| url_launcher_linux | 3.2.2 | transitive |
| url_launcher_macos | 3.2.5 | transitive |
| url_launcher_platform_interface | 2.3.2 | transitive |
| url_launcher_web | 2.4.3 | transitive |
| url_launcher_windows | 3.1.5 | transitive |
| uuid | 4.6.0 | transitive |
| vector_math | 2.2.0 | transitive |
| vm_service | 15.2.0 | transitive |
| web | 1.1.1 | transitive |
| web_socket | 1.0.1 | transitive |
| web_socket_channel | 3.0.3 | transitive |
| webdriver | 3.1.0 | transitive |
| win32 | 6.4.0 | transitive |
| xdg_directories | 1.1.0 | transitive |
| xml | 7.0.1 | transitive |
| yet_another_json_isolate | 2.1.1 | transitive |
