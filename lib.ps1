# 试卷题库 · 索引核心逻辑（PowerShell 版，5.1 兼容）
# 被 build-index.ps1 与 serve.ps1 共用。

$script:QBAppDir = $PSScriptRoot

function Get-QBVersion {
    $p = Join-Path $PSScriptRoot 'VERSION'
    if (Test-Path -LiteralPath $p) {
        $v = ([IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false)))).Trim()
        if ($v) { return $v }
    }
    return '0.0.0'
}

function ConvertTo-QBPlainString {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text
}

function Unquote-QBValue {
    param([string]$Value)
    $s = $Value.Trim()
    if ($s.Length -ge 2) {
        $first = $s.Substring(0, 1); $last = $s.Substring($s.Length - 1, 1)
        if ($first -eq $last -and ($first -eq '"' -or $first -eq "'")) {
            return $s.Substring(1, $s.Length - 2)
        }
    }
    return $s
}

function Split-QBInlineList {
    param([string]$Inner)
    $out = New-Object System.Collections.ArrayList
    $buf = ''
    $quote = $null
    foreach ($ch in $Inner.ToCharArray()) {
        if ($quote) {
            $buf += $ch
            if ($ch -eq $quote) { $quote = $null }
        } elseif ($ch -eq '"' -or $ch -eq "'") {
            $quote = $ch
            $buf += $ch
        } elseif ($ch -eq ',') {
            [void]$out.Add($buf)
            $buf = ''
        } else {
            $buf += $ch
        }
    }
    [void]$out.Add($buf)
    return $out.ToArray()
}

function ConvertFrom-QBYamlLite {
    param([string]$Block)
    $data = @{}
    $cur = $null
    foreach ($raw in ($Block -split "`n")) {
        if (-not $raw.Trim()) { continue }
        if ($raw.TrimStart().StartsWith('#')) { continue }
        $line = $raw.TrimEnd()

        $itemMatch = [regex]::Match($line, '^\s*-\s+(.*)$')
        if ($itemMatch.Success -and $cur) {
            $val = Unquote-QBValue $itemMatch.Groups[1].Value.Trim()
            $existing = $data[$cur]
            if ($null -eq $existing) { $existing = @() }
            if ($existing -is [array]) {
                $data[$cur] = @($existing) + @($val)
            } else {
                $data[$cur] = @($val)
            }
            continue
        }

        $kv = [regex]::Match($line, '^([A-Za-z_][\w\-]*)\s*:\s*(.*)$')
        if (-not $kv.Success) { continue }
        $key = $kv.Groups[1].Value
        $val = $kv.Groups[2].Value.Trim()
        $cur = $key
        if ($val -eq '') {
            $data[$key] = @()
        } elseif ($val.StartsWith('[') -and $val.EndsWith(']')) {
            $inner = $val.Substring(1, $val.Length - 2).Trim()
            $list = @()
            foreach ($piece in (Split-QBInlineList $inner)) {
                if ($piece.Trim()) { $list += (Unquote-QBValue $piece.Trim()) }
            }
            $data[$key] = $list
        } else {
            $data[$key] = (Unquote-QBValue $val)
        }
    }
    return $data
}

function Split-QBFrontmatter {
    param([string]$Text)
    $t = $Text
    if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $t = $t.Replace("`r`n", "`n").Replace("`r", "`n")
    $m = [regex]::Match($t, '^---\n(.*?)\n---\n?', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { return @{ Yaml = $null; Body = $t } }
    return @{ Yaml = ($m.Groups[1].Value); Body = $t.Substring($m.Index + $m.Length) }
}

function Get-QBList {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [array]) { return @($Value | Where-Object { $_ -ne '' -and $null -ne $_ }) }
    $s = [string]$Value
    if ($s.Trim()) { return @($s.Trim()) }
    return @()
}

function Convert-QBEntities {
    param([string]$s)
    if ($null -eq $s) { return '' }
    $s = [regex]::Replace($s, '&#x27;|&#39;', "'")
    $s = [regex]::Replace($s, '&lt;', '<')
    $s = [regex]::Replace($s, '&gt;', '>')
    $s = [regex]::Replace($s, '&nbsp;', ' ')
    $s = [regex]::Replace($s, '&amp;', '&')
    return $s
}

function Remove-QBTableMarks {
    param([string]$s)
    if ($null -eq $s) { return '' }
    $s = [regex]::Replace($s, '(?m)^\s*\|?[\s:|-]+\|[\s:|-]*\s*$', ' ')
    $s = $s.Replace('|', ' ')
    return $s
}

function Get-QBPlainText {
    param([string]$Md)
    $s = $Md
    $s = [regex]::Replace($s, '!\[[^\]]*\]\([^)]*\)', ' ')
    $s = [regex]::Replace($s, '\[\[([^\]|]+)(?:\|([^\]]+))?\]\]', {
        param($m)
        if ($m.Groups[2].Success -and $m.Groups[2].Value) { return $m.Groups[2].Value }
        return $m.Groups[1].Value
    })
    $s = [regex]::Replace($s, '\[([^\]]*)\]\([^)]*\)', '$1')
    $s = [regex]::Replace($s, '\$\$?(.+?)\$\$?', '$1', [Text.RegularExpressions.RegexOptions]::Singleline)
    $s = Convert-QBEntities $s
    $s = Remove-QBTableMarks $s
    $s = [regex]::Replace($s, '(?m)^>\s*\[![^\]]*\][-+]?\s*', ' ')
    $s = [regex]::Replace($s, '(?m)^>\s?', ' ')
    $s = [regex]::Replace($s, '[#*_`>|]', ' ')
    $s = [regex]::Replace($s, '\s+', ' ')
    return $s.Trim()
}

function Get-QBStemMarkdown {
    param([string]$Md, [int]$Limit = 230)
    $s = $Md
    $s = [regex]::Replace($s, '!\[[^\]]*\]\([^)]*\)', ' ')
    $s = [regex]::Replace($s, '\[\[([^\]|]+)(?:\|([^\]]+))?\]\]', {
        param($m)
        if ($m.Groups[2].Success -and $m.Groups[2].Value) { return $m.Groups[2].Value }
        return $m.Groups[1].Value
    })
    $s = [regex]::Replace($s, '\[([^\]]*)\]\([^)]*\)', '$1')

    # 按行内公式 $...$ 分段：数学段原样保留定界符 |、转义下划线 \_ 与 LaTeX 源码，
    # 避免被表格竖线清洗 / 下划线归一误伤；仅正文段做 markdown 清洗。
    $parts = [regex]::Split($s, '(\$[^$]*\$)')
    $kept = New-Object System.Collections.ArrayList
    foreach ($p in $parts) {
        if ($null -eq $p) { continue }
        $isMath = $p.Length -gt 1 -and $p.StartsWith('$') -and $p.EndsWith('$')
        if ($isMath) {
            [void]$kept.Add($p)
            continue
        }
        $q = $p
        $q = $q.Replace('\_', '_')
        $q = Remove-QBTableMarks $q
        $q = Convert-QBEntities $q
        $q = [regex]::Replace($q, '(?m)^>\s*\[![^\]]*\][-+]?\s*', ' ')
        $q = [regex]::Replace($q, '(?m)^>\s?', ' ')
        [void]$kept.Add($q)
    }
    $s = ($kept -join '')
    $s = [regex]::Replace($s, '\s+', ' ').Trim()
    if ($s.Length -gt $Limit) {
        $s = $s.Substring(0, $Limit)
        # 若截断点落在某个未闭合公式内部（花括号不配平 / 落在 _ ^ \ 上 / 下标上标后缺内容），
        # 回退到该残缺公式之前，避免 MathJax 解析残缺 LaTeX 报错；闭括号之后的正文不动。
        $lastDollar = $s.LastIndexOf('$')
        if ($lastDollar -ge 0) {
            $before = $s.Substring(0, $lastDollar)
            $openCount = ([regex]::Matches($before, '(?<!\\)\$')).Count
            if ($openCount % 2 -eq 0) {
                $tail = $s.Substring($lastDollar + 1)
                $ob = ([regex]::Matches($tail, '\{')).Count
                $cb = ([regex]::Matches($tail, '\}')).Count
                $incomplete = ($ob -ne $cb) -or ($tail -match '[\\_^]$') -or ($tail -match '[_^](?![{A-Za-z0-9\\])')
                if ($incomplete) { $s = $s.Substring(0, $lastDollar).TrimEnd() }
            }
        }
        $dollars = ([regex]::Matches($s, '(?<!\\)\$')).Count
        if ($dollars % 2 -ne 0) { $s += '$' }
    }
    return $s
}

function Get-QBSubject {
    param([string]$DocId, [string]$Paper, $Tags, [string]$Category)
    $subjectNames = @('数学', '物理', '化学', '生物', '英语', '语文', '历史', '地理', '道法', '几何')
    $byPrefix = @{ MAT = '数学'; GEO = '几何'; PHY = '物理'; CHE = '化学'; BIO = '生物'
                   ENG = '英语'; CHI = '语文'; HIS = '历史'; GEOG = '地理'; POL = '道法' }
    foreach ($name in $subjectNames) {
        if ($Category -and $Category.EndsWith($name)) { return $name }
    }
    $m = [regex]::Match([string]$DocId, '^([A-Za-z]{2,4})-')
    if ($m.Success) {
        $code = $m.Groups[1].Value.ToUpper()
        if ($byPrefix.ContainsKey($code)) { return $byPrefix[$code] }
    }
    foreach ($name in $subjectNames) {
        if ($Paper -and $Paper.Contains($name)) { return $name }
    }
    foreach ($t in $Tags) {
        foreach ($name in $subjectNames) {
            if ($t.EndsWith($name)) { return $name }
        }
    }
    return '其他'
}

function Get-QBGrade {
    param([string]$Paper, $Tags, [string]$DocId)
    $volumeLabel = @{ '上' = '上册'; '下' = '下册'; '全' = '全一册' }
    $tag0 = ''
    if ($Tags -and $Tags.Count -gt 0) { $tag0 = [string]$Tags[0] }
    $m = [regex]::Match($tag0, '([七八九])([上下全])')
    if (-not $m.Success) { $m = [regex]::Match([string]$Paper, '^([七八九])([上下全])') }
    if (-not $m.Success) { $m = [regex]::Match([string]$Paper, '([七八九])([上下全])') }
    if (-not $m.Success) {
        $mid = [regex]::Match([string]$DocId, '^[A-Za-z]{2,4}-([789])-')
        if ($mid.Success) {
            $gmap = @{ '7' = '七'; '8' = '八'; '9' = '九' }
            return @{ Grade = ($gmap[$mid.Groups[1].Value] + '年级'); Volume = ''; GradeTag = '' }
        }
        return @{ Grade = '其他'; Volume = ''; GradeTag = '' }
    }
    $g = $m.Groups[1].Value
    $v = $m.Groups[2].Value
    $vol = ''
    if ($volumeLabel.ContainsKey($v)) { $vol = $volumeLabel[$v] }
    return @{ Grade = ($g + '年级'); Volume = $vol; GradeTag = ($g + $v) }
}

function Get-QBType {
    param([string]$Body)
    if ([regex]::IsMatch($Body, '(?m)^\s*A\s*[.、．]\s*\S')) { return '选择题' }
    if ([regex]::IsMatch($Body, '_{3,}|＿{2,}|（\s*　*\s*）\s*$|\(\s*　*\s*\)', [Text.RegularExpressions.RegexOptions]::Multiline)) { return '填空题' }
    return '解答题'
}

function Get-QBAnchorNo {
    param([string]$Source, [string]$DocId)
    $m = [regex]::Match([string]$Source, '#\s*(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    $m = [regex]::Match([string]$DocId, '-Q(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

function Get-QBFileNo {
    param([string]$DocId)
    $m = [regex]::Match([string]$DocId, '-Q(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

function Get-QBPaperFromSource {
    param([string]$Source)
    $m = [regex]::Match([string]$Source, '\[\[([^\]|#]+)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Get-QBKnowledgeTree {
    param([string]$Vault, [string]$Sub)
    $base = Join-Path $Vault (Join-Path $Sub '待解析')
    $tree = @{}
    if (-not (Test-Path -LiteralPath $base)) { return $tree }
    $enc = New-Object Text.UTF8Encoding($false)
    $files = Get-ChildItem -LiteralPath $base -File -Force | Where-Object { $_.Name -like '*.md' } | Sort-Object Name
    foreach ($f in $files) {
        $m = [regex]::Match($f.Name, '【初中(数学|物理|化学|生物|英语|语文|历史|地理|道法)知识点体系')
        if (-not $m.Success) { continue }
        $subject = $m.Groups[1].Value
        $books = New-Object System.Collections.ArrayList
        $book = $null
        $chapter = $null
        $lines = ([IO.File]::ReadAllText($f.FullName, $enc)) -split "`n"
        foreach ($line in $lines) {
            if ($line.StartsWith('## ')) {
                $book = @{ book = $line.Substring(3).Trim(); chapters = (New-Object System.Collections.ArrayList) }
                [void]$books.Add($book)
                $chapter = $null
            } elseif ($line.StartsWith('### ')) {
                if ($null -eq $book) {
                    $book = @{ book = '未分册'; chapters = (New-Object System.Collections.ArrayList) }
                    [void]$books.Add($book)
                }
                $chapter = @{ title = $line.Substring(4).Trim(); points = (New-Object System.Collections.ArrayList) }
                [void]$book.chapters.Add($chapter)
            } elseif ($line.StartsWith('#### ')) {
                $title = $line.Substring(5).Trim()
                if (-not [regex]::IsMatch($title, '^\d+\s*-\s*\d+')) { continue }
                if ($null -eq $chapter) {
                    if ($null -eq $book) {
                        $book = @{ book = '未分册'; chapters = (New-Object System.Collections.ArrayList) }
                        [void]$books.Add($book)
                    }
                    $chapter = @{ title = '未分章'; points = (New-Object System.Collections.ArrayList) }
                    [void]$book.chapters.Add($chapter)
                }
                [void]$chapter.points.Add($title)
            }
        }
        if ($books.Count -gt 0) { $tree[$subject] = $books }
    }
    return $tree
}

function New-QBIndex {
    param([string]$Vault, [string]$Sub, [string]$Out)

    $version = Get-QBVersion
    $root = Join-Path $Vault $Sub
    if (-not (Test-Path -LiteralPath $root)) { throw "找不到目录：$root" }

    $rootFull = (Resolve-Path -LiteralPath $root).Path.TrimEnd('\')
    $vaultFull = (Resolve-Path -LiteralPath $Vault).Path.TrimEnd('\')
    $enc = New-Object Text.UTF8Encoding($false)

    $items = New-Object System.Collections.Generic.List[object]
    $skipped = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()

    $files = Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force |
             Where-Object { $_.Name -match '-Q\d+\.md$' -and $_.DirectoryName -notmatch '\\\.' -and $_.DirectoryName -notmatch '\\试卷题库\\' } |
             Sort-Object FullName

    foreach ($f in $files) {
        $text = ''
        try { $text = [IO.File]::ReadAllText($f.FullName, $enc) }
        catch { $skipped++; continue }

        $split = Split-QBFrontmatter $text
        if ($null -eq $split.Yaml) { $skipped++; continue }
        $fm = ConvertFrom-QBYamlLite $split.Yaml
        $body = $split.Body

        $docId = ''
        if ($fm.ContainsKey('id') -and $fm['id']) { $docId = [string]$fm['id'] } else { $docId = [IO.Path]::GetFileNameWithoutExtension($f.Name) }
        $source = ''
        if ($fm.ContainsKey('source') -and $fm['source']) { $source = [string]$fm['source'] }
        $knowledge = @(Get-QBList $fm['knowledge'])
        $tags = @(Get-QBList $fm['tags'])

        $paper = $f.Directory.Name
        $relDir = $f.Directory.FullName.Substring($rootFull.Length).TrimStart('\')
        $category = ''
        if ($relDir) { $category = ($relDir -split '\\')[0] }

        $subject = Get-QBSubject -DocId $docId -Paper $paper -Tags $tags -Category $category
        $gradeInfo = Get-QBGrade -Paper $paper -Tags $tags -DocId $docId
        $anchorNo = Get-QBAnchorNo -Source $source -DocId $docId
        $fileNo = Get-QBFileNo $docId

        # 题干 = 第一个 callout 之前的部分；判题型只看题干，
        # 免得答案/解析里恰好出现「A.」把解答题判成选择题（题干本身不截断）
        $stemSrc = ($body -split '> \[!question\]', 2)[0]
        $qtype = Get-QBType $stemSrc

        $plainAll = Get-QBPlainText $body
        $stem = Get-QBPlainText $stemSrc
        if ($stem.Length -gt 260) { $stem = $stem.Substring(0, 260) }
        $stemTex = Get-QBStemMarkdown $stemSrc

        $plainHead = $plainAll
        if ($plainHead.Length -gt 1200) { $plainHead = $plainHead.Substring(0, 1200) }
        $search = ($plainHead + ' ' + $paper + ' ' + ($knowledge -join ' ')).ToLower()

        $rel = $f.FullName.Substring($vaultFull.Length).TrimStart('\').Replace('\', '/')

        [void]$items.Add([pscustomobject]@{
            id          = $docId
            rel         = $rel
            paper       = $paper
            paperSrc    = (Get-QBPaperFromSource $source)
            subject     = $subject
            grade       = $gradeInfo.Grade
            volume      = $gradeInfo.Volume
            gradeTag    = $gradeInfo.GradeTag
            tags        = $tags
            type        = $qtype
            qno         = $fileNo
            anchorNo    = $anchorNo
            category    = $category
            knowledge   = $knowledge
            stem        = $stem
            stemTex     = $stemTex
            search      = $search
            hasImg      = $body.Contains('![')
            hasAnswer   = $body.Contains('> [!question]')
        })
    }

    # 排序：年级 → 试卷名（序数比较，与 Python 一致）→ 题号
    $gradeOrder = @{ '七年级' = 1; '八年级' = 2; '九年级' = 3; '其他' = 9 }
    $comparison = [System.Comparison[object]]{
        param($a, $b)
        $ga = 9; if ($gradeOrder.ContainsKey($a.grade)) { $ga = $gradeOrder[$a.grade] }
        $gb = 9; if ($gradeOrder.ContainsKey($b.grade)) { $gb = $gradeOrder[$b.grade] }
        if ($ga -ne $gb) { return [Math]::Sign($ga - $gb) }
        $pc = [string]::CompareOrdinal($a.paper, $b.paper)
        if ($pc -ne 0) { return [Math]::Sign($pc) }
        return [Math]::Sign($a.qno - $b.qno)
    }
    $items.Sort($comparison)

    $kpCount = @{}
    $kpSubj = @{}
    $papers = @{}
    foreach ($it in $items) {
        $papers[$it.paper] = 1
        foreach ($k in $it.knowledge) {
            if ($kpCount.ContainsKey($k)) { $kpCount[$k] = $kpCount[$k] + 1 } else { $kpCount[$k] = 1 }
            if (-not $kpSubj.ContainsKey($k)) { $kpSubj[$k] = @() }
            if ($kpSubj[$k] -notcontains $it.subject) { $kpSubj[$k] = @($kpSubj[$k]) + @($it.subject) }
        }
    }

    $kpTree = Get-QBKnowledgeTree -Vault $Vault -Sub $Sub

    $covered = @{}
    foreach ($subject in $kpTree.Keys) {
        foreach ($b in $kpTree[$subject]) {
            foreach ($ch in $b.chapters) {
                foreach ($p in $ch.points) { $covered[$p] = 1 }
            }
        }
    }
    $orphans = @{}
    foreach ($k in $kpCount.Keys) {
        if ($covered.ContainsKey($k)) { continue }
        $subj = '其他'
        if ($kpSubj.ContainsKey($k) -and $kpSubj[$k].Count -gt 0) { $subj = $kpSubj[$k][0] }
        if (-not $orphans.ContainsKey($subj)) { $orphans[$subj] = @() }
        $orphans[$subj] = @($orphans[$subj]) + @($k)
    }
    foreach ($subj in $orphans.Keys) {
        if (-not $kpTree.ContainsKey($subj)) { $kpTree[$subj] = (New-Object System.Collections.ArrayList) }
        # 按「章-节」编号排序，保证每次重建顺序稳定
        $pts = $orphans[$subj] | Sort-Object @{ Expression = {
                if ($_ -match '^(\d+)\s*-\s*(\d+)') { return ([int]$Matches[1]) * 1000 + ([int]$Matches[2]) }
                return 999999
            } }, @{ Expression = { $_ } }
        [void]$kpTree[$subj].Add(@{
            book     = '未归入知识点体系'
            chapters = @(@{ title = '待归类'; points = @($pts) })
        })
    }

    $generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $elapsedMs = [int]$sw.ElapsedMilliseconds

    $meta = [ordered]@{
        version        = $version
        generatedAt    = $generatedAt
        vault          = $Vault
        source         = $rootFull
        count          = $items.Count
        papers         = $papers.Count
        knowledgeCount = $kpCount.Count
        skipped        = $skipped
        elapsedMs      = $elapsedMs
    }

    $payload = [ordered]@{
        meta             = $meta
        knowledgeCounts  = $kpCount
        knowledgeSubjects = $kpSubj
        kpTree           = $kpTree
        items            = $items
    }

    $json = $payload | ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding($false)))
    return $payload
}

function Get-QBNewestMd {
    param([string]$Vault, [string]$Sub)
    $root = Join-Path $Vault $Sub
    $newest = [datetime]::MinValue
    if (-not (Test-Path -LiteralPath $root)) { return $newest }
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -Filter '*-Q*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '-Q\d+\.md$' -and $_.DirectoryName -notmatch '\\\.' -and $_.DirectoryName -notmatch '\\试卷题库\\' } |
        ForEach-Object { if ($_.LastWriteTime -gt $newest) { $newest = $_.LastWriteTime } }
    return $newest
}

# ============ 题库路径配置（可自定义，便于分享给别人） ============
# 读取顺序：命令行参数 > config.json > Obsidian 库自动探测 > 提示用户填写

function Get-QBConfigPath {
    return (Join-Path $script:QBAppDir 'config.json')
}

function Read-QBConfig {
    $path = Get-QBConfigPath
    $cfg = @{ vault = ''; sub = ''; port = 0; idleExit = 0; exists = $false }
    if (Test-Path -LiteralPath $path) {
        try {
            $raw = [IO.File]::ReadAllText($path, (New-Object Text.UTF8Encoding($false)))
            $j = $raw | ConvertFrom-Json
            if ($j) {
                if ($j.vault) { $cfg.vault = [string]$j.vault }
                if ($j.sub) { $cfg.sub = [string]$j.sub }
                if ($j.port) { $cfg.port = [int]$j.port }
                if ($j.idleExit) { $cfg.idleExit = [int]$j.idleExit }
                $cfg.exists = $true
            }
        } catch { }
    }
    return $cfg
}

function Save-QBConfig {
    param([string]$Vault, [string]$Sub, [int]$Port = 8787, [int]$IdleExit = 300)
    $path = Get-QBConfigPath
    $obj = [ordered]@{
        '_说明'    = '题库路径配置。vault = Obsidian 库根目录（可写相对路径，相对本程序目录）；sub = 库内存放试卷解析的子文件夹；port = 端口；idleExit = 无心跳多少秒后自动退出。'
        vault      = [string]$Vault
        sub        = [string]$Sub
        port       = [int]$Port
        idleExit   = [int]$IdleExit
    }
    $json = $obj | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
    return $path
}

function Resolve-QBPath {
    param([string]$Path)
    if (-not $Path) { return '' }
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return [IO.Path]::Combine($script:QBAppDir, $Path)
}

function Test-QBQuestionFolder {
    # 判断一个文件夹是不是「拆好题的题库」：里面有 *-Q*.md（抽查即可，不遍历全盘）
    param([string]$Dir)
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir -PathType Container)) { return $false }
    $hit = Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -Filter '*-Q*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '-Q\d+\.md$' -and $_.DirectoryName -notmatch '\\\.' } |
        Select-Object -First 1
    return [bool]$hit
}

function Select-QBFolder {
    # 弹系统文件夹选择框，返回选中路径；取消或这台机器弹不出框时返回 ''
    param([string]$Initial = '')
    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null } catch { return '' }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择题库存放的文件夹（里面有拆好的 *-Q*.md；名字随意，例如 12-试卷解析 / 我的数学题库）'
    $dlg.ShowNewFolderButton = $false
    $start = ''
    if ($Initial) {
        if (Test-Path -LiteralPath $Initial -PathType Container) {
            $start = $Initial
        } else {
            $parent = Split-Path -Parent $Initial
            if ($parent -and (Test-Path -LiteralPath $parent -PathType Container)) { $start = $parent }
        }
    }
    if ($start) { $dlg.SelectedPath = $start }
    $ok = $dlg.ShowDialog()
    if ($ok -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return ''
}

function Find-QBVault {
    # 从 Obsidian 的 vault 列表里找题库，找不到返回 $null。
    # 第一步按名字猜（含「试卷解析」）；猜不到再按内容认（子目录里有 *-Q*.md），所以文件夹叫什么都行。
    param([string]$RootHint = '')
    $roots = @()
    if ($RootHint) {
        if (Test-Path -LiteralPath $RootHint -PathType Container) { $roots += $RootHint }
    } else {
        $obs = Join-Path $env:APPDATA 'obsidian\obsidian.json'
        if (-not (Test-Path -LiteralPath $obs)) { return $null }
        try {
            $j = (Get-Content -LiteralPath $obs -Raw -Encoding UTF8) | ConvertFrom-Json
            foreach ($k in @($j.vaults.PSObject.Properties.Name)) {
                $p = $j.vaults.$k.path
                if ($p -and (Test-Path -LiteralPath $p)) { $roots += $p }
            }
        } catch { return $null }
    }

    foreach ($root in $roots) {
        $dirs = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)
        # 1) 名字里带「试卷解析」
        foreach ($d in $dirs) {
            if ($d.Name -like '*试卷解析*') { return @{ vault = $root; sub = $d.Name } }
        }
        # 2) 名字随意，但目录里确实有拆好的试题
        foreach ($d in $dirs) {
            if ($d.Name -match '^[\.\$_]') { continue }
            if (Test-QBQuestionFolder $d.FullName) { return @{ vault = $root; sub = $d.Name } }
        }
    }
    return $null
}
