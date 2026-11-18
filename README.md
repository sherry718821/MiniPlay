# 미니 파티 — 함께하는 게임

HTML/CSS/JavaScript 정적 웹사이트와 Supabase 데이터베이스·실시간 통신, GitHub Pages 배포로 구성되어 있습니다.

## 이번 버전 기능
- 누구나 방을 만들 수 있으며, 방 생성자가 방장 권한을 가짐
- 초대 링크로 접속하면 코드 입력 없이 자동 입장
- 메인 화면에서 방 코드로 바로 입장 가능
- 임의 닉네임 자동 부여, 방 안에서 닉네임 변경 가능
- 게임 진행 중에도 초대 링크로 난입 가능
- 최대 인원 2~32명, 3/5/10/15/20판
- 7종 미니게임: 반응속도, 상식 퀴즈, 숫자 기억력, 암산, 컬러 센스, 숫자 예측, 단어 타이핑
- 라운드별 점수 누적 및 최종 순위
- OBS 브라우저 소스용 별도 오버레이 URL
- Supabase RPC에서 답안 검증 및 점수 계산
- Realtime Broadcast는 갱신 신호로 사용하고, 실제 상태는 인증된 RPC에서 다시 조회
- 2.5초 폴링을 보조 경로로 유지

## 1. Supabase 설정하기
프로젝트: `hihjeclauhgpoxsbyupz`

1. Supabase Dashboard에서 **SQL Editor → New query**를 엽니다.
2. `supabase/migrations/001_mini_party.sql` 전체를 붙여 넣고 Run을 누릅니다.
3. **Project Settings → API** (또는 API Keys)에서 Project URL과 `anon` / publishable public key를 확인합니다.
4. `config.js`의 `SUPABASE_URL`, `SUPABASE_ANON_KEY`를 채웁니다.
   - Project URL은 이미 `https://hihjeclauhgpoxsbyupz.supabase.co`로 입력되어 있습니다.
   - `SUPABASE_ANON_KEY`에 공개용 anon/publishable key만 입력합니다.
   - `service_role` 또는 `secret` 키를 브라우저 코드나 GitHub에 절대 넣지 마세요.
5. SQL 실행 후 Supabase의 API Settings에서 Data API가 활성화되어 있는지 확인합니다. 앱은 테이블 직접 접근이 아니라 RPC 함수만 호출합니다.

## 2. 내 컴퓨터에서 미리 실행하기
정적 파일이라 Node 서버는 필요하지 않습니다. 브라우저에서 파일을 직접 열기보다 로컬 정적 서버를 권장합니다.

```bash
python3 -m http.server 8000
```
브라우저에서 `http://localhost:8000` 접속.

## 3. GitHub Pages로 배포하기
1. GitHub에 새 빈 저장소를 만듭니다.
2. 이 프로젝트의 파일과 `.github` 폴더를 저장소 루트에 업로드합니다.
3. `config.js`의 공개 anon key가 채워졌는지 확인합니다.
4. 저장소 **Settings → Pages → Build and deployment → Source**에서 **GitHub Actions**를 선택합니다.
5. `main` 브랜치에 push하면 `.github/workflows/pages.yml`이 자동 배포합니다.
6. Actions 탭에서 배포가 성공하면 Pages 사이트 주소를 확인합니다.

`config.js`는 브라우저에 전달되는 공개 설정 파일입니다. anon key는 공개 가능한 키여야 하며, 안전성은 RLS와 함수 권한으로 보장해야 합니다.

## 4. 방송 화면 안내
1. 방 생성자가 방을 만듭니다.
2. 대기실의 **초대 링크 복사** 버튼을 눌러 친구들에게 공유합니다.
3. 현재 버전에서는 별도의 OBS 오버레이 대신 일반 게임 화면으로 참여합니다.

## 5. 보안 및 운영 안내
- 테이블 RLS를 켜고 브라우저 역할의 직접 테이블 권한을 제거했습니다. 모든 작업은 검증된 SECURITY DEFINER RPC로 수행합니다.
- 방장 토큰, 참가자 토큰, OBS 토큰은 브라우저에 저장되며 DB에는 SHA-256 해시만 저장합니다.
- Supabase anon key는 공개용 키입니다. service_role/secret 키를 사용하지 마세요.
- 현재 버전은 비회원 닉네임 세션 기반 MVP입니다. 닉네임 사칭 방지, 신고/차단, 대기열, 호스트 재접속/이관, 라운드별 자동 타임아웃, 반응속도 정밀 보정, 레이트 리밋은 운영 전 보강을 권장합니다.
- 방장은 **라운드 결과 확정 / 다음 게임** 버튼으로 라운드를 마무리합니다. 모든 참가자가 제출하면 서버가 자동으로 해당 라운드를 채점합니다.

## 파일 구성
```text
index.html
style.css
app.js
config.js
config.example.js
supabase/migrations/001_mini_party.sql
.github/workflows/pages.yml
```
