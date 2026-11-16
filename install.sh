#!/bin/sh
# 값콕 Hub 설치 (Mac, Linux). Docker를 준비하고 Hub 관리 컨테이너를 시작한다.
set -eu
version='2026.11.16.1'
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
        /usr/bin/osascript -e 'on run argv' \
            -e 'do shell script "/usr/bin/ditto " & quoted form of item 1 of argv & " /Applications/Docker.app" with administrator privileges' \
            -e 'end run' "$cache/mount/Docker.app"
    fi
    open -g -a /Applications/Docker.app
    docker=/Applications/Docker.app/Contents/Resources/bin/docker
    echo 'Docker가 준비되기를 기다립니다. Docker 창이 뜨면 안내에 따라 주세요.'
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
        exit 1
    fi
    sleep 3
done

if ! $docker image inspect "$image" >/dev/null 2>&1; then
    echo '값콕 Hub를 받습니다.'
    case "$($docker info --format '{{.Architecture}}')" in
        aarch64|arm64) sum='e1cdaf3062415ffbe0473adae7999d13dacdc75dd454c4b3940746d065458cf4';;
        x86_64|amd64) sum='39c72a34160e07981fa27281c906956cf518a1a205dd3c8d9f335576cd94963b';;
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
