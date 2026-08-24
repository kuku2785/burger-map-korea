# Phase 5C-A Android Identity와 Release Signing

## 확정 값

- Android application ID와 namespace: `com.burgermapkorea.app`
- 앱 표시 이름: `버거맵 코리아`
- MainActivity: `android/app/src/main/kotlin/com/burgermapkorea/app/MainActivity.kt`

application ID는 Play Console에 앱을 등록한 뒤 사실상 변경하기 어렵다. 이전 ID로 설치한 emulator 앱과 새 ID 앱은 Android에서 서로 다른 앱으로 인식되므로 기존 앱을 자동 업데이트하지 않고 별도로 설치된다. Dart package 이름과 iOS Bundle ID는 이번 단계에서 변경하지 않았다.

## Signing 경계

Debug build는 Android debug key를 계속 사용한다. Release task는 debug signing으로 fallback하지 않으며 다음 로컬 파일이 모두 준비됐을 때만 upload key로 서명한다.

- `android/key.properties`
- `android/app/upload-keystore.jks`

`android/key.properties`가 없거나 필수 속성이 비어 있거나 placeholder이면 release task가 조기에 실패한다. `storeFile`이 가리키는 keystore 파일이 없어도 경로와 비밀번호를 출력하지 않고 실패한다. 실제 signing 파일은 Git에서 제외되며 Codex가 생성하거나 읽지 않는다.

Upload key는 개발자가 Play Console에 AAB를 업로드할 때 사용하는 키다. Google Play App Signing key는 Google Play가 사용자에게 배포하는 APK를 서명하는 별도 키다. 두 인증서의 SHA는 다를 수 있으며 Google Maps 제한에는 실제 배포 인증서인 Play App Signing SHA도 등록해야 한다.

## Upload keystore 생성

비밀번호를 명령행 인수로 전달하지 않고 `keytool` 프롬프트에서 직접 입력한다. 비밀번호, keystore, 인증서 개인키를 ChatGPT, Codex, GitHub에 보내지 않는다.

```cmd
cd /d C:\Users\jeong\burger-map\android\app
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool`이 PATH에 없다면 설치 위치만 확인한다.

```cmd
where keytool
where java
dir "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
```

Android Studio JBR 또는 설치된 JDK의 `bin\keytool.exe`가 확인되면 해당 전체 경로를 따옴표로 감싸 위 명령의 `keytool` 대신 사용한다.

Keystore를 분실하면 앱 업데이트 배포에 문제가 생길 수 있다. 생성 후 서로 다른 암호화된 안전한 위치에 백업 2개를 보관하고 복구 절차를 기록한다.

## key.properties 작성

`android/key.properties.example`을 참고해 로컬에만 `android/key.properties`를 만든다.

```properties
storeFile=upload-keystore.jks
storePassword=REPLACE_LOCALLY
keyAlias=upload
keyPassword=REPLACE_LOCALLY
```

`REPLACE_LOCALLY`는 실제 로컬 값으로 교체해야 하며 그대로 두면 release가 실패한다. `storeFile`은 `android/app` 기준 파일명이다. 이 파일이나 실제 값을 문서·채팅·Git에 올리지 않는다.

## 인증서 SHA 확인

Upload 인증서의 SHA-1과 SHA-256은 비밀번호를 대화형으로 입력해 확인한다.

```cmd
cd /d C:\Users\jeong\burger-map\android\app
keytool -list -v -keystore upload-keystore.jks -alias upload
```

Debug SHA와 release/upload SHA는 서로 다르다. Play App Signing을 활성화한 뒤에는 Play Console의 App integrity 화면에서 배포 인증서 SHA도 별도로 확인한다.

Google Maps Android application restriction에는 다음 조합을 등록해야 한다.

- package name: `com.burgermapkorea.app`
- 로컬 release 검증용 upload 인증서 SHA-1
- Play 배포용 Play App Signing 인증서 SHA-1
- API restriction: Maps SDK for Android

사용자는 upload keystore와 `android/key.properties`를 로컬에서 직접 생성했다. 두 파일은 Git에서 제외되며 비밀번호, 인증서 fingerprint, 인증서 DN은 저장소에 기록하지 않는다. Play App Signing 설정은 Play Console에서 별도로 진행한다.

## 검증 상태

- `dart format`: 25개 파일, 변경 0
- `flutter analyze`: 이슈 0
- Flutter 테스트: 87개 통과
- Python 테스트: 112개 통과
- debug APK 빌드 성공
- APK manifest application ID: `com.burgermapkorea.app`
- signed release AAB를 새로 생성하고 `jarsigner -verify` 종료 코드 0과 `jar verified`를 확인
- self-signed 인증서, timestamp, POSIX attribute 경고는 로컬 upload keystore 특성에 따른 예상 경고이며 서명 검증 실패가 아님
- release AAB application ID: `com.burgermapkorea.app`
- release bundle 검사에서 staging JSON entry, AssetManifest staging 참조, staging 식별 값, 비밀 패턴 모두 0건
- release debug signing fallback 없음
- application ID, namespace, MainActivity package와 경로 일치
- Android label `버거맵 코리아`
- 실제 key.properties와 keystore는 존재 여부와 Git 제외만 확인했으며 내용을 읽거나 출력하지 않음

## 2026-08-24 수동 검증

사용자가 Google Maps API key의 Android application restriction에 새 package와 현재 debug 인증서 조합을 등록하고 API restriction을 Maps SDK for Android로 제한했다. 새 package로 debug 앱을 다시 설치한 뒤 development staging 모드에서 Google 지도와 매장 마커 24개가 정상 표시되는 것을 직접 확인했다. 실제 API key와 인증서 fingerprint는 저장소에 기록하지 않았다.

Play Console 출시 후에는 Play App Signing 인증서 SHA-1을 Google Maps Android application restriction에 별도로 추가해야 한다. upload key로 서명한 로컬 release 앱의 지도를 테스트할 때는 upload 인증서 SHA-1도 별도로 등록해야 한다. iOS Bundle ID와 Play Console 설정은 이번 단계 범위가 아니다.
