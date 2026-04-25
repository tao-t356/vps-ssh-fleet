$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$inventoryExample = Join-Path $repoRoot 'inventory\hosts.csv.example'
$inventoryFile = Join-Path $repoRoot 'inventory\hosts.csv'
$generatedConfig = Join-Path $repoRoot 'generated\ssh_config'
$privateKey = Join-Path $HOME '.ssh\id_ed25519'
$privateKeyDir = Split-Path -Parent $privateKey

function Get-DefaultGitHubUser {
    $defaultUser = $env:GITHUB_USER
    if ($defaultUser) {
        return $defaultUser
    }

    try {
        $origin = (git -C $repoRoot remote get-url origin 2>$null).Trim()
        if ($origin -match 'github\.com[:/](?<owner>[^/]+)/') {
            return $matches.owner
        }
    } catch {
    }

    return ''
}

if (-not (Test-Path $inventoryFile)) {
    Copy-Item $inventoryExample $inventoryFile
    Write-Host ''
    Write-Host '已为你生成: inventory\hosts.csv'
    Write-Host '先把 VPS IP / 用户填进去，再重新运行这个脚本。'
    Write-Host ''
    Write-Host "文件位置: $inventoryFile"
    exit 0
}

$defaultGitHubUser = Get-DefaultGitHubUser
$githubUser = Read-Host "GitHub 用户名 [$defaultGitHubUser]"
if (-not $githubUser) {
    $githubUser = $defaultGitHubUser
}

if (-not $githubUser) {
    throw 'GitHub 用户名不能为空。'
}

$jshook = Read-Host 'jshook（当前环境需要，留空则不带）'

if (-not (Test-Path $privateKey)) {
    if (-not (Test-Path $privateKeyDir)) {
        New-Item -ItemType Directory -Force -Path $privateKeyDir | Out-Null
    }

    $generate = Read-Host "未找到本地私钥，立即生成 $privateKey ? [Y/n]"
    if ($generate -match '^(|y|Y)$') {
        ssh-keygen -t ed25519 -f $privateKey -C "$githubUser@vps-ssh-fleet"
        Write-Host ''
        Write-Host '请先把下面这个公钥上传到你的 GitHub 账号，然后再运行一次脚本：'
        Write-Host "$privateKey.pub"
        exit 0
    } else {
        throw '没有本地私钥，已停止。'
    }
}

$passwordPrompt = Read-Host '是否统一输入一次 SSH 密码给所有空白 password 行？[Y/n]'
$defaultPassword = ''
if ($passwordPrompt -match '^(|y|Y)$') {
    $secure = Read-Host 'SSH 密码' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $defaultPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$disablePasswordAnswer = Read-Host '验证成功后顺手关闭密码登录？[y/N]'

Push-Location $repoRoot
try {
    python -m pip install -r requirements.txt

    $arguments = @(
        'scripts/enable_github_key_login.py'
        '--inventory', $inventoryFile
        '--source', 'github'
        '--github-user', $githubUser
        '--private-key', $privateKey
        '--output-ssh-config', $generatedConfig
        '--mode', 'merge'
    )

    if ($jshook) {
        $arguments += @('--jshook', $jshook)
    }

    if ($defaultPassword) {
        $arguments += @('--default-password', $defaultPassword)
    }

    if ($disablePasswordAnswer -match '^(y|Y)$') {
        $arguments += '--disable-password'
    }

    python @arguments

    Write-Host ''
    Write-Host '完成。你现在可以这样连接：'
    Write-Host "ssh -F `"$generatedConfig`" hk-1"
} finally {
    Pop-Location
}
