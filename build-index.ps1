param(
    [string]$Vault = '',
    [string]$Sub = '',
    [string]$Out = '',
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

if ($Version) {
    Write-Host ('试卷题库 v' + (Get-QBVersion))
    exit 0
}

# 路径：命令行 > config.json > 自动探测
$cfg = Read-QBConfig
if (-not $Vault) { $Vault = $cfg.vault }
if (-not $Sub) { $Sub = $cfg.sub }
if (-not $Vault) {
    $found = Find-QBVault
    if ($found) { $Vault = $found.vault; if (-not $Sub) { $Sub = $found.sub } }
}
if (-not $Vault) {
    Write-Host '[!] 没有配置题库路径，请先在 config.json 里填写 vault / sub'
    exit 1
}
if (-not $Sub) { $Sub = '12-试卷解析' }
$Vault = Resolve-QBPath $Vault
if (-not (Test-Path -LiteralPath $Vault)) {
    Write-Host ('[!] 找不到题库根目录：' + $Vault)
    exit 1
}
$Vault = (Resolve-Path -LiteralPath $Vault).Path.TrimEnd('\')
$SubAbs = [IO.Path]::Combine($Vault, $Sub)
if (-not (Test-Path -LiteralPath $SubAbs -PathType Container)) {
    Write-Host ('[!] 该目录下没有这个子文件夹：' + $SubAbs)
    exit 1
}
if (-not (Test-QBQuestionFolder $SubAbs)) {
    Write-Host ('[!] 这个文件夹里没有拆好的试题（*-Q*.md）：' + $SubAbs)
    Write-Host '[i] 请改 config.json 的 sub（或双击 启动题库.bat 重新选题库文件夹），不要用空文件夹建索引'
    exit 1
}

if (-not $Out) { $Out = Join-Path $PSScriptRoot 'questions.json' }

Write-Host ('[..] 试卷题库 v' + (Get-QBVersion) + ' 构建索引')
$payload = New-QBIndex -Vault $Vault -Sub $Sub -Out $Out
$m = $payload['meta']
Write-Host ('[OK] 题目 ' + $m['count'] + ' / 试卷 ' + $m['papers'] + ' / 知识点 ' + $m['knowledgeCount'] +
            ' / 跳过 ' + $m['skipped'] + ' / 耗时 ' + $m['elapsedMs'] + 'ms')
Write-Host ('[OK] 索引已写入 ' + $Out)
