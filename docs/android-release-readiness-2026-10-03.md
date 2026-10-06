# Android Release Readiness Audit — 2026-10-03

**Phase 2 ?? ?? ? 2026-10-06:** Flutter ?? ?? UI/client contract? **IMPLEMENTED_AND_TESTED_LOCAL**. Backend **IMPLEMENTED_LOCAL_NOT_DEPLOYED**, Production **NOT_DEPLOYED**. ?? ?? UI ??? ??? ????, ?????? ?? ??? ??? ???. [Flutter ?? ???](account-deletion-flutter-local-2026-10-06.md)

**최신 후속 상태 — 2026-10-05:** Release Maps PASS(사용자의 현재 명시적 확인), 원인 `MAPS_RELEASE_SHA_RESTRICTION` 해결. Account deletion backend는 **ACCOUNT_DELETION_BACKEND_LOCAL_PASS / IMPLEMENTED_LOCAL_NOT_DEPLOYED**. Production 배포·Flutter 삭제 UI·웹 요청 경로는 아직 없으며 Play readiness는 BLOCKED다. 아래 최초 감사/이전 smoke 실패 기록은 이력이다. [최신 backend 검증](account-deletion-backend-local-2026-10-05.md)

## 판정과 범위

**ANDROID_RELEASE_READINESS_BLOCKED**. 릴리스 서명 구조와 production runtime 방어는 마련되어 있으나 release OAuth, Maps restriction, 공개 개인정보처리방침, 계정 삭제 및 공개 UGC 정책 대응은 제출 gate를 통과하지 못했다. 이번 작업은 감사만 수행하며 수정·게시·외부 설정 변경은 하지 않는다.

**후속 compile fix: RELEASE_AAB_BUILD_BLOCKER_FIXED.** 같은 날짜의 후속 요청으로 release AAB 실패를 재현하고 정상 Flutter release tooling 재생성으로 해결했다. signed AAB, analyze, Flutter 355/355, debug APK 및 debug → release 전환 빌드가 PASS다. 앱 소스·Gradle·dependency·SDK·generated Java를 직접 수정하지 않았다. 아래 최초 감사 기록은 이력이며 **L–M 후속 검증**이 현재 build 상태다. 전체 Play 출시 readiness 판정은 다른 blocker 때문에 BLOCKED를 유지한다.

코드·로컬 설정·이번 빌드와 현재 공식 문서를 구분한다. Play Console / Google Cloud / Firebase / Supabase Dashboard의 실제 설정은 열람하지 않았으므로 **UNVERIFIED**다. 사용자 제공 production 행 수와 debug E2E 결과는 재검증하지 않았다. `PROJECT_STATUS.md`에는 오래된 설정 부재 기록이 있지만 현재 로컬에는 production 공개 설정이 존재한다.

## A. Repository

- branch: `nearby-store-sort`
- HEAD 및 로컬 remote-tracking `origin/nearby-store-sort`: `f152a65121f7488df89cd3324ca6401170b7a105` — 일치. fetch 미실행이므로 서버 최신 HEAD 확인과는 구분한다.
- 시작 시 `PROJECT_STATUS.md`, `README.md`, `integration_test/app_flow_test.dart`가 modified였고 다수 untracked 문서·데이터·스크립트가 있었다. 모두 보존한다.
- 근거: `AGENTS.md`, `pubspec.yaml`, `pubspec.lock`, `android/app/build.gradle.kts`, `android/settings.gradle.kts`, `android/gradle.properties`, main/debug/profile Manifest, `lib/main.dart`, `lib/core/config/app_config.dart` 및 아래 repository / migration 파일.
- Flutter 3.44.8 stable / Dart 3.12.2, AGP 9.0.1, Kotlin plugin declaration 2.3.20, Gradle wrapper 9.1.0, Java compilation target 17. compileSdk 36 / targetSdk 36 / minSdk 24 / NDK 28.2.13676358는 설치된 FlutterExtension에서 확인했다.

## B. Version

`pubspec.yaml` 기본값은 **1.0.0+1**. Gradle은 `flutter.versionName` / `flutter.versionCode`를 사용한다. 감사 시작 시 ignored `android/local.properties`의 생성된 값은 1.0.0 / **4016**이다. 이는 Flutter build/run의 `--build-number` override가 전달되는 경로이며 pubspec에 4016은 없다. 저장소 검색에서 4016을 만든 원래 명령 기록은 찾지 못했으므로 실행 이력 자체는 UNVERIFIED다.

첫 출시 version policy는 명문화되지 않았다. 4016 debug 설치값이 Play에 등록된 최고 versionCode라는 의미는 아니다. Play Console의 사용 이력 확인 후 첫 제출 번호와 이후 단조 증가 정책을 확정해야 한다. 이번 감사에서 버전을 임의 변경하지 않는다.

## C. Package ID / 브랜드

namespace / applicationId / Kotlin MainActivity package는 `com.burgermapkorea.app`. flavor 및 `applicationIdSuffix` 선언이 없어 debug와 release ID가 같다. debug와 다른 release 키로 같은 기기 앱을 업데이트하면 서명 충돌할 수 있으며 앱 삭제·데이터 초기화로 우회하지 않는다.

main Manifest label은 `버거맵 코리아`, MaterialApp title은 `Burger Map Korea`. legacy vector(v21), adaptive(v26), monochrome(v33) launcher icon 자원이 있다. Play listing 이름·512px 아이콘·feature graphic·스크린샷·지원 연락처의 등록/승인은 UNVERIFIED다.

## D. Release signing

**READY**. 후속 AAB 서명 검증 및 configured release certificate 일치 PASS. Play 등록은 UNVERIFIED다.

로컬 필수 속성 및 keystore 존재, 인증서 읽기: 확인. release 인증서는 로컬 Android debug 인증서와 다르다. `android/key.properties`의 `storeFile`, `storePassword`, `keyAlias`, `keyPassword`는 비어 있거나 REPLACE placeholder가 아니다. 값·alias·개인 keystore 경로·인증서 지문은 기록하지 않는다.

`releaseBuildRequested`일 때만 release signingConfig를 만들고 필수 파일·속성·keystore 누락 시 GradleException으로 차단한다. debug signing fallback은 없다. 상대 storeFile은 app Gradle project 기준으로 해석한다. `.gitignore`는 key.properties, *.jks, *.keystore 등을 제외한다. `git ls-files`에서는 `android/key.properties.example`만 확인되었다. 실제 서명 비밀번호의 유효성 및 최종 서명은 빌드 결과로 판단하며 Play App Signing 등록·키 백업·접근 통제는 UNVERIFIED다.

## E–F. Release SHA / OAuth / Google Sign-In

- 기존 release 키에서 SHA-1 / SHA-256 산출 가능. debug 인증서와 구분 완료. Cloud OAuth / Firebase 등록 여부는 UNVERIFIED.
- `google_sign_in` 7.2.0: `NativeGoogleTokenProvider`가 `GoogleSignIn.initialize(serverClientId: ...)`, email/profile scope 계정 선택을 실행한다. ID token과 access token을 `SupabaseAuthRepository.signInWithIdToken(provider: google)`에 전달하고 세션 생성까지 확인한다.
- `lib/main.dart`는 `GOOGLE_SIGN_IN_ENABLED=true`, 비어 있지 않은 `GOOGLE_WEB_CLIENT_ID`, Android 조건을 모두 충족할 때 버튼을 활성화한다. Dart compile-time define이며 `.env` 자동 로딩은 없다.
- 현재 `.env` 및 프로세스 환경에는 두 Google 로그인 define이 없다. 이번 audit AAB는 Google 버튼이 비활성화되는 구성이다. debug E2E 성공을 release 로그인 PASS로 승격하지 않는다.
- Web OAuth client ID는 공개 identifier이며 앱에 필요하다. OAuth client secret은 Supabase provider 서버 설정 전용이며 앱에 넣지 않는다. provider 활성화 / audience 허용 목록 / secret 상태는 원격 UNVERIFIED.
- Play 배포본은 upload certificate와 다른 Play app-signing certificate로 서명될 수 있다. 로컬 release 인증서 등록만으로 Play 로그인 검증을 대체할 수 없다. package + Play app-signing SHA-1을 Android OAuth에 확인하고 SHA-256이 필요한 Google/Firebase 계약도 별도로 대조한다. [Android signing 문서](https://developer.android.com/studio/publish/app-signing), [Supabase Google 문서](https://supabase.com/docs/guides/auth/social-login/auth-google).

## G. Google Maps

Gradle 주입 우선순위: Gradle property → OS `GOOGLE_MAPS_API_KEY` → Base64 dart-defines decode → empty. main Manifest `${GOOGLE_MAPS_API_KEY}`로 native SDK에 전달한다. Dart `AppConfig`도 같은 define을 사용한다. Gradle/OS에만 값을 넣고 Dart define을 빼면 native 값과 UI의 key 존재 판단이 어긋날 수 있다.

현재 `.env`에 값 존재, client source / Manifest / Gradle 파일에서 실제 Maps key literal은 미검출. local.properties는 이 Gradle 로직에서 Maps key source가 아니다. Android restriction의 package `com.burgermapkorea.app` + 배포 서명 SHA-1, Maps SDK API restriction, API 활성화·billing·quota는 Cloud에서 UNVERIFIED. debug 성공은 release 또는 Play certificate restriction 확인을 대신하지 않는다. [Maps 설정 문서](https://developers.google.com/maps/documentation/android-sdk/config).

## H. Supabase release configuration

`SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY`는 `String.fromEnvironment` Dart define이며 소스 hardcode나 generated credential Dart 파일이 아니다. `.env`는 Flutter가 자동 읽지 않으며 빌드 실행자가 명시적으로 필요한 공개 값만 전달해야 한다. 이번 확인에서 URL은 `eoiwfprghyyguthdtayx` production project와 일치하고 key 형식은 **publishable**이다. 서비스 role·DB password·OAuth secret은 전달하지 않았다.

release에서는 APP_ENV / STORE_DATA_MODE 입력과 관계없이 production / supabase로 강제된다. 잘못된 URL·없는 key·privileged key는 config validation에서 거부되고 pilot/staging fallback은 없다. 단, URL validator는 특정 production project host allowlist를 강제하지 않으므로 잘못된 다른 HTTPS project URL을 주입하지 않도록 release config 검토가 필요하다.

공개 매장 조회 조건은 `verification_status=verified AND is_active=true`. `Supabase.initialize(debug:false)`로 하나의 client를 auth / stores / menus / reviews가 공유한다. 원격 데이터·RLS·Auth provider를 이번 감사에서 변경하거나 새로 검증하지 않았다.

## I. Source secret scan

client Dart / Android source XML / Gradle Kotlin 60개 파일을 검사했다. 기존 verifier의 sb_secret/private-key/non-anon JWT 실제값 패턴 **0**, 공개 config literal **0**, GOCSPX OAuth secret 실제값 패턴 **0**, password-bearing postgres URI **0**. `service_role` 문구가 validator에서 사용되는 것은 실제 credential 누출과 구분한다.

정적 패턴 검사는 임의 형식의 모든 secret을 부재 증명하지 않는다. `.env` 전체를 산출물에 넣지 않고 공개 빌드 설정 allowlist만 사용했다. 빌드 wrapper가 Base64 dart-defines를 echo하여 도구 출력에 공개 설정의 인코딩 표현이 포함되었다. 이를 값 비노출 기준 위반으로 기록하며 해당 값을 재인용하지 않는다. 보존할 로그에서는 dart-defines 전체를 제거한다. 서버 credential 전달·검출은 없으며 공개 Maps key도 제한 등록 확인이 필요하다.

## J. Android permissions / network / backup

main: INTERNET, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION. debug/profile: INTERNET 추가 선언만 있다. 위치는 foreground 기능을 선택할 때만 사용하며 FINE+COARSE를 함께 선언한다. 대략 위치에 대해 낮은 accuracy 요청·정밀 캐시 우회 차단·accuracy 안내가 있다.

| 권한 | 분류 | 판단 |
|---|---|---|
| INTERNET | REQUIRED | Supabase / Maps / 인증 |
| FINE + COARSE | OPTIONAL | 사용자 선택 current location / nearby sorting, 기본 탐색에는 불필요 |
| ACCESS_NETWORK_STATE | merged Manifest 확인 필요 | SDK가 사용하는 일반 네트워크 상태 접근 |
| background location | UNNECESSARY / source 미선언 | 추가하지 않음 |
| storage / camera / photos / notifications / advertising ID | UNNECESSARY / app source 미선언 | 현재 업로드·광고·알림 기능 없음; merged 결과와 구분 |

main Manifest에 cleartext 허용·custom networkSecurityConfig·backup exclusion 정책이 없다. Supabase URL은 HTTPS로 검증한다. Android 기본 backup 동작과 로컬 auth session / favorites 복원·제외 정책은 별도 확인 대상이며 안전한 암호화 저장이라고 주장하지 않는다. Geolocator dependency에는 location foreground service가 선언되어 있으나 앱에서 background stream/service 사용 경로는 찾지 못했다.

## K. Privacy / Data Safety 초기 inventory

| 데이터 | 실제 처리·보관 경로 | 공개/목적·남은 확인 |
|---|---|---|
| 이메일 / Google 계정 ID·profile scope | Google 인증 → Supabase Auth. Magic Link는 이메일을 서버로 전송하고 계정을 생성할 수 있음 | 인증·계정 관리, provider metadata 전체 필드는 원격 미확인 |
| ID/access token, Supabase session | 메모리 토큰 교환. Supabase Flutter 2.17.2 기본 persistSession=true, SharedPreferencesLocalStorage로 session JSON 저장 | 로컬에 auth token도 보관됨. favorites만 저장된다고 요약하면 불완전 |
| 사용자 UUID / nickname | profiles insert/read, 작성자 nickname 조회 | 공개 리뷰 작성자 표시, nickname/id 공개 조건은 migration 확인 |
| 별점 / 선택 본문 | reviews store_id/rating/content, DB user_id default, timestamps | 공개 UGC, 본인 수정·삭제; hidden/moderation 기록도 서버 보관 |
| 리뷰 신고 reason/detail / 신고자 ID | review_reports insert, DB 신고자 default·timestamps | 운영자 검수, 일반 사용자 신고 목록 공개 경로 없음 |
| favorite store UUID 목록 | SharedPreferencesAsync `favorite_store_ids_v1` | 로컬 즐겨찾기, 앱 Supabase 전송 없음; OS backup 고려 |
| 현재 정확/대략 위치 / accuracy / timestamp | location controller memory, 로컬 distance sorting, Maps 위치 layer·카메라 API | 앱 영구 저장·로그·Supabase payload 경로 미검출. Google SDK 사용까지 전송 없음으로 단정하지 않음 |
| Maps request metadata / IP / SDK pseudonymous ID / SDK crash metrics / map interactions | Google Maps SDK | SDK 별도 고지 포함, 최종 dependency version과 실제 호출 기준 분류 |

schema 근거: `supabase/migrations/20260922050439_auth_menu_reviews.sql`, optional content migration, `SupabaseAuthRepository`, `SupabaseReviewRepository`; 로컬 session 근거: 설치된 supabase_flutter 2.17.2 `flutter_go_true_client_options.dart`, `supabase.dart`, `local_storage.dart`.

app dependencies / client source에는 전용 analytics·ads·Sentry·Firebase Crashlytics SDK 사용을 찾지 못했다. 그러나 Google Maps 자체 SDK telemetry/crash metrics가 있으므로 “telemetry 없음”으로 신고하면 안 된다. resolved `google_maps_flutter_android` 2.19.12의 Android build dependency는 Maps SDK **20.0.0**이다. [Maps Data Safety 안내](https://developers.google.com/maps/documentation/android-sdk/play-data-disclosure)는 최신 SDK 기준이며 적용 버전과 대조해야 한다. Supabase 및 Google 서버 로그·보존 기간·처리자·국외 이전·삭제 SLA는 로컬 코드로 확인할 수 없다. 이 표는 최종 Data Safety 답안이나 법률 자문이 아니다.

`SUPPORT_URL`, `PRIVACY_POLICY_URL`, `OPERATOR_NAME`은 compile-time define이며 기본 empty. 이번 로컬 환경에서는 모두 부재하여 미준비 안내를 표시한다. 공개 정책·지원 정보·SDK 고지를 준비해야 한다. [Google Play User Data 정책](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en).

계정 생성 기능이 있지만 계정 삭제 요청 UI/웹 경로는 source에서 찾지 못했다. logout·review DELETE·DB CASCADE는 계정 삭제 요청 경로가 아니다. [계정 삭제 정책](https://support.google.com/googleplay/android-developer/answer/13327111)에 따라 앱 내 경로와 외부 웹 요청 경로를 준비해야 한다. 공개 리뷰 신고·운영 hide는 구현되어 있지만 약관 동의 gate, 사용자 신고/차단 기능은 미검출이다. 공개 UGC를 제공하므로 [UGC 정책](https://support.google.com/googleplay/android-developer/answer/9876937?hl=en)에 비춰 제출 전 보완 필요로 판단한다. 이번 감사에서는 구현하지 않는다.

## L–M. Release build / artifact inspection — 최초 감사 이력

**Release AAB build: FAIL. Current AAB artifact inspection: NOT RUN.** 기존 `build/app/outputs/bundle/release/app-release.aab`는 2026-08-24 생성 / 51,450,474 bytes로 현재 HEAD 증거가 아니며, 빌드 전 별도 복사본을 보존했다. 감사 산출물은 ignored `build/android-release-audit-20261003/`에 정리했다.

첫 제한 실행환경 시도는 진행되지 않아 해당 cmd 프로세스를 종료했다. 정상 권한 재시도는 Gradle 516.5초 후 exit 1로 종료했다. 정확한 blocker:

```text
Execution failed for task ':app:compileReleaseJavaWithJavac'.
android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java:44:
error: package dev.flutter.plugins.integration_test does not exist
new dev.flutter.plugins.integration_test.IntegrationTestPlugin()
```

registrant는 ignored generated file이다. `integration_test`는 pubspec dev_dependency이고 현재 generated plugin metadata에도 dev_dependency=true로 기록되어 있다. generated registrant와 release classpath가 불일치한다. `--no-pub` 상태의 generated 파일/metadata 재생성 문제인지 Flutter toolchain regression인지는 아직 분리 검증하지 않았으며, 새 원인으로 확정하지 않는다. 감사 요청에 따라 pub get/clean/registrant 수동 수정/의존성 변경으로 blocker를 수정하지 않았다. 후속 작업에서 기존 generated 상태 보존 후 정상 pub/plugin 재생성 경로로 재현하고, 계속 실패하면 toolchain의 release dev-plugin 제외 동작을 조사해야 한다.

Dart AOT 및 icon tree shaking은 완료했지만 bundle/signing까지 완료되지 않았다. 따라서 signing READY는 기존 키·인증서·로컬 구성의 준비 상태이며 keyPassword를 이용한 최종 artifact 서명 성공은 UNVERIFIED다. 신규 AAB path/size/version/package는 확인 불가. 기존 AAB의 시간·크기는 그대로였고 그 AAB로 현재 secret/staging 검사 PASS를 주장하지 않는다. 확인한 release merged Manifest도 8월 생성 파일이므로 현재 permission/version/debuggable 검증 증거에서 제외한다.

보존 파일: `build/android-release-audit-20261003/preexisting-app-release.aab`, `build/android-release-audit-20261003/build-result-redacted.txt`. 로그에서 Base64 `-Pdart-defines` 전체를 제거했다. OAuth secret / DB password / service_role / endpoints / localhost / staging URLs / local paths / staging UUID의 **현재 AAB 검사**는 산출물 부재로 모두 NOT RUN이다. verifier는 후속 최종 AAB에 `--bundle <new-aab> --staging-json assets/dev/yongsan_burger_stores_staging.json`으로 실행하고 추가 문자열·인증서·manifest 검사를 함께 수행한다.

실제 명령 계약(값 미기재):

```text
flutter build appbundle --release --no-pub
  --dart-define=APP_ENV=production
  --dart-define=STORE_DATA_MODE=supabase
  --dart-define=SUPABASE_URL=<existing production public URL>
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<existing publishable key>
  --dart-define=GOOGLE_MAPS_API_KEY=<existing Android Maps key>
```

실행자는 `.env`에서 위 세 공개 설정만 메모리로 읽어 전달했다. GOOGLE_SIGN_IN_ENABLED / GOOGLE_WEB_CLIENT_ID 및 운영 링크는 없으므로 이는 **감사용 빌드**다. 향후 최종 release build는 로그인·정책·지원 define까지 포함하고 공개 설정을 검증한 별도 빌드 파일/파이프라인을 통해 재현해야 한다.

### L–M 후속 검증 — release compile blocker 해결

**Release AAB: FAIL → PASS. IntegrationTestPlugin blocker: RESOLVED.**

현재 HEAD에서 기존 공개 설정과 서명키로 `flutter build appbundle --release --no-pub` 오류를 독립 재현했다: **211.8초 / exit 1**, 같은 `:app:compileReleaseJavaWithJavac` 및 GeneratedPluginRegistrant.java:44의 missing integration_test package 오류.

Root cause 분류: **B. stale generated registration state + E. Flutter tooling/generated state**. dependency metadata 자체가 잘못된 것이 아니라, 이전 debug용 공유 registrant를 release용으로 재생성하지 않은 실행 경로가 원인이다.

- pubspec `dev_dependencies`, lockfile `direct dev`, package graph `devDependencies`, plugin metadata `dev_dependency=true`가 모두 일치한다. SDK integration_test는 정상 Android package/pluginClass를 선언한다.
- 설치 Flutter 3.44.8 `flutter_command.dart` 1957–2010행: `--no-pub`이면 shouldRunPub=false여서 `regeneratePlatformSpecificToolingIfApplicable`가 즉시 return한다.
- `flutter_plugins.dart` 1300–1332행: releaseMode=true이면 dev 플러그인을 필터링한 뒤 Android registrant를 생성하고, debug는 포함한다.
- `PluginHandler.kt` 109–117행: dev plugin은 release API dependency에 추가하지 않는다. classpath 제외는 정상이며 stale Java 참조가 불일치다.
- 실제 Gradle `releaseCompileClasspath` tree에는 integration_test가 **없고**, `debugCompileClasspath` tree에는 **있다**. 전체 Gradle 프로젝트 configure 메시지에 등장하는 것과 classpath dependency는 구분했다.
- 앱 custom sourceSet은 debug staging assets만 추가한다. Java/test sourceSet leakage나 release test dependency 강제 포함은 없다. A dependency placement / C custom sourceSet leakage / D repository Gradle customization 원인은 배제한다.

정확히 어떤 과거 명령이 최초 debug registrant를 생성했는지는 확정하지 않는다. 다만 이번 debug 빌드에서 같은 테스트 참조가 정상 재생성되는 것을 직접 확인했다. SDK 주석의 [Flutter tooling 이슈](https://github.com/flutter/flutter/issues/162649)는 mode별 생성의 배경이며, 이 저장소 원인은 현재 SDK 코드·재현·classpath로 판정했다.

**최소 조치:** 같은 공개 define·기존 signing 설정에서 `--no-pub`만 제거했다. Flutter가 정상 dependency 확인과 release platform tooling 재생성을 수행하여 integration_test 참조를 제거했다. 첫 성공 **173.8초 / exit 0**, debug 빌드 이후 동일 정상 release 명령 재실행도 **21.1초 / exit 0**이다. `flutter clean`·cache 삭제는 불필요하여 실행하지 않았다. SDK/generated 파일 수동 수정·stub·release test dependency 추가·테스트 삭제·dependency 변경은 없다.

재발 방지 명령 계약은 다음과 같다. `--pub`는 기본값이므로 생략 가능하며 mode 전환 때 `--no-pub`로 재생성을 생략하지 않는다. standalone `flutter pub get`은 release mode 필터링을 대신하지 않는다.

```text
flutter build appbundle --release --pub
  --dart-define=APP_ENV=production
  --dart-define=STORE_DATA_MODE=supabase
  --dart-define=SUPABASE_URL=<existing production public URL>
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<existing publishable key>
  --dart-define=GOOGLE_MAPS_API_KEY=<existing Android Maps key>
```

새 AAB Manifest protobuf에서 package **com.burgermapkorea.app**, versionName **1.0.0**, versionCode **1**을 직접 확인했다. build-number override 없이 pubspec 값을 사용한다. path는 `build/app/outputs/bundle/release/app-release.aab`, 첫 성공 size는 **53,987,559 bytes**. 최종 산출물 수치는 아래 최종 검사 기록으로 확인한다.

서명: jarsigner `jar verified` + AAB signer SHA-256과 기존 configured release certificate SHA-256 비교 **true**. 비밀번호·alias·개인 key 경로·지문은 공개하지 않는다. self-signed / PKIX chain / timestamp 부재 warning은 있으나 서명 무결성과 기존 certificate 일치는 통과했다. Play 등록까지 검증한 것은 아니다.

Artifact 검사: verifier safe=true, entries=157, public config hits=19, secretPatternHits=0, forbidden staging entry=0, manifest staging=0, staging UUID=0 / 24 checked. DEX IntegrationTestPlugin / dev.flutter.plugins.integration_test=0, integration_test ZIP entry=0. DEX flutter/testing 및 dart.vm.service 표식=0. GOCSPX OAuth secret actual value / password-bearing postgres URI=0. production Supabase host 존재 확인. 공개 client identifier를 비밀 누출로 오인하지 않았다.

native engine에는 loopback·VM Service 관련 일반 문자열이 있고 libapp AOT에는 bare localhost와 로컬 Dart 파일 경로가 남아 있으며 debug symbols metadata에도 같은 문자열이 있다. 실제 debug endpoint 설정·서비스 실행 증거와 구분한다. 앱 소스에서 localhost/loopback 설정 경로는 미검출이다. “debug 문자열·로컬 경로 전혀 없음”으로 주장하지 않으며 제거 필요성은 다른 readiness 범위로 남긴다. 임의 형식 모든 secret 부재를 증명하는 검사도 아니다.

새 AAB permissions: INTERNET, FINE, COARSE, ACCESS_NETWORK_STATE, USE_BIOMETRIC, USE_FINGERPRINT, 앱 DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION. debuggable 속성 미선언. biometric/fingerprint는 dependency merge 결과이며 J의 app source 선언과 구분한다. 필요성·제거 정책은 별도 검토이고 이번 task에서 바꾸지 않았다.

회귀 검증:

- `flutter analyze --no-pub`: **PASS**, no issues, 142.6초.
- `flutter test --no-pub --reporter expanded`: **355/355 PASS**, 이번 실제 실행, 약 92초.
- `flutter build apk --debug` + 같은 공개 define: **PASS**, 71.4초. debug registrant와 APK DEX에 IntegrationTestPlugin 존재, SDK package resolution·dev dependency 유지.
- debug → release 재빌드: **PASS**, 21.1초, release registrant가 다시 test plugin을 제외함.
- Dart source 변경 없음으로 dart format은 해당 없음. 사용자 파일을 format하지 않았다.
- 기기 E2E·Google login E2E·production review/report write는 실행하지 않았다.

최종 재빌드 AAB 검사도 동일 결과다: **53,987,559 bytes**, SHA-256 `3529d295c8c51b6de137219c84dee44ed011c27bc87258b9cc19c3918e0d3ccb`, package/version `com.burgermapkorea.app` / `1.0.0+1`, verifier safe=true, release certificate 일치=true. 최종 release registrant test 참조=0.

Git 변경은 기존 uncommitted audit 문서 업데이트뿐이다. 의도적으로 업데이트한 이 문서를 제외한 기존 사용자 파일 **48개 hash 동일**, 예상 밖 변경=0, 기존 status 유지. 앱 코드 변경 없이 운영 명령/정상 generated state를 교정했다. 로그·초기 사용자 파일 hash snapshot·graph·artifact inspection은 ignored `build/release-blocker-fix-20261003/`에 보존했다. raw/encoded define 비노출 검사 및 문서 whitespace 검사 통과. proposed commit message: `docs: record release plugin regeneration fix and signed AAB validation`.

## N–O. Debug vs release / R8

| 요소 | release 차이·위험 |
|---|---|
| signing / package | 동일 package + 다른 인증서, debug 업데이트 충돌 가능 |
| OAuth / Maps | debug SHA 통과와 release / Play signing SHA 등록은 별개 |
| environment | release production/supabase 강제; .env 자동 주입 안 됨; Google login define 기본 disabled |
| assets | Gradle Sync가 staging JSON을 debug assets에만 주입. pubspec assets 선언 없음. final AAB UUID 검사 필요 |
| logging | app diagnostic은 development에서만, Supabase debug=false. SDK 로그까지 0으로 단정하지 않음 |
| network / permissions | main Manifest 공유; merged dependencies 및 release cleartext·debuggable 상태는 artifact로 확인 |
| minify/shrink | app Gradle에 명시 flag는 없지만 설치 FlutterPlugin은 기본 shouldShrinkResources=true로 release R8/minify + resource shrinking 적용 |

Flutter는 default optimized ProGuard와 flutter_proguard_rules.pro를 추가한다. 프로젝트 `android/app/proguard-rules.pro`는 없다. Maps / google_sign_in은 native SDK와 consumer rules를 사용하고 Supabase Dart 로직은 JVM reflection 대상이 아니다. 실제 R8 build warning 및 로그인·Maps runtime smoke 없이 무문제 판정은 하지 않는다. 불필요한 keep rule은 추가하지 않았다.

## P. Device release smoke

**NOT RUN**. `adb devices`에 연결 기기 없음. AAB 자체는 직접 adb install 할 수 없다. 향후 Play internal testing 설치본을 우선 사용하고 필요 시 동일 설정의 release APK 또는 bundletool APK set을 별도 생성한다.

1. 서명 충돌 시 기존 debug 앱을 삭제하거나 데이터 초기화하지 말고 별도 테스트 기기 사용.
2. cold launch / guest map tiles / public store 목록 / 상세 / menu / review read.
3. Google 계정 선택 → token exchange → 실제 Supabase session → nickname/지도 복귀; 취소·오프라인 후 복구.
4. 위치 거부 / approximate / precise, nearby sorting, background 이후 위치 제거, favorites 유지.
5. 정책·지원·계정 삭제 요청 링크 및 UGC 안전 장치 확인.
6. Play app-signing 설치본으로 OAuth·Maps 재확인. production test review/report 작성은 이 감사의 smoke 범위에 포함하지 않는다.

## Q. Play Store blockers

| 심각도 | 항목 | 근거 / 완료 조건 |
|---|---|---|
| CRITICAL | 실제 서버 비밀 누출 | 현재 검사에서 확인된 실제 누출 없음. 발견 시 즉시 제출 차단 |
| HIGH | release Google login build defines 없음 / OAuth 등록·runtime UNVERIFIED | public Web client ID·활성화 설정, release 및 Play signing 등록 후 설치본 검증 |
| HIGH | Maps restriction / 실제 release tiles UNVERIFIED | package + 배포 SHA-1·API restriction 대조 및 설치본 검증 |
| HIGH | 개인정보처리방침 / Data Safety / 지원 정보 미준비 | 실제 공개 링크, SDK·Auth session 포함 inventory, Play form·운영자 정보 검증 |
| HIGH | 계정 삭제 요청 경로 없음 | 앱 내 + 웹 요청 경로, 인증·삭제·보관 정책·처리 절차 검증 |
| HIGH | 공개 UGC 약관 동의 / 사용자 신고·차단 gap | 현재 review report/moderation과 별도로 정책 대응 검증 |
| HIGH | 최종 후보 AAB / Play App Signing / 배포 smoke gate | 감사용 AAB와 구분, signing·scan·Play internal test 통과 |
| RESOLVED | release Java compile 실패 | --no-pub를 제거한 정상 release tooling 재생성; signed AAB 및 mode 전환 회귀 PASS |
| MEDIUM | version policy / Play used versionCode UNVERIFIED | 첫 출시 이름·번호와 증가 규칙 확정 |
| MEDIUM | listing assets / review access / content rating / 대상 연령·개발자 계정 조건 UNVERIFIED | Console 요구 항목 및 지원 연락처 등록 |
| MEDIUM | 16KB compatibility / backup 및 auth session 저장 정책 | native ELF·bundle alignment·16KB 실행 및 backup 처리 검증 |
| LOW | 기본 앱 정보의 용산 우선 안내·문서 최신성 | 실제 공개 서비스 범위와 표현 대조 |

targetSdk 36은 현재 신규 앱 제출의 API 36 요구에 부합한다. 최종 artifact에서도 확인해야 한다. [공식 target API 정책](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-EN). native library가 있으므로 [16KB page size 요구](https://developer.android.com/guide/practices/page-sizes)도 별도 제출 gate로 확인한다. 서명 로컬 준비와 Play Console 등록 완료는 다르다.

## R–S. Production / Git / tests

INSERT=0, UPDATE=0, DELETE=0, DDL=0, migration=0, RLS=0, Auth config=0. Google Cloud 설정 변경=0. remote production query도 미실행. commit / push / PR / merge **NO**. 키 생성·삭제·교체 없음. source / pubspec / Manifest / Gradle 변경 없음.

최초 감사에서는 사용자 제공 analyze PASS 및 Flutter 355/355를 재실행하지 않았다. 후속 compile fix에서는 요청에 따라 analyze 및 전체 **355/355 PASS**를 새로 확인했다. 기존 dirty/untracked 파일을 task 변경으로 포함하지 않는다. audit 문서 외에는 ignored build 산출물만 만든다. 문서 trailing whitespace 검사 0. 최초 전체 `git diff --check`는 기존 사용자 변경 `integration_test/app_flow_test.dart` 93/96행 trailing whitespace를 지적했으며 해당 파일의 hash/state를 그대로 보존했다.

## T. Exact next actions

1. 기존 키 백업·접근 통제·Play App Signing 계획 확인. 키를 새로 만들거나 교체하지 않고 upload / Play signing certificate 역할 확정.
2. Google Cloud에서 production package + local release 및 Play signing fingerprint와 Android OAuth / Maps restrictions를 대조. 기존 Web client ID와 Supabase provider audience 설정을 확인하고 secret은 서버에만 둠.
3. 실제 public build settings에 Google sign-in 및 privacy/support/operator define을 추가하는 후속 작업 승인·수행. `.env` 전체를 build define으로 넣지 않음.
4. 공개 정책·계정 삭제 요청·UGC 약관 동의/신고/차단·운영 절차를 제출 전 보완하는 별도 범위를 확정. 이번 감사에서 변경하지 않음.
5. compile blocker는 후속 작업에서 해결 완료. Play 이력과 version policy 확정 → 로그인·운영 설정까지 갖춘 최종 signed production AAB → 추가 artifact/16KB 검사 → Play internal test release smoke.
6. Data Safety / account deletion URL / content rating / listing assets / contact / app access / 개발자 계정 조건 확인 후 제출 여부 판정.

## U. Verdict

**ANDROID_RELEASE_READINESS_BLOCKED**. production runtime 방어와 기존 release 키는 확인됐으나 로그인·정책·배포 검증이 남아 PASS가 아니다. debug E2E 및 오래된 AAB는 이 gate를 대신하지 않는다.

후속 요청 범위 판정: **RELEASE_AAB_BUILD_BLOCKER_FIXED**. 정상 release build와 Flutter/debug 회귀는 PASS이며 전체 Play readiness와는 구분한다.

## Google Sign-In / Maps credential audit — 2026-10-05

### 범위와 현재 판정

**RELEASE_GOOGLE_SERVICES_CONFIG_REQUIRED — 확인된 로컬 OAuth build 설정 누락 기준.** Google Cloud의 release 등록이 없다고 확정한 것은 아니다. 외부 Android OAuth / Web OAuth / Maps registration은 **UNVERIFIED**다. 등록 자체의 외부 변경이 필요한지는 Console 증거를 확보한 뒤 결정한다. 전체 Android readiness는 BLOCKED, 이전 release AAB PASS와 compile blocker RESOLVED는 유지한다.

사용자는 기존 Cloud OAuth 설정 확인을 지시하고 ID 추측·새 credential 생성을 금지했다. Computer Use inventory는 apps=[] / browsers=[]였고 Chrome Console 열기는 `Browser is not available: chrome`로 실패했다. 따라서 기존 로그인된 Console 화면에 접근할 수 없었으며 UI 외부 확인은 이 접근 blocker에서 중단했다. API key·OAuth credential을 새로 만들거나 변경하지 않았다.

### A–B. Repository / signing identity

branch `nearby-store-sort`, HEAD `f152a65121f7488df89cd3324ca6401170b7a105` 일치. package는 `com.burgermapkorea.app`이고 signing 설정·기존 keystore를 변경하지 않았다. 기존 키에서 인증서를 읽어 debug 인증서와 **다름**을 다시 확인했다. 아래 지문은 OAuth / Maps 등록용 공개 인증서 식별자이며 keystore secret이 아니다.

| release certificate identifier | 실제 값 |
|---|---|
| SHA-1 | `3D:F2:42:D9:BE:EE:AC:42:97:3F:B5:1B:23:13:49:C2:54:C2:8F:4C` |
| SHA-256 | `87:65:4D:71:D0:27:32:45:D2:02:6F:55:7E:23:B4:BD:57:D8:F5:16:9B:1F:7F:C0:4F:C1:6C:B2:CD:A7:40:B2` |

로컬 직접 설치 APK의 signer와 Play 배포 APK의 app-signing certificate는 다를 수 있다. upload key 지문을 Play signer로 추정하지 않으며, Play Console 인증서는 아직 UNVERIFIED다.

### C–G. Sign-In 구현과 OAuth contract

`google_sign_in` **7.2.0**, resolved `google_sign_in_android` **7.2.17**. 실제 경로는 `lib/main.dart` → `NativeGoogleTokenProvider` → `SupabaseAuthRepository`다.

`GOOGLE_SIGN_IN_ENABLED=true` + nonempty `GOOGLE_WEB_CLIENT_ID` + Android 조건을 만족해야 Google 버튼이 활성화된다. `GoogleSignIn.initialize(serverClientId: googleWebClientId)`, 계정 선택, email/profile authorization으로 ID/access token을 얻고 Supabase `signInWithIdToken(provider: Google, idToken, accessToken)`에 전달하여 실제 session을 확인한다. 실패를 로그인 성공으로 바꾸지 않는다.

Android OAuth client는 **package + 실제 설치 signer SHA-1**로 앱 신원을 등록한다. Android client ID를 Dart serverClientId에 넣는 방식이 아니다. Web application OAuth client의 ID가 Dart serverClientId / `GOOGLE_WEB_CLIENT_ID`이며 ID token audience와 Supabase provider 허용 ID 계약을 맞춰야 한다. Web client secret은 Supabase/server 전용이고 APK·Dart define·로컬 public build 파일에 넣지 않는다. [Flutter Android integration 문서](https://pub.dev/packages/google_sign_in_android#integration), [Supabase Google 문서](https://supabase.com/docs/guides/auth/social-login/auth-google).

실제 프로젝트에는 `android/app/google-services.json`과 Google Services Gradle plugin이 없고 native provider는 nonempty serverClientId를 요구한다. repo-specific debug fallback이나 Android client ID 자동 대체 경로는 없다. `.env`는 Flutter가 자동 주입하지 않는다.

| 항목 | 현재 evidence / 판정 |
|---|---|
| 로컬 Google build config | `.env`, process/user/machine environment에 두 define 부재; repo safe text 검색에서도 실제 OAuth client ID 미검출. **RELEASE_OAUTH_CONFIG_INCOMPLETE** |
| Android OAuth client | release package/SHA-1은 확인, Console 등록 **UNVERIFIED_EXTERNAL_REGISTRATION** |
| Web OAuth client | 기존 client ID의 로컬 값·Console client type 및 같은 project 여부 **UNVERIFIED**. 사용자도 별도 저장 경로를 모른다고 답함 |
| Supabase Google provider | production `/auth/v1/settings` GET **HTTP 200**, external.google=true. **활성화만 확인** |
| Supabase Web ID / secret 연결 | 공개 settings는 ID/secret 계약을 노출하지 않아 **UNVERIFIED**. 로그인 token exchange를 실행하지 않음 |

provider 활성화는 release native 로그인 성공의 증거가 아니다. Web ID audience·기존 secret의 연결·Google Auth Platform Audience/Data Access·Android signing 등록이 별도로 필요하다. native token 교환은 browser redirect OAuth 경로와 구분하며 불필요한 redirect 변경을 제안하지 않는다.

### H. Public build config / secrets

| 이름 | 분류 / 주입 |
|---|---|
| APP_ENV=production / STORE_DATA_MODE=supabase | PUBLIC BUILD CONFIG, Dart define; release runtime도 production/supabase 강제 |
| GOOGLE_SIGN_IN_ENABLED=true | PUBLIC BUILD CONFIG, bool Dart define; 현재 누락 |
| GOOGLE_WEB_CLIENT_ID | PUBLIC BUILD CONFIG, **기존 Web client ID** Dart define; 현재 누락 |
| GOOGLE_MAPS_API_KEY | PUBLIC MOBILE CLIENT CONFIG, Dart define + native Manifest placeholder. 값 비공개; 반드시 Android/API restriction 검증 |
| SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY | PUBLIC CLIENT CONFIG, 기존 production 값 Dart define. 값 비공개 |
| OAuth client secret / service_role / sb_secret / DB password / keystore passwords | SECRET, 앱 artifact·public build config에 전달 금지 |

Gradle 값만 넣으면 Dart의 key 존재 판단과 다를 수 있으므로 기존 Maps Dart define/native Manifest 일치를 확인한다. shell의 환경변수 이름과 Dart compile-time define 전달은 동일한 것이 아니다. 최종 로그인 smoke 후보 명령은 다음 계약이며 실제 ID를 추측하지 않는다:

```text
flutter build apk --release --pub
  --dart-define=APP_ENV=production
  --dart-define=STORE_DATA_MODE=supabase
  --dart-define=GOOGLE_SIGN_IN_ENABLED=true
  --dart-define=GOOGLE_WEB_CLIENT_ID=<confirmed existing Web application client ID>
  --dart-define=GOOGLE_MAPS_API_KEY=<existing Android Maps key>
  --dart-define=SUPABASE_URL=<existing production URL>
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<existing publishable key>
```

`--no-pub`는 사용하지 않는다. 실제 감사 APK는 기존 확인된 Supabase·Maps 공개 define만 사용하며 Google 두 define은 없는 상태를 그대로 유지한다. 따라서 Google 버튼이 disabled되는 기술 검증 산출물이고 로그인 smoke 준비 완료로 판정하지 않는다.

### I–J. Maps injection / restriction

`android/app/build.gradle.kts`는 Gradle property → OS GOOGLE_MAPS_API_KEY → Dart defines Base64 decode → empty 순서로 key를 선택하고 manifestPlaceholders에 넣는다. main Manifest의 `com.google.android.geo.API_KEY`가 이를 읽는다. 이 로직은 local.properties를 Maps key source로 사용하지 않는다. Dart AppConfig도 GOOGLE_MAPS_API_KEY define을 읽는다.

필요한 외부 계약은 기존 key의 Android application restriction에 package `com.burgermapkorea.app` + 위 release **SHA-1**, API restriction에 **Maps SDK for Android**이다. SHA-256은 이 Android Maps restriction 입력을 대신하지 않는다. debug row와 release row는 다르다. 실제 restriction·enabled API 범위·billing/quota는 Console 접근 불가로 **UNVERIFIED**, 광범위 API 활성화를 추정하지 않는다. [Maps key security 문서](https://developers.google.com/maps/api-security-best-practices).

### K–N. Release APK / static inspection / device

실제 APK build와 검사 결과는 아래 최종 실행 기록에 추가한다. AAB를 재빌드하거나 수정하지 않는다. 기기는 `adb devices -l` **빈 목록**. 설치/uninstall/data clear를 하지 않았고 release device smoke는 **NOT RUN**이다. 기기 준비 후 기존 설치 signer를 비교하고 debug와 다르면 `install -r` 강행·uninstall 없이 **DEVICE_RELEASE_SMOKE_BLOCKED_BY_SIGNATURE**로 중단한다. 별도 테스트 기기 또는 같은 signer 설치 경로를 사용한다.

**Release APK build PASS**: `flutter build apk --release` + 기존 production/Supabase/Maps defines, `--no-pub` 없음, 271.1초 / exit 0.

- path: `build/app/outputs/flutter-apk/app-release.apk`
- size: **55,057,411 bytes**, SHA-256 `47301d2e4642965ff9be587186b99d75110ac14335eb3cb0a055ce6129de7e0e`
- aapt2 package/version: **com.burgermapkorea.app / 1.0.0 / versionCode 1**
- apksigner verification=true, configured release certificate match=true, debuggable=true 미검출.
- native Manifest Maps key == 기존 local Maps key **true**, key 본문 출력 없음.
- verifier safe=true, entries=141, public config hits=9, secretPatternHits=0, forbidden staging entry=0, asset manifest staging=0, staging UUID hits=0 / 24 checked.
- IntegrationTestPlugin/해당 DEX package 참조=0, integration_test ZIP entry=0. OAuth secret actual value 및 password-bearing postgres URI pattern=0. production Supabase host 존재 확인.
- OAuth Client ID actual pattern hits=0이며 Google build define 부재와 일치한다. Google 로그인 smoke용 후보가 아니다.
- 일반 localhost/loopback 문자열은 native AOT/engine에 남고 local Dart build path도 AOT에 남는다. 앱 소스 localhost/loopback endpoint 설정 파일=0. 최종 URL/외부 host 추가 검사 결과는 아래 preservation 기록에 포함한다. 일반 library 문자열을 actual endpoint로 오인하지 않는다.

APK PASS는 restriction·OAuth token exchange·지도 렌더링 성공을 대신하지 않는다. 기존 AAB의 SHA-256을 비교하여 유지 여부도 확인한다.

### O–R. 변경 범위와 검증

Production INSERT/UPDATE/DELETE/DDL/migration/RLS 모두 **0**. Supabase Auth/Google Cloud/Maps/Play Console 변경 모두 **0**. 읽기 전용 Supabase 공개 settings GET만 수행했다. source feature·dependency·Gradle·credential 파일 수정 없음. commit/push **NO**. 이번 수정은 이 기존 audit 문서뿐이고 ignored `build/google-services-audit-20261005/`에 snapshot/log/검사 결과를 보존한다. Flutter 355/355 및 analyze는 이전 compile fix의 결과이며 문서-only audit에서 다시 실행하지 않았다.

최종 preservation/추가 검사: 의도적으로 업데이트한 audit 문서 외 기존 사용자 파일 **48개 hash 동일**, 예상 밖 변경=0. 기존 AAB SHA-256도 이전 PASS artifact와 동일하다. APK explicit HTTP(S) localhost/127.0.0.1 URL 패턴=0, non-production Supabase host=0. 로그 raw/Base64 define 비노출 검사 통과. 임의 형식 모든 endpoint/secret 부재를 보장하는 검사는 아니며 위 일반 library 문자열·로컬 build 경로 잔존은 별도로 보고한다.

### S. 사용자가 Console에서 확인할 정확한 작업

다음은 **먼저 조회·대조할 절차**다. agent는 Save/Create/Enable을 실행하지 않는다. 누락 시 입력할 변경안을 기록하고, 기존 credential 삭제/교체·새 API key 생성은 하지 않는다. 이미 등록돼 있다면 변경 없이 그 증거만 확인한다.

1. **기존 Google OAuth project 선택** → Google Auth Platform → **Clients**. Android type의 기존 client 상세를 열어 package가 `com.burgermapkorea.app`, SHA-1이 `3D:F2:42:D9:BE:EE:AC:42:97:3F:B5:1B:23:13:49:C2:54:C2:8F:4C`인 항목이 있는지 대조한다. debug SHA 항목은 release 등록을 대신하지 않는다. 없으면 이 package/SHA-1 쌍의 release Android 등록 추가가 필요한 변경안이다. 기존 debug client를 삭제하거나 덮어쓰지 않는다.
2. 같은 project의 Clients에서 **Web application** type의 기존 client를 연다. public Client ID를 확인하고 이를 GOOGLE_WEB_CLIENT_ID에 사용한다. Android type ID를 복사하지 않는다. 기존 Web client secret을 reveal/채팅/앱 build 파일에 복사하지 않는다. 기존 Web client가 실제로 없다면 이번 작업에서는 만들지 말고 필요한 설정으로 보고한다.
3. Supabase Dashboard → production project `eoiwfprghyyguthdtayx` → Authentication → **Sign In / Providers → Google**. Enabled와 Client IDs에 같은 Web ID가 있는지, 기존 Web secret이 대응하는지 값 노출 없이 확인한다. 여러 허용 ID라면 공식 계약의 Web ID 우선 순서를 대조한다. secret 교체·nonce 설정 변경은 이 감사에서 하지 않는다.
4. Google Auth Platform의 **Audience** 및 **Data Access**에서 실제 목표 사용자 로그인 허용 상태와 openid/email/profile scope를 확인한다. Testing 상태면 smoke 계정의 허용 여부도 대조한다. 추가 scope/API는 현재 앱이 필요로 하지 않으면 임의 활성화하지 않는다.
5. 기존 Maps key의 Cloud project 선택 → Google Maps Platform → **Credentials** (또는 APIs & Services → Credentials) → **해당 기존 Android key 편집 화면**. API key 본문을 reveal하지 않고 Application restrictions가 Android apps인지 확인한다. package/SHA-1 목록에 위 release 쌍이 있는지 대조한다. 없으면 Android app row 추가가 필요한 변경안이다. 다른 사용 중인 row는 삭제하지 않는다.
6. 같은 key 화면의 **API restrictions**에서 Maps SDK for Android가 허용되는지 확인한다. APIs & Services → Enabled APIs & services에서 Maps SDK for Android 활성화, 기존 billing/quota 상태를 확인한다. 다른 API 제한 제거·billing 변경은 독립 검토 없이 하지 않는다.
7. Play Console → 해당 앱 → **App integrity / App signing**에서 실제 app-signing certificate SHA-1/SHA-256을 확인한다. 위 로컬 release 지문과 다르면 Play 설치본용 Android OAuth/Maps 쌍을 추가 확인해야 한다. upload certificate만 보고 Play signer로 쓰지 않는다.
8. 확인된 **public Web Client ID**를 기존 ignored public build configuration의 GOOGLE_WEB_CLIENT_ID로 제공하고 GOOGLE_SIGN_IN_ENABLED=true를 명시하여 다시 build한다. secret/API key 값을 채팅에 보내지 않는다. 이후 기기에서 Maps tiles → 계정 선택 → Supabase session → 지도 복귀 및 취소/오프라인 복구를 확인한다. production test review/report 작성은 포함하지 않는다.

### T–U. Remaining blockers / verdict

로컬 public Google login 설정 누락 + 외부 Android/Web/Maps 등록 미검증 + release device smoke 미실행이 남는다. privacy/Data Safety·계정 삭제·UGC·Play signing/버전/listing 및 기타 전체 readiness 항목은 기존 미완료 상태를 유지한다. 기존 Web ID와 registration 증거를 얻기 전에는 RELEASE_GOOGLE_SERVICES_READY로 승격하지 않는다.

## Google Play Policy Readiness Audit — 2026-10-05

**PLAY_POLICY_READINESS_AUDIT_COMPLETE / PLAY_POLICY_READINESS_BLOCKED**

이 절은 위의 과거 상태를 삭제하지 않고 최신 정책 감사 결과를 덧붙인다. application source, credential, migration, RLS, 운영 데이터, Console 변경 없이 문서만 작성했다. 아래 REQUIRED/CONDITIONAL/RECOMMENDED는 정책 강도이며 CRITICAL/HIGH/MEDIUM/LOW는 이 프로젝트의 출시 우선순위다.

### A. 기준 상태와 증거 범위

- branch `nearby-store-sort`, HEAD `f152a65121f7488df89cd3324ca6401170b7a105`, 로컬 remote-tracking `origin/nearby-store-sort`도 동일. 실제 원격 서버 최신값은 이번 감사에서 fetch하지 않았으므로 원격 최신이라고 단정하지 않는다.
- 기존 dirty `PROJECT_STATUS.md`, `README.md`, `integration_test/app_flow_test.dart` 및 untracked 자료를 보존한다. 새 기능·dependency 변경 없음.
- 사용자 요청의 production 건수(stores 280/public 237/menus 28/menu_evidence 29/profiles 2/reviews 0/reports 0)는 사용자 제공 참고값이며 이번 감사에서 재조회·확정하지 않았다.
- AAB/APK 빌드, Google 로그인 및 세션 확인은 이전 작업 결과다. 현재 설치 후보 APK 4017에 새 Web ID가 들어간 기록이 있다. 이 감사에서 로그인/리뷰/신고를 실행하지 않았다.
- **Maps 후속 해결:** 14:12:07 logcat의 `Authorization failure`와 빈 타일은 과거 실패 증거다. 이후 사용자가 실제 production key 프로젝트에 package + release SHA-1 조합을 추가한 뒤 정상 지도를 확인했다고 명시했다. 최신 상태 **RELEASE_MAPS_PASS**, 원인 **MAPS_RELEASE_SHA_RESTRICTION**. 이번 backend 작업은 문서만 갱신하며 새 Android smoke 수행을 주장하지 않는다.
- 코드·tracked migrations·resolved dependency source·기존 merged release manifest를 조사했다. live production schema, 개인 Auth metadata, 저장소 내용, 로그 설정, 계약, Play Console는 열람하지 않았다. FK 결과는 migration 기준이며 live drift 확인은 구현 전 별도 read-only 검증 사항이다.
- 이번 문서 감사에서는 Flutter 테스트/빌드/실기기 정책 동작을 다시 실행하지 않았다. 기존 PASS 숫자를 신규 검증으로 재사용하지 않는다.

### B. 현재 공식 정책 근거

확인일 2026-10-05. Google Play **full policy**를 우선했으며 블로그·Reddit·StackOverflow를 정책 근거로 사용하지 않았다.

| ID | 공식 출처 | 핵심 적용 |
|---|---|---|
| P1 | [User Data](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en) | REQUIRED: 실제 처리와 일치하는 개인정보처리방침·안전한 처리. CONDITIONAL: 예상 밖 민감정보 처리는 명시적 앱 내 고지/동의 |
| P2 | [Account deletion](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en) | REQUIRED: 앱 내 계정 생성이면 앱/외부 웹에서 삭제 시작 가능, 관련 데이터 삭제. 공개 웹의 이메일/폼 요청도 가능 |
| P3 | [Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en) | REQUIRED: SDK 포함 정확한 양식. local-only, ephemeral, sharing 예외를 구분 |
| P4 | [UGC](https://support.google.com/googleplay/android-developer/answer/9876937?hl=en) | REQUIRED: UGC 전 약관 동의, 금지 콘텐츠 정의, 적절한 지속 관리. 공개 UGC는 콘텐츠·사용자 신고 및 사용자 차단 |
| P5 | [Permissions / location](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en) | REQUIRED: 필요 최소 권한, 기능 맥락의 요청, 거부 존중. 현재 전경 위치와 background 요건을 구분 |

P5는 2027-01-27 예정 변경도 표시한다. 아직 발효 전인 location button 권고를 2026-10-05의 필수 구현 blocker로 소급하지 않는다. 출시가 그 이후라면 재감사한다.

기술 근거(Play 정책과 구분): [Maps SDK disclosure](https://developers.google.com/maps/documentation/android-sdk/play-data-disclosure), [Google OIDC](https://developers.google.com/identity/openid-connect/openid-connect), [Supabase Google Auth](https://supabase.com/docs/guides/auth/social-login/auth-google), [Auth audit logs](https://supabase.com/docs/guides/auth/audit-logs), [서버 deleteUser](https://supabase.com/docs/reference/javascript/auth-admin-deleteuser), [검증된 getUser](https://supabase.com/docs/reference/javascript/auth-getuser), [Auth user 관리](https://supabase.com/docs/guides/auth/managing-user-data). Supabase changelog.md는 fetch 오류로 읽지 못했으며 이번에는 구현·dependency 변경이 없다.

### C. Actual data inventory / Data Safety

전체 데이터별 Collected/Stored/Local-or-Server/Purpose/Required/외부 처리/Retention/Deletion/코드 근거 표는 [Data Safety 초안 §3](google-play-data-safety-draft.md#3-실제-데이터-흐름-전수표)에 있다. 주요 결론:

- AUTH: Google 식별자·email/profile scope·ID/access token, Supabase UUID/session. 이름·사진 URL은 SDK 반환 가능하며 실제 제공 여부는 계정별이다. 화면에서 사용하지 않아도 Auth metadata/session JSON에 포함될 수 있다.
- PROFILE: id/nickname/is_suspended/created_at/updated_at. 공개 author endpoint는 UUID와 닉네임에 제한되며 이메일은 공개하지 않는다.
- REVIEWS: rating 1~5, content nullable(있으면 10~2000자), user/store relation, timestamps, hidden/moderation metadata. 현재 본문 없는 평가도 공개 UGC다.
- REPORTS: reporter/review ID, reason/detail, status 및 resolution metadata. 클라이언트는 insert하며 신고자나 운영 기록을 일반 public read로 노출하지 않는다.
- LOCAL: favorites 매장 IDs는 SharedPreferences. **session도 SDK 기본 SharedPreferences에 저장**되므로 “기기에 즐겨찾기만 저장”은 불완전한 설명이다. Android backup 동작은 별도 미검증.
- SDK: Maps의 요청/기기 정보·IP·SDK ID·crash·camera interactions는 자체 처리다. 별도 앱 analytics SDK 부재가 telemetry 전체 부재는 아니다.
- 실제 프로젝트 로그·백업 TTL, 외부 공급자 역할·리전, Google Auth metadata 정확한 필드, SDK 위치 off-device/보유 범위는 NEEDS VERIFICATION이다.

### D. Location / permissions / disclosure

`geolocator_current_location_service.dart:63` → `current_location_controller.dart:115` → `map_screen.dart:1124`에서 사용자 동작 후 위치를 취득한다. 가까운 순 계산은 `map_screen.dart:205`의 로컬 계산이다. 위치 값은 current controller 메모리에 있으며 배경 시 `current_location_controller.dart:138`에서 무효화된다. 신선도 기준은 2분이다. OS last-known 조회를 앱의 자체 영구 저장이라고 해석하지 않는다.

lib 전체의 저장/네트워크/로그 경로와 repository payload를 조사했고 Supabase 위치 전송·좌표 DB 저장·SharedPreferences 위치 저장·좌표 logger 호출은 발견되지 않았다. 반면 `map_screen.dart:595`의 My Location과 `:1158`의 CameraUpdate는 Google Maps SDK로 위치 관련 값을 전달한다. **앱 자체 경로는 local-only지만 SDK 전체 off-device 수집은 미확정**이다. precise/approximate Data Safety를 무조건 NO로 작성하지 않는다.

release merged manifest의 실제 permission:

| Permission | 기능/판정 |
|---|---|
| INTERNET | Supabase·Google 네트워크, 필요 |
| ACCESS_FINE_LOCATION + ACCESS_COARSE_LOCATION | 현재 위치·근거리 정렬. geolocator Android PermissionManager가 함께 요청; 대략 위치만 허용하는 경로 존재 |
| ACCESS_NETWORK_STATE | SDK 네트워크 상태 사용 |
| USE_BIOMETRIC, USE_FINGERPRINT | manifest merger에서 `androidx.biometric:biometric:1.1.0` 유입 확인. 앱 자체 biometric feature 호출 없음. 제거 가능성/credential dependency 사용 여부를 별도 확인; 권한 존재만으로 지문 원본 수집 YES 금지 |
| 앱 전용 DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION | signature 보호용 receiver permission; 사용자 데이터 수집 권한과 구분 |
| ACCESS_BACKGROUND_LOCATION | **없음**. background location을 사용하는 코드 경로도 발견되지 않음 |

“현재 위치로 이동”, “가까운 순”의 요청 맥락 및 거부 시 탐색 유지가 존재한다. 정보 및 지원 화면에도 목적 안내가 있으나 권한 요청 전 별도의 목적 설명 UI는 없다. **REQUIRED:** 실제 사용·권한·공개 설명의 정합성과 최소 범위. **CONDITIONAL:** 예상 밖 SDK 위치 공유 등이 확인되면 정상 흐름에서 사전 고지와 명시 동의가 필요하다(P1). 현재 증거만으로 모든 foreground 앱에 별도 modal을 강제하지 않는다. **RECOMMENDED:** 첫 요청에 “현재 위치 표시·거리 계산, 대략 위치 가능” 설명 추가. 정확 위치의 필요성과 SDK 처리 검증은 제출 전에 종료해야 한다. 별도의 background 권한 선언/검토를 추가할 이유는 없다.

### E. Privacy policy / public access gap

P1 기준 public URL과 앱 내 방침 접근은 REQUIRED. 공개 문서는 운영자 또는 앱 식별, 문의 경로, 처리 데이터/목적/대상, 안전 처리, 보유·삭제를 실제로 설명해야 한다. URL은 공개 접근 가능하고 지역 차단·PDF·독자 편집 형태를 피해야 한다.

기존 `AppInfoScreen`에는 개인정보처리방침 진입점이 **이미 있다**. `lib/core/config/app_config.dart:219`의 `PRIVACY_POLICY_URL`이 유효한 HTTPS일 때 활성화되며 아니면 준비 중 안내를 표시한다. APK 4017 build wrapper는 이 define을 전달하지 않았고 기본값은 빈 문자열이다. 따라서 “UI가 전혀 없다”가 아니라 **실제 유효한 링크 미연결**이 blocker다. `SUPPORT_URL`, `OPERATOR_NAME`도 같은 빌드에 미주입이다.

최소 변경: 기존 지도 우상단 정보 및 지원 → 방침 링크를 실제 public URL에 연결. 로그인/첫 UGC 동의 화면에서도 같은 정책을 열 수 있게 한다. 웹 사이트 자체를 대규모 개발할 필요는 없다. 개인정보 동의와 UGC 약관 동의의 목적을 혼동하지 않는다.

[개인정보처리방침 초안](privacy-policy-draft-ko.md)을 생성했다. 문의처 `[PRIVACY_CONTACT_EMAIL]`, 운영자, 시행일, retention/deletion, 외부 처리 세부사항은 미정 표시다. 이 초안을 현재 서비스의 완성된 정책으로 게시하지 않는다.

### F. Account creation / deletion current state

Google SSO가 Supabase identity/user를 만들고 닉네임이 profiles로 연결된다. 이메일 magic link도 `shouldCreateUser:true`다. 따라서 P2의 app account creation에 해당한다. 게스트 탐색이 가능해도 적용된다.

lib Auth 인터페이스·repository·UI 및 migrations에서 계정 삭제 버튼/요청 endpoint/Auth admin delete/associated-data 삭제 workflow를 찾지 못했다. 현재 logout만 있고 `is_suspended`는 운영 제한이다. 둘 다 삭제를 대신하지 않는다. UI나 정책에 계정 삭제가 지원된다고 표시할 수 없다.

### G. FK / deletion model — migration 기준

| Parent 삭제 | Child / column | 동작 | 영향 |
|---|---|---|---|
| auth.users | profiles.id | CASCADE | nickname·suspension·timestamps 제거 |
| profiles | reviews.user_id | CASCADE | 본인 모든 리뷰 및 moderation 기록 제거 |
| reviews | review_reports.review_id | CASCADE | **다른 사람이 해당 리뷰에 남긴 신고도 삭제** |
| profiles | review_reports.reporter_user_id | CASCADE | 이 사용자가 타인 리뷰에 남긴 신고 삭제 |
| stores | reviews.store_id, menus.store_id | RESTRICT | 참조 데이터가 있으면 매장 삭제 거부; 계정 삭제 방향에는 영향 없음 |
| stores / menus | private.menu_evidence FK | RESTRICT | store/menu evidence는 계정과 직접 관계 없음 |
| auth.users | stores/menus/menu_evidence | 직접 FK 없음 / PRESERVED | 계정 삭제로 운영 매장·메뉴를 건드리지 않음 |
| auth.users | 공급자 로그·백업·SDK telemetry | 앱 migrations 범위 밖 | CASCADE를 주장할 수 없음; 별도 보유/삭제 확인 |
| auth.users | favorites / 로컬 sessions | DB FK 없음 | 별도 client cleanup 결정 필요 |

분석한 app-owned FK에는 SET NULL 경로가 없다. 사용자 리뷰 DELETE도 연결 신고를 지우므로 신고를 불변 기록으로 설명하면 틀리다. 신고 보존이 필요하면 합법적 목적/최소항목/기간을 먼저 결정하고 별도 migration 승인을 받아야 한다. 이번 최소안은 기존 CASCADE 유지이며 불필요한 보존용 테이블을 추가하지 않는다.

### H. 최소 안전 계정 삭제 구조 — 제안만

선택안: **Flutter → 인증된 Supabase Edge Function → 서버에서 Auth user 검증 → 자기 계정 hard delete → 기존 FK cascade → 로컬 session 정리**.

1. 화면에 계정/리뷰/신고 삭제 영향과 복구 불가를 설명하고 명시적 확인을 받는다. 새 Google 계정 삭제로 오해하지 않도록 앱 계정임을 표시한다. 정지 사용자·프로필 없는 Auth 사용자도 요청할 수 있어야 한다.
2. POST endpoint는 인증 header를 요구한다. `auth.getUser(jwt)` 등 서버 검증 결과의 user.id만 사용한다. body의 임의 user_id를 신뢰하거나 단순 JWT decode로 승인하지 않는다. origin/CORS만으로 인증하지 않는다.
3. privileged client는 서버 비밀 환경에만 둔다. 최소 기능은 검증한 current user의 `auth.admin.deleteUser(id, false)`이며 Flutter에 service_role/서버 secret을 전달하지 않는다. 사용자 rows를 먼저 임의 순서로 지우는 앱 기능을 만들지 않는다.
4. 실제 production FK/trigger/storage 소유 관계를 구현 전 read-only preflight한다. Auth 관리 API와 외부 저장소/로그는 단일 애플리케이션 transaction으로 묶인다고 가정하지 않는다. timeout/부분 실패/재시도 결과를 구분하고 실패를 성공으로 표시하지 않는다.
5. session/refresh 처리와 로컬 cleanup을 검증한다. 기존 JWT는 만료 전까지 서명상 유효할 수 있다. **중요 기존 gap:** `profiles_owner_insert`는 현재 user 존재를 명시 확인하지 않고 auth.uid를 사용한다. Auth row 삭제 뒤에는 FK가 insert를 막아야 하며 이를 만료 전 token replay로 검증한다. 다른 쓰기들도 profile 존재와 RLS로 차단되는지 확인한다. deletion endpoint 자체는 삭제된 user의 replay를 getUser 검증으로 거부한다.
6. 기기 session JSON을 SDK 정상 경로로 제거한다. favorites는 계정과 무관한 로컬 데이터이므로 삭제 시 함께 초기화할지 설명과 일치시킨다. 다른 기기 세션, 오프라인 UI, 공급자 로그·백업까지 “즉시 완전 삭제”라고 약속하지 않는다.

서비스 API 근거: [서버 deleteUser](https://supabase.com/docs/reference/javascript/auth-admin-deleteuser), [getUser](https://supabase.com/docs/reference/javascript/auth-getuser). 계정 삭제 후 JWT 유효성/Storage 소유 제약은 [공식 사용자 관리](https://supabase.com/docs/guides/auth/managing-user-data)에 설명돼 있다.

기존 관계가 production과 같고 별도 retention/acceptance 기능을 넣지 않는다면 삭제 기능 자체를 위한 DB migration은 **불필요 후보**다. 실제 배포·production 삭제는 이 감사의 승인이 아니다.

### I. External deletion web requirement

P2 기준 외부 요청 경로 REQUIRED. 앱을 재설치해야만 요청할 수 있게 만들면 안 된다. 운영자/앱 명칭, 분명한 삭제 요청 방법, 대상 데이터, 남는 정보와 기간, 처리 예상 시간을 갖춘 작동하는 public URL을 Play Console에 등록해야 한다.

**최소 MVP 선택안:** GitHub Pages 같은 정적 HTTPS 페이지 + 실제 관리되는 삭제 요청 이메일/폼 + 본인 확인 후 운영자 처리. 페이지에 “[앱] 계정 삭제 요청”을 명시하고 메일 주소만으로 타인 계정을 삭제하지 않는다. email ownership 또는 기존 로그인 기반 확인이 필요하다. 처리 담당·기한·완료 안내를 정한 뒤 운영할 수 있다. 정적 페이지가 자동 삭제를 수행한다고 설명하지 않는다.

대안은 별도 공식 정적 사이트 + 같은 API, 또는 Supabase/Edge Function 기반 응답 페이지다. 후자는 HTML 제공·보호·운영 경로 검증이 추가되므로 현재 가장 작은 선택은 정적 페이지와 관리되는 요청 절차다. 실제 페이지 배포/도메인 구매/메일 발송/Console 변경은 수행하지 않았다.

### J. UGC / acceptance / user blocking

| 요구/기능 | 정책 강도 | 현재 | 판단 / 최소안 |
|---|---|---|---|
| 공개 rating/선택 본문 리뷰 | REQUIRED 정책 적용 | 게스트 public read | UGC, 본문이 선택이어도 제외되지 않음 |
| 작성 전 terms/user policy 동의 | REQUIRED P4 | 없음 | HIGH blocker. 첫 평가/리뷰 제출 전에 명시 동의, 정책 열람, 거부 시 탐색 허용 |
| 유해 내용/행동 정의 | REQUIRED P4 | 앱 연결된 정책 없음 | 커뮤니티 초안 게시·동의 연결 |
| 콘텐츠 신고 | REQUIRED P4 | 리뷰 신고 UI + DB + 중복 방지 존재 | 기존 구현 기반 유지, 실기기 재검증은 향후 수행 |
| 사용자 신고 | REQUIRED P4 공개 UGC 조항 | review_id 신고만 있음 | HIGH gap. 리뷰 메뉴에서 “작성자 신고”, actor와 evidence review ID를 운영자가 확인 가능하도록 최소 모델 설계 |
| 사용자 차단 | REQUIRED P4 공개 UGC 조항 | 없음 | HIGH blocker. 댓글/DM/태그 없음이 면제 사유 아님 |
| 지속 moderation | REQUIRED P4 | hide/unhide·suspension 가능; 운영 주기/담당 미정 | 도구 개발보다 운영 책임·절차·조치 실행을 먼저 완료 |
| 동의 version/timestamp DB 보관 | RECOMMENDED 증거/운영 | 없음 | Play가 특정 schema를 요구하지 않음. 기능적 동의는 필수, 기록 저장 설계는 선택 |
| 관리자 Flutter 화면 | RECOMMENDED 운영 편의 | 없음 | 자동 blocker 아님. 권한 통제된 수동 운영 가능 |
| 1:1 interaction 전용 기능 | CONDITIONAL | DM/댓글/태그 없음 | 해당 기능 추가 전 재검토; 공개 UGC 의무는 별개 |

P4의 공개 UGC 문구 중 필요한 부분만 인용: “report users and content, and to block users.” 소셜 앱 예시는 범위를 그 앱 종류에만 제한하지 않는다. Burger Map은 공개 리뷰를 제공하므로 적용된다고 판단한다. **현재 scope에서는 사용자 blocking을 출시 후로 미룰 수 없다.**

최소 blocking 제안: 공개 리뷰의 작성자 메뉴에 차단/차단 해제, 해당 작성자의 리뷰를 사용자 화면에서 제외, 관리 목록 제공. DM 차단·친구 그래프·사용자 검색 등은 불필요하다. 현재 게스트 public read를 유지하므로 local-only 차단을 택할지, 계정별 server 목록과 로컬 게스트 목록을 함께 둘지 결정해야 한다. 로컬 MVP도 정책 문구가 특정 DB 구현을 강제하지는 않지만, 재실행 후 유지·모든 리뷰 표시 경로의 일관성·재설치/다른 기기 범위를 명확히 검증해야 한다. 서버 방식은 별도 migration/RLS 승인 필요. 차단과 운영자 suspension은 다른 기능이다.

### K. Reporting / moderation 운영 gap

`review_report.dart` UI 사유 6개: 욕설·비방, 개인정보, 광고·도배, 허위 정보 의심, 무관, 기타. DB reason은 spam/harassment/personal_information/irrelevant/other이며 허위 정보는 설명 prefix와 other로 매핑한다. 현재 enum을 임의로 확장하지 않는다. 불법/위험 콘텐츠도 기타 설명으로 신고 가능하여 전용 버튼 부재만으로 blocker로 판단하지 않는다.

기존 operator 모델은 review hidden 필드와 일관된 note/time/actor, report pending/resolved/dismissed 및 resolution 기록을 지원한다. `can_contribute()`는 suspended 사용자의 기여를 막는다. 본인 review 삭제는 suspension 여부와 별개로 가능하다. 리뷰 public view와 profile public author policy가 hidden을 제외한다. 이미 게시된 다른 리뷰는 suspension만으로 자동 숨김되지 않으므로 운영 시 별도 검토해야 한다.

보고 UI→운영 검토→숨김/복원은 초기 수동 운영으로 충족할 수 있다. 실제 담당자·신고 확인 주기·긴급 기준·이의제기 경로·완료 확인을 정하지 않은 상태는 운영 gap이다. 기존 smoke 문서는 technical validation이며 지속 운영 runbook을 대신하지 않는다. 매장 소유자에게 타인 리뷰 삭제 권한을 주지 않는 현재 정책과 충돌하지 않는다.

최소 runbook 제안(아직 가동 아님): 권한 있는 운영자가 pending queue 확인 → 개인정보/위협 등 우선 분류 → 증거·문맥 확인 → 숨김/기각/복원 및 처리 기록 → 반복 위반 계정 제한 → 누락·재발 확인. 자동 신고 횟수만으로 삭제하지 않는다. 정당한 부정적 평가는 허용한다. 상세 응답 SLA는 **NEEDS USER DECISION**, 임의 시간 약속 없음.

### L. Release blocker matrix / fix now vs defer

| 우선순위 | 항목 | 강도 | 첫 Play 제출 전 판정 |
|---|---|---|---|
| CRITICAL | 앱 내 계정 삭제 시작 + 안전한 associated-data 처리 | REQUIRED P2 | 미구현, MUST FIX |
| CRITICAL | 삭제 외부 public URL/작동하는 요청 운영 | REQUIRED P2 | 미확인/미구현, MUST FIX |
| HIGH | 실제 privacy public URL·내용·문의처 및 앱 내 연결 | REQUIRED P1 | 자리만 있고 기능 불가, MUST FIX |
| HIGH | Data Safety SDK/location/shared/retention 불확실성 및 최종 양식 | REQUIRED P3 | NEEDS VERIFICATION, MUST FIX |
| HIGH | UGC 작성 전 동의·금지 행동 정의 | REQUIRED P4 | 미구현/초안, MUST FIX |
| HIGH | 사용자 신고·차단 | REQUIRED P4 공개 UGC | 미구현, MUST FIX |
| HIGH | moderation 담당·지속 운영 경로 | REQUIRED P4 결과 요건 | 도구 있음, 운영 증거 필요; MUST FIX |
| RESOLVED | release Maps 인증 실패 | `MAPS_RELEASE_SHA_RESTRICTION` | 사용자 후속 확인: Release Maps PASS |
| HIGH | Play Console 최종 공개 정보·삭제 URL·Data Safety·UGC content rating/대상 연령 | REQUIRED / 대상별 CONDITIONAL | 실제 Console 미검증; 제출 전 확인 |
| MEDIUM | 위치 SDK 흐름·정확 권한 필요성·고지 충분성 | REQUIRED 최소권한 + CONDITIONAL prominent disclosure | 증거 확정은 제출 전; 별도 modal 자체는 자동 의무 아님 |
| MEDIUM | biometric 전이 권한·session 저장/OS backup 검토 | REQUIRED 필요권한/안전처리, 구현방법은 선택 | 정당성/보호 검토를 제출 전 완료; 자동으로 생체정보 수집 선언 금지 |
| MEDIUM | 삭제/로그/백업 retention 및 기존 JWT 재사용 검증 | REQUIRED 정책 정합성 + 보안 구현 | 삭제 기능 acceptance 기준에 포함 |
| LOW | 전용 관리자 앱, 자동 moderation/분석 대시보드 | RECOMMENDED | MVP 후 가능 |
| LOW | 동의 증거 DB의 고급 감사 이력/운영 자동화 | RECOMMENDED | 동의 기능 및 최소 운영 증거 확보 후 개선 가능 |

**MUST FIX BEFORE FIRST PLAY SUBMISSION:** 위 CRITICAL/HIGH의 실제 기능/문서/운영, MEDIUM의 미확정 데이터/권한·보안 판단, 최종 정책·양식 정합성. 공개/폐쇄 테스트 트랙과 internal-only 면제 범위는 실제 제출 트랙에 맞춰 P3로 확인하되 첫 일반 출시 목표를 internal-only 예외로 통과시키지 않는다.

**CAN DEFER AFTER MVP RELEASE:** 관리자 Flutter UI, 자동 moderation/응답 봇, 신고 처리 대시보드, 고급 이의제기 자동화, 즐겨찾기 서버 동기화, 선제적 모든 계정 차단 네트워크 기능, 별도 전체 마케팅 사이트. 필요한 사용자 신고·차단·실효성 있는 moderation·계정 삭제 자체는 defer 대상이 아니다.

### M. Small implementation phases — 제안 경로는 아직 생성하지 않음

| Phase | 범위 / files | DB impact / migration | Production risk | Tests | Device verification |
|---|---|---|---|---|---|
| P0 | 운영자/문의/보유/삭제/목표 연령 결정; 이 4개 문서 TODO, SDK 및 live-schema read-only 확인 | 쓰기 없음; migration 없음 | 조회 정보 최소화 | 정책·schema·SDK evidence 대조 | 현재 permission/정책 entry 확인 |
| P1 | `supabase/functions/delete-account/index.ts` 제안; 계약·서버 auth 검증·오류/재시도; 삭제 검증 tests 제안 | 기존 cascade 활용 시 migration 불필요 후보; drift/retention 필요시 별도 승인 | HIGH: Auth 삭제는 비가역, **로컬/격리 계정만 검증**, production 실사용자 삭제 금지 | forged/missing/expired JWT, 타인 ID 무시/거부, suspended/profile 없는 user, FK cascade, 타인 데이터 보존, token replay, timeout | Flutter 연결 전 endpoint 격리 검증 |
| P2 | `auth_repository.dart`, `supabase_auth_repository.dart`, `auth_controller.dart`, `auth_gate.dart`, 계정 삭제 UI 제안, 기존 map/info entry | 데이터 삭제는 P1만; source 변경 별도 task | HIGH: 잘못된 계정 삭제·성공 오판 방지 | 취소/중복 탭/네트워크 실패/성공 cleanup/세션 만료/favorites 결정 | release APK에서 별도 disposable 계정만, 계정·관련 데이터 삭제 및 재시작 |
| P3 | `app_info_screen.dart`, `login_screen.dart`, `store_review_section.dart`, config/link 및 첫 UGC 동의 UI | 로컬 version 동의 최소안은 migration 없음; 서버 acceptance 기록 선택 시 필요 | MEDIUM: 공개 탐색 유지, content 없는 rating도 gate | 링크 오류·접근성·동의 거절·재시작·정책 버전·제출 gate | 권한 사전 문맥, 링크, 동의 전 제출 차단 |
| P4 | review author 신고/차단·해제, domain/repository/화면 tests 및 운영 runbook | local 차단은 migration 없음 후보; account-sync/user-report 모델은 현재 schema 확장 필요 가능, 별도 승인 | HIGH: 사용자 식별 위조·타인 콘텐츠·guest 동작 | actor identity, 모든 review 경로 차단, 지속/해제, 신고 중복·권한, moderator 수동 조치 | 기존/게스트/정지 계정의 신고·차단·리뷰 표시 |
| P5 | 정적 privacy/community/deletion 페이지 제안 + 실제 지원 채널 + release public defines | 앱 DB migration 없음; 요청 서비스 선택 시 별도 | 외부 게시/연락처 공개는 별도 승인 | public HTTPS, 로그인 없이 접근, 삭제 요청이 앱 설치를 요구하지 않음 | 정책·삭제 링크를 외부 브라우저에서 확인 |
| P6 | 최종 Data Safety/Play Console·content rating·privacy/deletion URL·출시 SDK 대조 | DB 쓰기 없음; Console 저장은 별도 명시 승인 | 잘못된 공개 선언 위험 | 실제 APK/manifest/SDK/data contract와 답변 일치, secret/staging 검사 | Maps PASS 별도 확보 후 로그인·삭제·UGC·위치 release smoke |

P3/P4 구현은 이번 감사에 포함하지 않는다. P1 전에 신고 보유 예외 여부를 결정하되 근거 없는 데이터 보존을 요구하지 않는다. 정책·운영 결정을 기록하고 가장 작은 contract부터 진행한다.

### N. 산출물 / 검증 / 다음 작업

- [privacy-policy-draft-ko.md](privacy-policy-draft-ko.md): 실제 데이터 처리와 TODO를 구분한 한국어 개인정보처리방침 초안.
- [community-guidelines-draft-ko.md](community-guidelines-draft-ko.md): 정당한 부정 평가 허용, 금지행동·신고·운영 조치·미구현 기능 구분.
- [google-play-data-safety-draft.md](google-play-data-safety-draft.md): 전수 inventory·Play 양식 후보·SDK/dependency 근거·미확정 답변.
- 이 기존 release-readiness 문서에 정책 출처·계정 삭제 FK·구현 단계·blocker를 추가.

검증은 문서 범위/링크·근거 경로·비밀값 패턴·기존 파일 보존 확인에 한정한다. 실기기 정책 검증, live schema 검증, 법률 준수 확정, Play 제출 승인을 대신하지 않는다.

완료 검증: 변경 전 tracked/untracked 파일 344개를 해시로 기록했고, 기존 audit 문서 1개만 변경·요청한 초안 3개만 추가됐다. 나머지 기존 343개 파일 동일, 삭제 0. 네 문서의 trailing whitespace 0, 깨진 로컬 파일 링크 0, 검사한 API key/OAuth secret/서버 secret/JWT 패턴 0. lockfile 121개 package/version/dependency 구분을 Data Safety 부록에 전사했다. 새 기능 테스트·분석·빌드는 문서-only 범위라 실행하지 않았다.

Production INSERT/UPDATE/DELETE/DDL/migration/RLS **ALL 0**. Auth user/profile/review/report 삭제 **0**. Google Cloud/Supabase Auth/Play Console 변경 **0**. Application source **NONE**. commit/push **NO**.

**Exact next task:** P0의 운영자·삭제 처리 기한/보유 예외를 확정한 뒤, **Account Deletion Backend Contract + 격리 환경 테스트**를 별도 요청으로 시작한다. production 삭제 없이 live FK read-only 대조, current-user-only 인증 검증, hard-delete/cascade/잔존 JWT·timeout acceptance 기준을 고정한다. 기존 FK로 충분하면 migration을 추가하지 않는다.

**Overall: PLAY_POLICY_READINESS_BLOCKED.** 감사 산출물 완료와 첫 Play 제출 준비 완료는 별개의 판정이다.


## Account Deletion Backend ?? ? 2026-10-05

**ACCOUNT_DELETION_BACKEND_LOCAL_PASS / IMPLEMENTED_LOCAL_NOT_DEPLOYED**. ?? production FK? ?? RLS? ?? ???? ????. ? cascade ??? migrations/local/production ??. ? ?? ??? JWT? Auth?? ??? current user? hard delete??. ?? ??? 7/7, ?? ?? Auth JWT E2E 57 assertions PASS. ?? ID body/query ??, ?? profile/review/report ??, ?? ??? ??, ?? ??/???? ?? JWT? ????.

? ?? ??? ? G?H? backend ???/?? ??? ????. ? ? UI?? ?? ???production ??? ??? ????? ?? blocker?. ?? fixture users/profiles/reviews/reports ?? 0; ?? ??????? 0, ?? ?? ??. Production mutation/deploy/config ?? ALL 0. ?? FK ????????? ??? [backend ???](account-deletion-backend-local-2026-10-05.md)? ???.
