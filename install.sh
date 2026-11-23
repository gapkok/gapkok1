#!/bin/sh
# 값콕 Hub 설치 (Mac, Linux). Docker를 준비해 로그인할 때 켜지게 하고 Hub 관리 컨테이너를 시작한다.
set -eu
version='2026.11.23.2'
base='https://gapkok.com'
image="gapkok/manager:$version"

if [ "$(uname -s)" = Darwin ]; then
    if [ ! -d /Applications/Docker.app ]; then
        echo 'Docker를 설치합니다.'
        case "$(uname -m)" in arm64) arch=arm64;; x86_64) arch=amd64;; *) echo '지원하지 않는 컴퓨터입니다.' >&2; exit 1;; esac
        cache=$(mktemp -d -t gapkok-setup)
        trap 'hdiutil detach "$cache/mount" >/dev/null 2>&1 || true; rm -rf "$cache"' EXIT
        curl --fail --location --proto '=https' --tlsv1.2 "https://desktop.docker.com/mac/main/$arch/Docker.dmg" -o "$cache/Docker.dmg"
        mkdir "$cache/mount"
        hdiutil attach "$cache/Docker.dmg" -mountpoint "$cache/mount" -nobrowse >/dev/null
        codesign --verify --deep --strict "$cache/mount/Docker.app"
        codesign -dv "$cache/mount/Docker.app" 2>&1 | grep -q 'TeamIdentifier=9BNSXJN65R'
        echo '이 Mac의 비밀번호를 묻는 창이 열리면 입력하세요.'
        # Docker's installer accepts its agreement and does the admin setup now, so Docker opens without asking again.
        /usr/bin/osascript -e 'on run argv' \
            -e 'do shell script quoted form of item 1 of argv & " --accept-license --user=" & quoted form of item 2 of argv with administrator privileges' \
            -e 'end run' "$cache/mount/Docker.app/Contents/MacOS/install" "$(id -un)"
    fi
    # Docker does not start at login by default; this keeps the Hub running after a restart.
    mkdir -p "$HOME/Library/LaunchAgents"
    cat >"$HOME/Library/LaunchAgents/com.gapkok.hub.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.gapkok.hub</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>-j</string><string>-a</string><string>Docker</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
EOF
    docker=/Applications/Docker.app/Contents/Resources/bin/docker
    if ! $docker info >/dev/null 2>&1; then
        open -g -j -a /Applications/Docker.app
        echo 'Docker가 준비되기를 기다립니다.'
    fi
else
    root=''
    [ "$(id -u)" = 0 ] || root=sudo
    if ! command -v docker >/dev/null 2>&1; then
        echo 'Docker를 설치합니다.'
        . /etc/os-release
        case "$ID" in ubuntu|debian) ;; *) echo 'Ubuntu 또는 Debian을 사용하세요.' >&2; exit 1;; esac
        $root sh -eu -c '
            apt-get update
            apt-get install -y ca-certificates curl
            install -m 0755 -d /etc/apt/keyrings
            curl --fail --proto "=https" "https://download.docker.com/linux/$1/gpg" -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            printf "Types: deb\nURIs: https://download.docker.com/linux/%s\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n" "$1" "$2" "$(dpkg --print-architecture)" >/etc/apt/sources.list.d/docker.sources
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io
            systemctl enable --now docker
        ' sh "$ID" "${UBUNTU_CODENAME:-$VERSION_CODENAME}" </dev/null
    fi
    docker=docker
    docker info >/dev/null 2>&1 || docker="$root docker"
fi

waited=0
until [ "$($docker info --format '{{.OSType}}' 2>/dev/null)" = linux ]; do
    waited=$((waited + 3))
    if [ "$waited" -gt 900 ]; then
        echo 'Docker가 시작되지 않았습니다. Docker를 연 뒤 같은 명령을 다시 실행하세요.' >&2
        $docker info 2>&1 | tail -n 1 >&2 || true
        exit 1
    fi
    [ $((waited % 30)) -ne 0 ] || echo 'Docker 창에 동의, 로그인, 업데이트 화면이 있으면 진행해 주세요. 계속 기다립니다.'
    sleep 3
done

if ! $docker image inspect "$image" >/dev/null 2>&1; then
    echo '값콕 Hub를 받습니다.'
    case "$($docker info --format '{{.Architecture}}')" in
        aarch64|arm64) sum='b57f76ee3c86c7309d9a7f51850d36e2a3f85d692ba0f5a97f25ef0d9049ec45';;
        x86_64|amd64) sum='74f9daabbe2100ec86a15085c68d6092ba573e3b01b600798097b7fcdd3bb792';;
        *) echo '지원하지 않는 컴퓨터입니다.' >&2; exit 1;;
    esac
    file=$(mktemp)
    curl --fail --location --proto '=https' --tlsv1.2 "$base/hub/manager/$sum.tar.gz" -o "$file"
    if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$file"); else got=$(shasum -a 256 "$file"); fi
    if [ "${got%% *}" != "$sum" ]; then
        rm -f "$file"
        echo '받은 파일이 올바르지 않습니다. 다시 실행하세요.' >&2
        exit 1
    fi
    $docker load --quiet --input "$file" >/dev/null
    rm -f "$file"
fi

url=$($docker run --rm --env "GAPKOK_HOST_NAME=$(hostname)" \
    --volume /var/run/docker.sock:/var/run/docker.sock "$image" install </dev/null)
echo "값콕 Hub를 설치했습니다. 브라우저에서 조직을 연결하세요: $url"
if [ "$(uname -s)" = Darwin ]; then open "$url"; else xdg-open "$url" >/dev/null 2>&1 || true; fi
