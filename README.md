# 값콕 Hub

값콕 Hub는 평가 자료를 내 컴퓨터로 모으고 분석하는 프로그램입니다. 설치 방법과 설치 스크립트를 이곳에서 공개합니다.

## 설치

설치 파일은 없습니다. 아래 명령 한 줄을 붙여 넣고 Enter를 누르면 됩니다. 같은 안내가 [gapkok.com](https://gapkok.com) 첫 화면에도 있습니다.

**Windows** (시작 메뉴에서 PowerShell을 열고 붙여 넣기)

```powershell
irm https://gapkok.com/install.ps1 | iex
```

**Mac, Linux** (터미널을 열고 붙여 넣기)

```sh
curl -fsSL https://gapkok.com/install.sh | sh
```

명령이 하는 일:

1. Hub를 실행할 Docker 엔진을 준비합니다.
   - Windows: Docker Desktop을 설치하지 않습니다. WSL에 값콕 전용 Linux를 만들고 그 안에서 Docker 엔진을 실행합니다. WSL이 없으면 관리자 권한을 물은 뒤 설치하며, 컴퓨터를 다시 시작해야 할 수 있습니다. 다시 시작한 뒤 로그인하면 설치가 이어집니다.
   - Mac: Docker Desktop이 없으면 설치합니다. 이 Mac의 비밀번호를 한 번 묻습니다.
   - Linux(Ubuntu, Debian): Docker 엔진이 없으면 설치합니다. 관리자 비밀번호를 물을 수 있습니다.
2. 값콕 Hub 관리 프로그램을 받아 내용이 올바른지 확인한 뒤 시작합니다.
3. 브라우저를 엽니다.

Mac에 Docker Desktop을 새로 설치할 때는 Docker Desktop의 사용 조건에 동의하는 것으로 설치합니다. 직원 250명 이상이거나 연 매출 1천만 달러 이상인 조직과 정부 기관은 Docker 유료 구독이 필요합니다. 자세한 내용은 [Docker Desktop 사용 조건](https://docs.docker.com/subscription/desktop-license/)에서 확인하세요.

실행되는 내용은 이 저장소의 [install.ps1](install.ps1)과 [install.sh](install.sh)에서 볼 수 있습니다. gapkok.com에서 내려가는 파일과 같은 파일입니다.

## 값콕 연결

1. 설치가 끝나고 열리는 브라우저에서 값콕에 로그인합니다.
2. 사용할 조직을 선택해 연결합니다.
3. Hub 준비가 끝나면 값콕에서 자료 수집과 분석을 시작합니다.

Hub 본체는 연결한 뒤 자동으로 내려받습니다. GitHub 계정은 필요하지 않습니다. 이미 연결된 조직의 Hub를 다른 컴퓨터로 옮길 때는 값콕의 **설정 → Hub**에서 이전 절차를 이용하세요.

## 실행과 업데이트

- 컴퓨터를 켜고 로그인하면 Hub도 함께 시작됩니다. 따로 실행할 것은 없습니다.
- Hub 업데이트는 값콕의 **설정 → Hub**에서 자동 또는 수동을 선택합니다. 진행 중인 작업이 끝난 뒤 새 버전을 적용하며, 기존 평가환경과 자료, 결과, 계정 연결은 유지합니다.
- 관리 프로그램도 같은 선택을 따라 새 버전으로 바뀝니다. 수동이면 설치 때 열린 Hub 화면에서 **업데이트 확인**을 누릅니다.

연결이나 내려받기가 멈추면 인터넷 연결을 확인한 뒤 설치 명령을 다시 실행하세요. 자료는 유지됩니다.

## 끄기와 지우기

Hub를 끄려면 Windows는 PowerShell에서 `wsl --terminate GapKok`, Mac과 Linux는 터미널에서 `docker stop gapkok-manager`를 실행합니다. 다시 켜려면 설치 명령을 다시 실행합니다.

Hub를 지우면 Hub에 모은 자료도 함께 지워집니다.

**Windows** (PowerShell)

```powershell
Remove-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run GapKokHub
wsl --unregister GapKok
```

**Mac, Linux** (터미널)

```sh
docker rm -f $(docker ps -aq --filter name=gapkok-)
docker volume rm $(docker volume ls -q --filter name=gapkok-)
rm -f ~/Library/LaunchAgents/com.gapkok.hub.plist
```
