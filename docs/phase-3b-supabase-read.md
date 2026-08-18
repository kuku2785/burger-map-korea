# Phase 3B Supabase 공개 매장 조회

## 범위

Phase 3B는 Flutter development 환경에서 Supabase `stores` 테이블의 공개 매장을 읽는 경로만 추가한다. Supabase Auth, 로그인, 관리자 기능, 데이터 쓰기, 실제 매장 업로드는 포함하지 않는다.

## 패키지

- `supabase_flutter: ^2.17.2`

프로젝트의 Dart 3.12.2 환경에서 dependency resolution과 Android debug build를 검증한다.

## 데이터 모드

- `pilot`: 기본값. 기존 이태원 파일럿 데이터를 사용한다.
- `staging`: development에서만 로컬 24개 staging asset을 사용한다.
- `supabase`: development에서만 Supabase 공개 데이터를 조회한다.

production 환경 또는 release 빌드에서 `STORE_DATA_MODE=supabase`를 요청하면 기존 안전 정책에 따라 `pilot`으로 돌아간다. Supabase 모드를 production 기본값으로 사용하지 않는다.

## 공개 설정

Supabase 모드에는 다음 dart-define 두 개가 모두 필요하다.

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

값은 소스, 테스트, 문서, Git에 기록하지 않는다. secret key, service-role key, DB 비밀번호, connection string을 Flutter에 전달하는 입력 경로는 제공하지 않는다.

`SUPABASE_URL`에는 프로젝트 기본 URL만 설정한다.

```text
https://<project-ref>.supabase.co
```

`/rest/v1` 같은 API 경로를 덧붙이지 않는다. Supabase SDK가 REST 경로를 내부에서 구성하므로 기본 URL에 `/rest/v1`이 포함되면 잘못된 중복 경로로 요청하게 된다.

## 조회 정책

Flutter는 `stores`에서 다음 필드만 SELECT한다.

```text
id,name,address,latitude,longitude,burger_style,verification_status
```

클라이언트 쿼리에도 다음 조건과 정렬을 명시한다.

```text
verification_status = verified
is_active = true
order by name ascending
```

RLS가 같은 공개 조건을 강제한다. INSERT, UPDATE, DELETE, UPSERT, RPC 호출은 구현하지 않는다.

## 화면 상태

- 설정 누락: 누락된 환경변수 이름만 표시한다.
- 조회 중: 로딩 표시를 유지한다.
- 0행: `현재 공개된 매장이 없습니다.`를 표시하고 pilot/staging으로 대체하지 않는다.
- 오류: URL, key, 서버 응답 원문을 숨기고 일반 오류와 재시도 버튼을 표시한다.
- 성공: 조회 결과만 기존 지도 마커와 상세 카드에 전달한다.

## Windows CMD 실행

실제 값은 현재 CMD 세션의 환경변수에만 설정한다.

```bat
cd /d C:\Users\jeong\burger-map
set "SUPABASE_URL=로컬에서_설정한_Project_URL"
set "SUPABASE_PUBLISHABLE_KEY=로컬에서_설정한_Publishable_Key"
C:\Users\jeong\flutter\bin\flutter.bat run -d emulator-5554 --dart-define=APP_ENV=development --dart-define=STORE_DATA_MODE=supabase --dart-define=SUPABASE_URL=%SUPABASE_URL% --dart-define=SUPABASE_PUBLISHABLE_KEY=%SUPABASE_PUBLISHABLE_KEY% --dart-define=GOOGLE_MAPS_API_KEY=%GOOGLE_MAPS_API_KEY%
```

Google Maps 키가 Gradle property 등 기존 로컬 설정으로 주입된다면 마지막 Google Maps dart-define은 생략할 수 있다.

## 실제 연결 검증

2026-08-18 Android `emulator-5554`에서 development + supabase 모드의 실제 연결을 검증했다.

- 초기 실패 원인: `SUPABASE_URL`에 `/rest/v1`이 포함되어 SDK가 잘못된 REST 경로를 생성했다.
- 수정: `SUPABASE_URL`을 프로젝트 기본 URL 형식으로 변경했다.
- 결과: RLS가 적용된 빈 `stores` 테이블 조회에 성공했고 `현재 공개된 매장이 없습니다.` 화면이 정상 표시됐다.
- 확인 범위: Publishable Key 기반 읽기 연결, 0행 응답, 정상 빈 상태 처리.
- 미수행: 실제 매장 데이터 업로드, INSERT/UPDATE/DELETE, Auth, 원격 스키마 변경.

실제 Project URL, 프로젝트 식별자, Publishable Key 및 기타 비밀정보는 문서와 저장소에 기록하지 않았다.

## 안전한 오류 진단

development debug 빌드에서만 Supabase 로더의 실패 단계와 안전한 오류 코드가 출력된다. URL, 키, 요청 헤더, 서버 응답 원문은 출력하지 않는다. production/release에서는 진단 로그가 비활성화된다.
