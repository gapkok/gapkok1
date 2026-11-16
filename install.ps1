# 값콕 Hub 설치 (Windows). WSL과 Docker를 준비하고 Hub 관리 컨테이너를 시작한다.
# 붙여 넣어 실행하는 스크립트라 cmdlet과 기본 명령만 쓴다.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $version = '2026.11.16.1'
    $base = 'https://gapkok.com'
    $image = 'gapkok/manager:' + $version
    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    $docker = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'

    function Ready {
        if (-not (Test-Path $docker)) { return $false }
        $ErrorActionPreference = 'SilentlyContinue'
        $system = & $docker info --format '{{.OSType}}' 2>$null
        return ($LASTEXITCODE -eq 0 -and $system -eq 'linux')
    }

    # 설치되지 않은 PC에서는 wsl --status가 입력을 기다리므로 시간을 정해 확인한다.
    $probe = Start-Process -FilePath 'wsl.exe' -ArgumentList '--status' -WindowStyle Hidden -PassThru
    $null = $probe.Handle
    $probe | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
    if ($probe.HasExited) { $wsl = $probe.ExitCode -eq 0 } else { $probe | Stop-Process -Force; $wsl = $false }

    $steps = ''
    if (-not $wsl) {
        $steps += '$p = Start-Process wsl.exe -ArgumentList ''--install'',''--no-distribution'',''--web-download'' -WindowStyle Hidden -Wait -PassThru; '
        $steps += 'if ($p.ExitCode -eq 3010) { $r = 3010 } elseif ($p.ExitCode -ne 0) { exit 1 }; '
    }
    if (-not (Test-Path $desktop)) {
        Write-Host 'Docker를 받습니다.'
        $arch = 'amd64'
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'arm64' }
        $installer = Join-Path $env:TEMP 'GapKok Docker Desktop Installer.exe'
        Invoke-WebRequest -UseBasicParsing ('https://desktop.docker.com/win/main/' + $arch + '/Docker%20Desktop%20Installer.exe') -OutFile $installer
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Docker Inc') {
            Remove-Item -LiteralPath $installer -Force
            throw 'Docker 설치 파일의 서명을 확인하지 못했습니다.'
        }
        $steps += '$p = Start-Process -FilePath ''' + $installer.Replace("'", "''") + ''' -ArgumentList ''install'',''--quiet'',''--backend=wsl-2'',''--no-windows-containers'' -Wait -PassThru; '
        $steps += 'if ($p.ExitCode -eq 3010) { $r = 3010 } elseif ($p.ExitCode -ne 0) { exit 2 }; '
    }
    if ($steps) {
        Write-Host 'WSL과 Docker를 설치합니다. 관리자 권한을 묻는 창에서 예를 누르세요.'
        $setup = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -Wait -PassThru `
            -ArgumentList @('-NoProfile', '-Command', ('$r = 0; ' + $steps + 'exit $r'))
        if ($installer) { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }
        if ($setup.ExitCode -eq 3010) {
            # 다시 시작한 뒤 로그인하면 같은 설치를 한 번 이어서 실행한다.
            New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'GapKokHubInstall' -Force `
                -Value ('powershell.exe -NoProfile -NoExit -Command "irm ' + $base + '/install.ps1 | iex"') | Out-Null
            Write-Host '컴퓨터를 다시 시작하면 설치를 이어갑니다.'
            return
        }
        if ($setup.ExitCode -ne 0) { throw 'WSL 또는 Docker 설치를 완료하지 못했습니다. 같은 명령을 다시 실행하세요.' }
    }

    if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) { Start-Process -FilePath $desktop }
    Write-Host 'Docker가 준비되기를 기다립니다. Docker 창이 뜨면 안내에 따라 주세요.'
    $waited = 0
    while (-not (Ready)) {
        $waited += 3
        if ($waited -gt 900) { throw 'Docker가 시작되지 않았습니다. Docker Desktop을 연 뒤 같은 명령을 다시 실행하세요.' }
        Start-Sleep -Seconds 3
    }

    $ErrorActionPreference = 'Continue'
    & $docker image inspect $image *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '값콕 Hub를 받습니다.'
        $sum = '39c72a34160e07981fa27281c906956cf518a1a205dd3c8d9f335576cd94963b'
        if ((& $docker info --format '{{.Architecture}}') -match 'aarch64|arm64') { $sum = 'e1cdaf3062415ffbe0473adae7999d13dacdc75dd454c4b3940746d065458cf4' }
        $file = Join-Path $env:TEMP ('gapkok-manager-' + $version + '.tar.gz')
        Invoke-WebRequest -UseBasicParsing ($base + '/hub/manager/' + $sum + '.tar.gz') -OutFile $file
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash -ne $sum) {
            Remove-Item -LiteralPath $file -Force
            throw '받은 파일이 올바르지 않습니다. 같은 명령을 다시 실행하세요.'
        }
        & $docker load --quiet --input $file | Out-Null
        Remove-Item -LiteralPath $file -Force
        if ($LASTEXITCODE -ne 0) { throw '값콕 Hub를 준비하지 못했습니다. 같은 명령을 다시 실행하세요.' }
    }

    $url = & $docker run --rm --env ('GAPKOK_HOST_NAME=' + $env:COMPUTERNAME) `
        --volume /var/run/docker.sock:/var/run/docker.sock $image install
    if ($LASTEXITCODE -ne 0 -or -not $url) { throw '값콕 Hub를 시작하지 못했습니다. 같은 명령을 다시 실행하세요.' }
    Write-Host ('값콕 Hub를 설치했습니다. 브라우저에서 조직을 연결하세요: ' + $url)
    Start-Process $url
}
