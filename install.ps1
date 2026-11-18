# 값콕 Hub 설치 (Windows). WSL에 값콕 전용 Linux를 두고, 그 안의 Docker 엔진으로 Hub 관리 컨테이너를 시작한다.
# 붙여 넣어 실행하는 스크립트라 cmdlet과 기본 명령만 쓴다.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $version = '2026.11.18.1'
    $base = 'https://gapkok.com'
    $image = 'gapkok/manager:' + $version
    $name = 'GapKok'
    $linux = '9b6501b926b1cd7deb8ae5d79fad27b3a47bc19622521e139822a521edfcc2d1'
    $manager = '85d4dc3717051ef6101af18a450ddb516d91ed922191f1aaf54bb0bf35f7309b'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $linux = 'ece7f46ff76c7345e3aac30967564fa19394682337844f86ded50801976238b0'; $manager = '525485b25854c852f2219a1676c7cf065f6e9a1e413d44b78a73828c34e7791e' }
    # WSL 구성 요소. 창 없이 Linux 명령을 실행한다.
    $hold = Join-Path $env:ProgramFiles 'WSL\wslg.exe'
    # WSL과 Linux가 내는 글을 UTF-8로 읽는다.
    $env:WSL_UTF8 = '1'
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

    # 값콕 Linux 안에서 명령 하나를 실행한다.
    function Run {
        $ErrorActionPreference = 'Continue'
        & wsl.exe --distribution $name --user root --cd / --exec @args
    }

    # 설치되지 않은 PC에서는 wsl --status가 입력을 기다리므로 시간을 정해 확인한다.
    $probe = Start-Process -FilePath 'wsl.exe' -ArgumentList '--status' -WindowStyle Hidden -PassThru
    $null = $probe.Handle
    $probe | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
    if ($probe.HasExited) { $wsl = $probe.ExitCode -eq 0 } else { $probe | Stop-Process -Force; $wsl = $false }
    # Windows에 기본으로 들어 있는 예전 WSL에는 이 구성 요소가 없어 새 WSL을 설치한다.
    if (-not (Test-Path -LiteralPath $hold)) { $wsl = $false }

    $fresh = $false
    if (-not $wsl) {
        Write-Host 'WSL을 설치합니다. 관리자 권한을 묻는 창에서 예를 누르세요.'
        $setup = Start-Process -FilePath 'wsl.exe' -ArgumentList '--install', '--no-distribution', '--web-download' `
            -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        if ($setup.ExitCode -ne 0 -and $setup.ExitCode -ne 3010) { throw 'WSL 설치를 완료하지 못했습니다. 같은 명령을 다시 실행하세요.' }
        $fresh = $true
    }

    $known = Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
        Where-Object { $_.GetValue('DistributionName') -eq $name }
    if (-not $known) {
        Write-Host '값콕 Hub용 Linux를 받습니다.'
        $file = Join-Path $env:TEMP ('gapkok-linux-' + $linux + '.tar.gz')
        Invoke-WebRequest -UseBasicParsing ($base + '/hub/manager/' + $linux + '.tar.gz') -OutFile $file
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash -ne $linux) {
            Remove-Item -LiteralPath $file -Force
            throw '받은 파일이 올바르지 않습니다. 같은 명령을 다시 실행하세요.'
        }
        $folder = Join-Path $env:LOCALAPPDATA 'GapKok\wsl'
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        $ErrorActionPreference = 'Continue'
        $said = (& wsl.exe --import $name $folder $file --version 2 2>&1 | Out-String).Trim()
        $imported = $LASTEXITCODE -eq 0
        $ErrorActionPreference = 'Stop'
        Remove-Item -LiteralPath $file -Force
        if (-not $imported) {
            if ($fresh) {
                # WSL을 막 설치했으면 다시 시작해야 쓸 수 있다. 로그인하면 같은 설치를 한 번 이어서 실행한다.
                New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'GapKokHubInstall' -Force `
                    -Value ('powershell.exe -NoProfile -NoExit -Command "irm ' + $base + '/install.ps1 | iex"') | Out-Null
                Write-Host '컴퓨터를 다시 시작하면 설치를 이어갑니다.'
                return
            }
            throw ('Hub용 Linux를 준비하지 못했습니다. WSL의 응답: ' + $said)
        }
    }

    # 로그인할 때 창 없이 값콕 Linux를 켜고, 로그인해 있는 동안 WSL이 끄지 않도록 붙어 있는다.
    # wslg.exe는 --exec를 모르면 사용법 창을 띄우고 끝나므로 --shell-type none과 --로 명령을 넘긴다.
    $holding = @('--distribution', $name, '--user', 'root', '--cd', '/', '--shell-type', 'none', '--', '/bin/sleep', 'infinity')
    New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'GapKokHub' -Force `
        -Value ('"' + $hold + '" ' + ($holding -join ' ')) | Out-Null
    $held = Get-CimInstance Win32_Process -Filter "Name='wslg.exe'" |
        Where-Object { $_.CommandLine -like ('*--distribution ' + $name + ' *') }
    if (-not $held) { Start-Process -FilePath $hold -ArgumentList $holding }

    Write-Host 'Docker 엔진이 준비되기를 기다립니다.'
    $waited = 0
    while ((Run docker info --format '{{.OSType}}' 2>$null) -ne 'linux') {
        $waited += 3
        if ($waited -gt 300) {
            throw ('Docker 엔진이 시작되지 않았습니다. 컴퓨터를 다시 시작한 뒤 같은 명령을 다시 실행하세요. 응답: ' + ((Run docker info 2>&1) | Out-String).Trim())
        }
        Start-Sleep -Seconds 3
    }

    Run docker image inspect $image *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '값콕 Hub를 받습니다.'
        $file = '/var/tmp/gapkok-manager.tar.gz'
        Run curl --fail --silent --show-error --location --proto '=https' --output $file ($base + '/hub/manager/' + $manager + '.tar.gz')
        $got = [string](Run sha256sum $file)
        if ($got.Split(' ')[0] -ne $manager) {
            Run rm -f $file
            throw '받은 파일이 올바르지 않습니다. 같은 명령을 다시 실행하세요.'
        }
        Run docker load --quiet --input $file | Out-Null
        $loaded = $LASTEXITCODE -eq 0
        Run rm -f $file
        if (-not $loaded) { throw '값콕 Hub를 준비하지 못했습니다. 같은 명령을 다시 실행하세요.' }
    }

    $url = Run docker run --rm --env ('GAPKOK_HOST_NAME=' + $env:COMPUTERNAME) `
        --volume /var/run/docker.sock:/var/run/docker.sock $image install
    if ($LASTEXITCODE -ne 0 -or -not $url) { throw '값콕 Hub를 시작하지 못했습니다. 같은 명령을 다시 실행하세요.' }
    $url = [string]($url | Select-Object -Last 1)
    Write-Host ('값콕 Hub를 설치했습니다. 브라우저에서 조직을 연결하세요: ' + $url)
    Start-Process $url
}
