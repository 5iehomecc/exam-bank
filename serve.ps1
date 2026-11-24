param(
    [string]$Vault = '',
    [string]$Sub = '',
    [int]$Port = 0,
    [switch]$NoOpen,
    [switch]$Rebuild,
    [int]$IdleExit = 0,
    [switch]$NoPrompt,
    [switch]$NoPick,
    [switch]$Version
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

$QBVersion = Get-QBVersion
if ($Version) {
    Write-Host ('试卷题库 v' + $QBVersion)
    exit 0
}
try { $Host.UI.RawUI.WindowTitle = ('试卷题库 v' + $QBVersion) } catch { }

$ByeGrace = 8
# /vault/ 允许对外提供的扩展名（试题 md + 本地化图片），其余一律 403
$script:VaultExt = @('.md', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp', '.pdf')
Write-Host ('[..] 试卷题库 v' + $QBVersion)

# ---- 题库路径：命令行 -Vault/-Sub > 交互确认（config.json / 选择框）> 自动探测 ----
$cfg = Read-QBConfig
# 写回配置时只用「配置层」的值，不把本次命令行的临时参数固化进去
$CfgPort = if ($cfg.port -gt 0) { $cfg.port } else { 8787 }
$CfgIdle = if ($cfg.idleExit -gt 0) { $cfg.idleExit } else { 300 }
if ($Port -le 0) { $Port = $CfgPort }
if ($IdleExit -le 0) { $IdleExit = $CfgIdle }

function Read-Key-Timeout {
    # 等一个按键；$Seconds<=0 表示一直等；没有可用控制台（输入被重定向）时返回 ''
    param([int]$Seconds = 5)
    if ($Seconds -gt 0) { $end = [datetime]::Now.AddSeconds($Seconds) } else { $end = [datetime]::MaxValue }
    while ([datetime]::Now -lt $end) {
        try { $has = [Console]::KeyAvailable } catch { return '' }
        if ($has) {
            $k = [Console]::ReadKey($true)
            return ([string]$k.KeyChar)
        }
        Start-Sleep -Milliseconds 80
    }
    return ''
}

function Select-QBValidFolder {
    # 反复让用户选，直到选中「里面有拆好 *-Q*.md」的那一层。
    # 选到空文件夹时只接受 R 重选 / Q 退出，没有「超时默认继续」，免得挂上空路径进旧索引。
    param([string]$Initial = '')
    $hint = $Initial
    while ($true) {
        if ($NoPick) { return $null }
        $pick = Select-QBFolder $hint
        if (-not $pick) { return $null }      # 选择框里点了取消
        $full = ''
        try { $full = (Resolve-Path -LiteralPath $pick).Path.TrimEnd('\') } catch { }
        if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Container)) {
            Write-Host ('[!] 不是有效文件夹：' + $pick)
            $hint = $Initial
            continue
        }
        $parent = Split-Path -Parent $full
        $leaf = Split-Path -Leaf $full
        if (-not $parent -or $parent -eq $full -or -not $leaf -or $parent.Length -le 2) {
            Write-Host '[!] 请选具体的题库文件夹，不要选整个磁盘'
            $hint = $Initial
            continue
        }
        if (Test-QBQuestionFolder $full) { return $full }

        Write-Host ('[!] 这个文件夹里没有拆好的试题（*-Q*.md）：' + $full)
        Write-Host '[i] 要选的是「放独立试题 md」的那一层，通常下面还有 初中数学 / 初中物理 这样的子文件夹'
        if ($NoPrompt -or $NoPick) { return $null }
        Write-Host '[?] 重新选择请按 R，退出请按 Q（这里没有默认选项，需要你明确选）'
        while ($true) {
            $k = Read-Key-Timeout 0
            if ($k -match '^[rR]$') { $hint = $full; break }
            if ($k -match '^[qQ]$') { return $null }
            if ($k -eq '') { return $null }
            Write-Host '[?] 请按 R 重新选择，或按 Q 退出'
        }
    }
}

function Save-QBFolder {
    # 只做「已校验过的路径 → 写入 config.json」（vault=父目录, sub=文件夹原名）
    param([string]$Full)
    $parent = Split-Path -Parent $Full
    $leaf = Split-Path -Leaf $Full
    [void](Save-QBConfig -Vault $parent -Sub $leaf -Port $CfgPort -IdleExit $CfgIdle)
    Write-Host ('[OK] 已记住这个题库：' + $Full)
    return @{ vault = $parent; sub = $leaf; path = $Full }
}

$VaultSrc = $Vault
if ($VaultSrc) {
    # 命令行显式指定，全程不交互
    if (-not $Sub) { if ($cfg.sub) { $Sub = $cfg.sub } else { $Sub = '12-试卷解析' } }
} else {
    # 只配了库根、没配 sub，等于没配（否则会把整个库根当题库，sub 又落到默认值上）
    if ($cfg.vault -and -not $cfg.sub) { $cfg.vault = '' }
    $candPath = ''
    $candV = ''
    $candS = $cfg.sub
    if ($cfg.vault) {
        $candV = Resolve-QBPath $cfg.vault
        if ($candS) { $candPath = [IO.Path]::Combine($candV, $candS) } else { $candPath = $candV }
    }

    if ($candPath -and (Test-Path -LiteralPath $candPath -PathType Container) -and (Test-QBQuestionFolder $candPath)) {
        # 有配置且有效：问一句就用，5 秒不操作按「用上次的」
        $use = $true
        if (-not $NoPrompt) {
            Write-Host ('[i] 上次的题库：' + $candPath)
            Write-Host '[?] 用它打开题库？（回车 / Y 打开 · N 换一个文件夹，5 秒默认用上次的）'
            $k = Read-Key-Timeout 5
            if ($k -match '^[nN]$') { $use = $false }
        }
        if ($use) {
            $VaultSrc = $candV
            $Sub = $candS
            Write-Host '[i] 使用上次的题库'
        } else {
            $full = Select-QBValidFolder $candPath
            $res = if ($full) { Save-QBFolder $full } else { $null }
            if ($res) {
                $VaultSrc = $res.vault
                $Sub = $res.sub
            } else {
                Write-Host '[i] 没换成，继续用上次的题库'
                $VaultSrc = $candV
                $Sub = $candS
            }
        }
    } elseif ($candPath) {
        # 有配置但用不上：路径不存在 → 说找不到；路径在但没有试题 → 说这里没有题
        if (Test-Path -LiteralPath $candPath -PathType Container) {
            Write-Host ('[!] 这个文件夹里没有拆好的试题（*-Q*.md）：' + $candPath)
        } else {
            Write-Host ('[!] 上次记录的题库找不到了：' + $candPath)
        }
        Write-Host '[..] 请重新选一次题库文件夹'
        $full = Select-QBValidFolder $candPath
        $res = if ($full) { Save-QBFolder $full } else { $null }
        if ($res) {
            $VaultSrc = $res.vault
            $Sub = $res.sub
        } else {
            Write-Host '[!] 没有选到可用的文件夹，旧路径也用不了，先退出'
            Write-Host ('[i] 也可以手动改 ' + (Get-QBConfigPath) + '：vault = 库根目录，sub = 题库文件夹的名字（原名即可）')
            exit 1
        }
    } else {
        # 没有配置：先自动探测一次，探到就直接问一句；探不到弹选择框
        $found = Find-QBVault
        $chosen = $null
        if ($found) {
            $foundPath = [IO.Path]::Combine($found.vault, $found.sub)
            Write-Host ('[i] 探测到 Obsidian 库里像题库的文件夹：' + $foundPath)
            $use = $true
            if (-not $NoPrompt) {
                Write-Host '[?] 用它吗？（Y 用它 / N 自己选，5 秒默认用它）'
                if ((Read-Key-Timeout 5) -match '^[nN]$') { $use = $false }
            }
            if ($use) { $chosen = $foundPath }
        }
        if (-not $chosen) {
            Write-Host '[..] 请选择题库存放的文件夹（里面有拆好的 *-Q*.md，名字随意）'
            $chosen = Select-QBValidFolder ''
        }
        if (-not $chosen) {
            Write-Host '[!] 没有选到可用的题库文件夹，无法启动'
            Write-Host ('[i] 下次双击 启动题库.bat 会再让你选；也可以手动改 ' + (Get-QBConfigPath) + '：vault = 库根目录，sub = 题库文件夹名')
            exit 1
        }
        $res = Save-QBFolder $chosen
        $VaultSrc = $res.vault
        $Sub = $res.sub
    }
}
if (-not $Sub) { $Sub = '12-试卷解析' }

$VaultPath = Resolve-QBPath $VaultSrc
if (-not (Test-Path -LiteralPath $VaultPath)) {
    Write-Host ('[!] 找不到题库根目录：' + $VaultPath)
    Write-Host ('[i] 请检查 ' + (Get-QBConfigPath) + ' 里的 vault 项')
    exit 1
}
$VaultAbs = (Resolve-Path -LiteralPath $VaultPath).Path.TrimEnd('\')
$SubAbs = [IO.Path]::Combine($VaultAbs, $Sub)
if (-not (Test-Path -LiteralPath $SubAbs)) {
    Write-Host ('[!] 该目录下没有子文件夹：' + $SubAbs)
    Write-Host ('[i] 请检查配置文件里的 sub 项（应为存放试卷解析的那个子文件夹名）')
    exit 1
}
Write-Host ('[i] 题库路径：' + $VaultAbs + '\' + $Sub)
$AppDir = $PSScriptRoot
$QJson = Join-Path $AppDir 'questions.json'

# 兜底：这一层必须真有拆好的试题，否则拒绝启动（避免挂空路径读到旧索引）
if (-not (Test-QBQuestionFolder $SubAbs)) {
    Write-Host ('[!] 这个文件夹里没有拆好的试题（*-Q*.md）：' + $SubAbs)
    Write-Host '[i] 请双击 启动题库.bat 重新选择题库文件夹（要选到「放独立试题 md」的那一层）'
    exit 1
}

# 索引：缺失 / 比最新 md 旧 / 是别的题库建的 → 重建
$needBuild = [bool]$Rebuild -or (-not (Test-Path -LiteralPath $QJson))
if (-not $needBuild) {
    try {
        # 只读文件头几 KB 取 meta.source，不必把 4.7MB 索引整份读进内存
        $fs = [IO.File]::OpenRead($QJson)
        try {
            $buf = New-Object byte[] 8192
            $n = $fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Close() }
        $head = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
        $sm = [regex]::Match($head, '"source":"([^"]*)"')
        if ($sm.Success) {
            $idxSrc = $sm.Groups[1].Value.Replace('\\', '\').TrimEnd('\')
            if ($idxSrc -and ($idxSrc -ne $Sub)) {
                Write-Host ('[i] 现有索引是别的题库建的（' + $idxSrc + '），按新路径重建')
                $needBuild = $true
            }
        }
    } catch { }
}
if (-not $needBuild) {
    $qTime = (Get-Item -LiteralPath $QJson).LastWriteTime
    $newest = Get-QBNewestMd -Vault $VaultAbs -Sub $Sub
    if ($newest -gt $qTime) { $needBuild = $true }
}
if ($needBuild) {
    Write-Host '[..] 正在重建索引…'
    $payload = New-QBIndex -Vault $VaultAbs -Sub $Sub -Out $QJson
    Write-Host ('[OK] 索引重建完成：' + $payload['meta']['count'] + ' 题 / ' + $payload['meta']['elapsedMs'] + 'ms')
}

$listener = $null
$usePort = 0
for ($i = 0; $i -lt 30; $i++) {
    $candidate = $Port + $i
    try {
        $try = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $candidate)
        $try.Start()
        $listener = $try
        $usePort = $candidate
        break
    } catch {
        # 这个端口被占了（或没权限），换下一个
        if ($try) { try { $try.Stop() } catch { } }
    }
}
if ($usePort -eq 0) {
    Write-Host ('[!] ' + $Port + ' 起连续 30 个端口都被占用，没有可用端口')
    exit 1
}

$state = @{ last = [datetime]::Now; deadline = $null }

function Update-Touch {
    param([bool]$Bye)
    $now = [datetime]::Now
    $state.last = $now
    if ($Bye) { $state.deadline = $now.AddSeconds($ByeGrace) } else { $state.deadline = $null }
}

function Get-MimeType {
    param([string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLower()
    switch ($ext) {
        '.html' { 'text/html; charset=utf-8' }
        '.htm'  { 'text/html; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.md'   { 'text/markdown; charset=utf-8' }
        '.txt'  { 'text/plain; charset=utf-8' }
        '.svg'  { 'image/svg+xml' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif'  { 'image/gif' }
        '.webp' { 'image/webp' }
        '.bmp'  { 'image/bmp' }
        '.ico'  { 'image/x-icon' }
        '.pdf'  { 'application/pdf' }
        default { 'application/octet-stream' }
    }
}

function Send-Response {
    param($Stream, [int]$Status, [string]$CType, [byte[]]$Body, [string]$Cache, [bool]$HeadOnly)

    $text = 'OK'
    switch ($Status) {
        204 { $text = 'No Content' }
        403 { $text = 'Forbidden' }
        404 { $text = 'Not Found' }
        500 { $text = 'Internal Server Error' }
    }
    if ($null -eq $Body) { $Body = New-Object byte[] 0 }
    $head = "HTTP/1.1 $Status $text`r`nContent-Type: $CType`r`nContent-Length: $($Body.Length)`r`nCache-Control: $Cache`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($head)
    $Stream.Write($hb, 0, $hb.Length)
    if (-not $HeadOnly -and $Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}

function Get-SafePath {
    param([string]$Root, [string]$Rel)
    if ($null -eq $Rel) { return $null }
    $clean = $Rel.Replace('/', '\').TrimStart('\')
    $full = [IO.Path]::GetFullPath((Join-Path $Root $clean))
    $rootWithSep = $Root.TrimEnd('\') + '\'
    if ($full -ne $Root -and -not $full.StartsWith($rootWithSep, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $full
}

function Serve-Request {
    param($Client)

    $stream = $Client.GetStream()
    $stream.ReadTimeout = 5000
    $buf = New-Object byte[] 8192
    $sb = New-Object System.Text.StringBuilder
    $deadline = [datetime]::Now.AddSeconds(5)

    while ([datetime]::Now -lt $deadline) {
        $n = 0
        try { $n = $stream.Read($buf, 0, $buf.Length) } catch { $n = 0 }
        if ($n -le 0) { break }
        [void]$sb.Append([Text.Encoding]::ASCII.GetString($buf, 0, $n))
        if ($sb.ToString().Contains("`r`n`r`n")) { break }
        if ($sb.Length -gt 65536) { break }
    }

    $raw = $sb.ToString()
    if (-not $raw) { return }

    $first = ($raw -split "`r`n")[0]
    $parts = $first -split ' '
    if ($parts.Length -lt 2) { return }
    $method = $parts[0].ToUpper()
    $target = $parts[1]
    $headOnly = ($method -eq 'HEAD')

    $qIndex = $target.IndexOf('?')
    if ($qIndex -ge 0) {
        $path = $target.Substring(0, $qIndex)
        $query = $target.Substring($qIndex + 1)
    } else {
        $path = $target
        $query = ''
    }
    try { $path = [Uri]::UnescapeDataString($path) } catch { }

    if ($path -eq '/' -or $path -eq '/index.html') {
        Update-Touch $false
        $file = Join-Path $AppDir 'index.html'
        Send-Response $stream 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes($file)) 'no-store' $headOnly
        return
    }

    if ($path -eq '/api/ping') {
        $bye = [regex]::IsMatch($query, '(^|&)bye=1(&|$)')
        Update-Touch $bye
        Send-Response $stream 204 'text/plain; charset=utf-8' $null 'no-store' $headOnly
        return
    }

    if ($path -eq '/api/questions') {
        if (-not (Test-Path -LiteralPath $QJson)) {
            Send-Response $stream 500 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('{"error":"index missing"}')) 'no-store' $headOnly
            return
        }
        Send-Response $stream 200 'application/json; charset=utf-8' ([IO.File]::ReadAllBytes($QJson)) 'no-store' $headOnly
        return
    }

    if ($path -eq '/api/meta') {
        # 用 ConvertTo-Json 生成，路径里出现引号/反斜杠也不会把 JSON 弄坏
        $metaObj = [ordered]@{
            version   = $QBVersion
            vault     = $VaultAbs
            vaultName = (Split-Path -Leaf $VaultAbs)
            sub       = $Sub
            source    = $SubAbs
        }
        Send-Response $stream 200 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes(($metaObj | ConvertTo-Json -Compress))) 'no-store' $headOnly
        return
    }

    if ($path.StartsWith('/assets/')) {
        $file = Get-SafePath $AppDir ('assets\' + $path.Substring(8).Replace('/', '\'))
        if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
            Send-Response $stream 404 'text/plain; charset=utf-8' $null 'no-store' $headOnly
            return
        }
        Send-Response $stream 200 (Get-MimeType $file) ([IO.File]::ReadAllBytes($file)) 'max-age=3600' $headOnly
        return
    }

    if ($path.StartsWith('/vault/')) {
        # 只开放「题库那一层」里的文件，不再把整个 Obsidian 库挂到页面上
        $file = Get-SafePath $SubAbs $path.Substring(7)
        if (-not $file) {
            Send-Response $stream 403 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('forbidden')) 'no-store' $headOnly
            return
        }
        $ext = [IO.Path]::GetExtension($file).ToLower()
        if ($script:VaultExt -notcontains $ext) {
            Send-Response $stream 403 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('forbidden type')) 'no-store' $headOnly
            return
        }
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            Send-Response $stream 404 'text/plain; charset=utf-8' $null 'no-store' $headOnly
            return
        }
        Send-Response $stream 200 (Get-MimeType $file) ([IO.File]::ReadAllBytes($file)) 'no-store' $headOnly
        return
    }

    Send-Response $stream 404 'text/plain; charset=utf-8' $null 'no-store' $headOnly
}

$url = 'http://127.0.0.1:' + $usePort + '/'
Write-Host ('[OK] 题库服务已启动：' + $url + '  （v' + $QBVersion + '）')
Write-Host ('     关闭浏览器标签页后会自动停止；也可以直接按 Ctrl+C')

if (-not $NoOpen) {
    try { Start-Process $url } catch { }
}

$stopReason = $null

try {
    while (-not $stopReason) {
        # 先判停，再收请求：避免被「只连不发」的空连接拖住后漏掉宽限期
        if ($null -ne $state.deadline -and [datetime]::Now -gt $state.deadline) {
            $stopReason = ('浏览器页面已关闭（' + $ByeGrace + ' 秒宽限期已过）')
            break
        }
        if ($IdleExit -gt 0 -and (([datetime]::Now) - $state.last).TotalSeconds -gt $IdleExit) {
            $stopReason = ('页面已 ' + $IdleExit + ' 秒无心跳')
            break
        }

        if ($listener.Pending()) {
            $client = $listener.AcceptTcpClient()
            try {
                Serve-Request $client
            } catch {
            } finally {
                try { $client.Close() } catch { }
            }
        } else {
            Start-Sleep -Milliseconds 20
        }
    }
} finally {
    try { $listener.Stop() } catch { }
}

Write-Host ('[OK] ' + $stopReason + '，服务自动退出')
