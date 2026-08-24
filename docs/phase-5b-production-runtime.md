# Phase 5B Production Runtime 분리

## 목표

development의 pilot·staging·Supabase 검증 흐름을 보존하면서 production과 release에서는 Supabase 공개 데이터만 사용한다. production 설정이 잘못돼도 pilot 3곳이나 staging 24곳을 대신 표시하지 않는다.

## 환경 결정표

| 빌드 | 요청 `APP_ENV` | 요청 `STORE_DATA_MODE` | effective environment | effective data mode |
| --- | --- | --- | --- | --- |
| debug/profile | 미지정 또는 development | pilot | development | pilot |
| debug/profile | development | staging | development | staging |
| debug/profile | development | supabase | development | supabase |
| debug/profile | staging | 모든 값 | staging | supabase |
| debug/profile | production | 모든 값 | production | supabase |
| release | 모든 값 | 모든 값 | production | supabase |

release 여부와 요청 환경·모드를 받는 순수 `resolveRuntimePolicy`가 effective 값을 결정한다. 테스트에서 `kReleaseMode`를 변경하지 않고 release 정책을 검증할 수 있다.

## 데이터 안전 경계

- 아무 define이 없는 debug 실행은 기존 development/pilot 3곳을 유지한다.
- development에서만 pilot과 staging asset을 선택할 수 있다.
- production과 release는 Supabase만 선택한다.
- production에 pilot/staging이 전달되면 요청을 무시하고 Supabase로 고정한다.
- release는 `APP_ENV=development`가 전달돼도 production으로 고정한다.
- Supabase 설정이 유효하지 않으면 로더를 호출하지 않고 `서비스 설정을 확인할 수 없습니다.`를 표시한다.
- 설정 오류와 네트워크 오류는 내부적으로 구분한다. 네트워크 오류는 기존 일반 오류와 재시도를 사용한다.
- 정상 0행은 오류가 아니며 `현재 공개된 매장이 없습니다.`를 유지한다.

런타임 선택 차단과 asset 패키징은 구분해야 한다. 초기 Phase 5B에서는 `pubspec.yaml`의 `assets/dev/` 정적 선언 때문에 로컬에 생성된 staging JSON이 release 진단 AAB에도 포함됐다. 이를 다음 구조로 분리했다.

- `pubspec.yaml`에서 `assets/dev/` 전역 선언 제거
- Android debug build에서만 `prepareDebugStagingAssets` Gradle `Sync` task 실행
- ignored JSON을 `build/app/generated/debugStagingAssets/flutter_assets/assets/dev/` 아래에 복사
- 생성 디렉터리를 Android debug asset source set에만 연결
- `mergeDebugAssets`가 복사 task를 선행하도록 연결
- release source set과 task에는 staging 파일을 연결하지 않음

`Sync` output은 `build/` 내부에만 존재하고 원본이 없으면 이전 생성본도 정리한다. 개발자가 소스 트리에 복사본을 만들거나 매번 수동 복사할 필요가 없다. debug APK에는 `assets/flutter_assets/assets/dev/yongsan_burger_stores_staging.json`이 들어가므로 기존 `rootBundle` 경로를 유지한다.

다른 대안을 선택하지 않은 이유:

- release tree shaking에만 의존하면 실제 데이터 문자열 제거를 산출물 수준에서 보장하기 어렵다.
- Android source directory에 복사본을 두면 ignored 실제 데이터가 `build/` 밖에 남고 수동 동기화가 필요하다.
- flavor별 Flutter 구조는 현재 한 개의 개발 asset을 분리하기에는 설정 범위가 지나치게 크다.

## Supabase 설정 검증

Flutter 클라이언트는 다음 두 값만 입력받는다.

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

두 값은 사용 전에 앞뒤 공백을 제거한다. URL은 host가 있는 HTTPS base URL이어야 하며 다음을 차단한다.

- HTTP 또는 잘못된 URL
- `/rest/v1` 및 그 하위 경로
- 다른 임의 경로
- query와 fragment
- userinfo

`/rest/v1`은 SDK가 내부에서 붙이므로 Project URL에 포함하면 중복 경로가 만들어진다. 과거 실제 연결에서 이 구성으로 `PGRST125`가 발생했다.

Publishable key 형식은 향후 변경을 막지 않도록 특정 prefix만 강제하지 않는다. 빈 값과 `sb_secret_`, `service_role`, legacy JWT의 privileged role처럼 명백한 고권한 key만 차단한다. Secret/service-role 입력 변수나 Flutter 쓰기 경로는 추가하지 않았다.

development debug에서만 다음과 같은 안전한 code를 로그에 남길 수 있다.

- `missing_supabase_url`
- `missing_publishable_key`
- `invalid_supabase_url`
- `url_has_rest_path`
- `disallowed_privileged_key`
- `disallowed_data_mode`

URL, key, header, 예외 원문은 로그와 화면에 출력하지 않는다. production과 release에서는 이 진단 로그도 비활성화한다.

## Google Maps key

Android manifest는 `${GOOGLE_MAPS_API_KEY}` placeholder를 사용한다. Gradle은 다음 순서로 값을 찾는다.

1. Gradle property
2. 운영체제 환경변수
3. Flutter `--dart-define=GOOGLE_MAPS_API_KEY=...`
4. 빈 값

실제 key를 소스나 `.env` asset에 넣지 않는다. Android Maps SDK 특성상 key는 최종 APK/AAB manifest에 포함되므로 비밀값처럼 숨기는 방식이 아니라 Google Cloud에서 Android application restriction과 Maps SDK for Android API restriction으로 보호해야 한다. debug 인증서 제한은 확인됐으며, 로컬 release 테스트용 upload 인증서와 Play 배포용 Play App Signing 인증서 제한은 각각 별도로 등록해야 한다.

## 사용자 UI

- `기술 검증 · Development` 배지는 development에서만 표시한다.
- 카메라 상태와 debug center/zoom도 development에서만 표시한다.
- production과 release에서는 개발 배지, 카메라 진단, 원시 지도 예외를 표시하지 않는다.
- 검색, 스타일 필터, 마커, 상세 화면, 주소 복사 동작은 변경하지 않았다.

## Production 임시 검증 주의사항

현재 개발용 Supabase 프로젝트를 production runtime debug 검증에 임시 사용할 수 있다. 이는 runtime 분리 검증일 뿐 실제 production 데이터·운영 환경 승격이 아니다. 공개 출시에는 개발 데이터와 운영 권한을 분리한 별도 production Supabase 프로젝트 사용을 권장한다.

## 진단 빌드

실제 key 없이도 build 자체는 가능하다.

```bat
cd /d C:\Users\jeong\burger-map
C:\Users\jeong\flutter\bin\flutter.bat build apk --debug
C:\Users\jeong\flutter\bin\flutter.bat build appbundle --release --dart-define=APP_ENV=development --dart-define=STORE_DATA_MODE=staging
```

두 번째 명령도 release resolver에 의해 production/Supabase가 된다. Phase 5C-A에서 로컬 upload signing 구성을 준비해 signed AAB 생성을 검증했지만, Play 업로드 전에는 Play App Signing과 production 설정값을 별도로 확인해야 한다.

## Release bundle 검사

`scripts/release/verify_release_bundle.py`는 AAB/APK ZIP을 직접 열어 다음을 검사한다.

- staging JSON ZIP entry
- `AssetManifest.bin`/`AssetManifest.json`의 staging 경로
- 로컬 staging JSON에서 읽은 candidate ID와 충분한 길이의 이름·주소
- Google API key, Supabase URL, JWT, Publishable/Secret key 패턴

실제 ID, 매장명, 주소 또는 key는 출력하지 않고 검사 개수만 출력한다.

```bat
cd /d C:\Users\jeong\burger-map
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\VC\SecurityIssueAnalysis\python\python.exe" scripts\release\verify_release_bundle.py --bundle build\app\outputs\bundle\release\app-release.aab --staging-json assets\dev\yongsan_burger_stores_staging.json
```

2026-08-20 clean build 검사 결과:

- release ZIP staging entry: 0
- release AssetManifest staging 항목: 0
- 검사한 staging 식별 값: 71
- release에서 발견한 staging 식별 값: 0
- release key/URL/JWT 패턴: 0
- debug APK staging entry: 1
- debug APK에서 발견한 staging 식별 값: 71

2026-08-20 결과는 당시 실제 key가 없는 진단 build 기준이다. Phase 5C-A에서는 로컬 upload key로 새 signed release AAB를 생성했고 동일 검사에서 staging entry, AssetManifest 참조, staging 식별 값, 비밀 패턴이 모두 0건임을 다시 확인했다.

## 2026-08-21 수동 검증

사용자가 Android emulator에서 다음 세 실행 경계를 직접 확인했다.

### Development staging

- `APP_ENV=development`, `STORE_DATA_MODE=staging`
- `기술 검증 · Development` 배지 표시
- staging 매장 24개 로딩
- 버거 스타일 필터와 `PPS` 검색 + 스매시 필터 AND 조건 정상
- 상세 화면 진입과 뒤로가기 정상

### Production runtime

- `APP_ENV=production`, `STORE_DATA_MODE=staging`을 전달했지만 effective data mode는 Supabase로 고정
- pilot/staging fallback 없이 Supabase의 공개 매장 1곳만 표시
- 필터 `전체`, `클래식`과 상세 화면 `클래식`, `검수 완료` 확인
- Development 배지와 카메라 center/zoom 진단 문구 미표시
- URL, key, 원시 오류 미노출

### Production 설정 누락

- `APP_ENV=production`, `STORE_DATA_MODE=pilot`이며 Supabase 설정은 전달하지 않음
- `서비스 설정을 확인할 수 없습니다.` 표시
- pilot 3곳과 staging 24곳 모두 미표시
- Development 배지, URL, key, 원시 오류 미노출
- 설정 누락 시 Supabase 요청과 로컬 fallback이 모두 발생하지 않음

Android debug APK는 build type 특성상 `APP_ENV=production` 실행에도 staging JSON을 물리적으로 포함할 수 있다. runtime resolver가 해당 데이터를 선택하지 않으므로 production 동작 검증에는 사용할 수 있지만 외부 배포 대상은 아니다. 실제 배포 대상인 release AAB에서는 staging ZIP entry, AssetManifest 참조, staging 식별 값이 모두 0건으로 데이터 자체가 제거됐다.

## 수동 검증 CMD 명령

실제 값은 현재 CMD 세션의 환경변수에만 설정하고 명령 기록이나 문서에 적지 않는다.

### Development staging

```bat
cd /d C:\Users\jeong\burger-map
C:\Users\jeong\flutter\bin\flutter.bat run -d emulator-5554 --dart-define=APP_ENV=development --dart-define=STORE_DATA_MODE=staging --dart-define=GOOGLE_MAPS_API_KEY=%GOOGLE_MAPS_API_KEY%
```

### Development Supabase

```bat
cd /d C:\Users\jeong\burger-map
C:\Users\jeong\flutter\bin\flutter.bat run -d emulator-5554 --dart-define=APP_ENV=development --dart-define=STORE_DATA_MODE=supabase --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_PUBLISHABLE_KEY=%SUPABASE_PUBLISHABLE_KEY% --dart-define=GOOGLE_MAPS_API_KEY=%GOOGLE_MAPS_API_KEY%
```

### Production runtime debug

pilot 요청이 Supabase로 강제되는지 함께 확인한다.

```bat
cd /d C:\Users\jeong\burger-map
C:\Users\jeong\flutter\bin\flutter.bat run -d emulator-5554 --dart-define=APP_ENV=production --dart-define=STORE_DATA_MODE=pilot --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_PUBLISHABLE_KEY=%SUPABASE_PUBLISHABLE_KEY% --dart-define=GOOGLE_MAPS_API_KEY=%GOOGLE_MAPS_API_KEY%
```

### Production 설정 누락

이 명령에는 Supabase define을 전달하지 않는다. 기존 환경변수를 삭제하거나 파일을 수정할 필요가 없다.

```bat
cd /d C:\Users\jeong\burger-map
C:\Users\jeong\flutter\bin\flutter.bat run -d emulator-5554 --dart-define=APP_ENV=production --dart-define=STORE_DATA_MODE=staging
```

확인 항목은 pilot/staging 매장 미표시, 일반 설정 오류, 개발 배지와 debug center/zoom 미표시다.

## 자동 검증 범위

- development의 세 data mode
- production/release의 Supabase 강제와 로컬 data 차단
- URL·key 정규화와 invalid configuration 차단
- invalid configuration에서 로더 0회
- production 설정 오류·빈 상태·오류·재시도
- development UI 유지와 production 기술 UI 차단
- 기존 검색·필터·상세 화면 회귀
- 합성 release bundle의 entry·manifest·식별 값·key 탐지
- clean release AAB의 entry·manifest·staging 식별 값 직접 검사

최종 자동 검증은 Flutter 87개와 Python 103개 테스트, analyze 이슈 0건, debug APK와 release AAB 진단 빌드 성공으로 완료했다.

Phase 5B에서는 원격 Supabase, Google Cloud, application ID, migration, RLS, 실제 데이터와 signing 설정을 변경하지 않았다. 후속 Phase 5C-A에서 Android application ID와 release signing 안전장치를 별도로 적용했다.
