# Android 네이티브 Google 로그인 검증 메모

앱의 Google 버튼은 `google_sign_in` 7.2.0의 Android 계정 선택 UI로 토큰을 얻고, Supabase `signInWithIdToken` 응답에서 실제 세션이 만들어진 뒤에만 로그인으로 처리한다. 외부 브라우저 OAuth는 Google 버튼 경로에서 사용하지 않는다. 기존 이메일 Magic Link 딥링크는 유지한다. Google 버튼은 `GOOGLE_SIGN_IN_ENABLED=true`와 `GOOGLE_WEB_CLIENT_ID`가 모두 설정된 빌드에서만 보인다.

외부 설정 및 확인:

1. 현재 Android `applicationId`는 `com.burgermapkorea.app`이다. 이번 `signingReport`에서 확인한 debug SHA-1은 `91:C0:F9:F3:3A:0B:27:5A:82:4D:86:0B:B8:CB:BC:80:48:47:67:E1`이다. 이 패키지명과 각 서명 인증서의 SHA-1을 Google Cloud Android OAuth 클라이언트에 등록한다. release, Play App Signing 인증서는 별도로 확인한다.
2. Google Cloud Web OAuth 클라이언트 ID를 앱의 `GOOGLE_WEB_CLIENT_ID` Dart define으로 전달한다. 이는 `google_sign_in`의 `serverClientId`다. Web Client Secret은 앱, `.env`, 빌드 인자, Git에 넣지 않는다.
3. 실제 운영 Supabase 프로젝트의 Google 제공자에 Web OAuth 클라이언트 ID와 Secret을 Dashboard에서 설정한다. Secret은 Supabase Dashboard에만 보관한다.
4. Supabase Google 제공자를 활성화한 뒤, `GOOGLE_SIGN_IN_ENABLED=true`로 Android 빌드를 만들어 계정 선택 → 토큰 교환 → Supabase 세션 → 지도 복귀를 실기기에서 확인한다. 계정 선택 취소·인증 실패·네트워크 오류 후 Guest 지도와 Magic Link를 확인한다.
5. 기존 계정, 신규 계정의 프로필 없음, 앱 재시작 세션 복원, 로그아웃 및 로컬 즐겨찾기 보존을 검증한다. release 및 Play 설치본은 별도 서명으로 다시 검증한다.

Google 제공자와 Android OAuth 설정이 확인되기 전에는 Google 버튼을 켠 빌드를 배포하지 않는다. 현재 실기기 Google 로그인 E2E는 미실시다.
