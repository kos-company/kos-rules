param([string]$Root = $PSScriptRoot, [string]$ClosedIdList = '')
$ErrorActionPreference = 'Stop'
$patterns = [ordered]@{
    'email' = '(?i)\b[A-Z0-9.!#$%&*+/=?^_{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    'телефон' = '(?<![\w.])(?:\+\d{1,3}|8)[ -]?\(?\d{3}\)?[ -]?\d{3}[ -]?\d{2}[ -]?\d{2}(?!\w)'
    'токен' = '(?i)\b(?:sk-[\w-]{12,}|AIza[\w-]{20,}|gh[pousr]_[\w-]{20,}|github_pat_[\w-]{20,}|Bearer\s+[\w.=-]{12,})'
    'длинный код' = '(?<![\w-])[A-Za-z0-9+/_=-]{48,}(?![\w-])'
    'устаревшая ссылка' = '(?i)raw\.githubusercontent\.com/|github\.com/[^/]+/[^/]+/blob/'
    'личное имя проекта' = '(?i)\b(?:Степан|Ефимов|Максим|Сысоев|Ренат|Ксени|Виля|Виле|Илья|Вика|Эльвин)[а-яё]*\b'
    'ссылка Google с ID' = '(?i)https?://(?:docs|drive)\.google\.com/[^\s)>]*[\w-]{20,}'
}
$closed = if ($ClosedIdList) { @(Get-Content -LiteralPath $ClosedIdList | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @() }
$issues = 0
$homePath = (Resolve-Path -LiteralPath $Root).Path
$repo = Test-Path -LiteralPath (Join-Path $homePath '.git')
if ($repo) {
    $paths = @(git -c core.quotepath=false -C $homePath ls-files)
    if ($LASTEXITCODE) { throw 'Не удалось прочитать список файлов Git' }
} else {
    $paths = @(Get-ChildItem -LiteralPath $homePath -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($homePath, $_.FullName) })
}
foreach ($path in $paths) {
    if ($path -in @('check-public.ps1','hooks/pre-push')) { continue }
    $file = Join-Path $homePath $path
    if ([IO.Path]::GetExtension($file) -notin @('.md','.txt','.yml','.yaml','.json')) {
        Write-Output "${path}: неожиданный формат"
        $issues++
        continue
    }
    $lineNo = 0
    foreach ($line in Get-Content -LiteralPath $file -Encoding utf8) {
        $lineNo++
        foreach ($entry in $patterns.GetEnumerator()) {
            # Owner-approved routing rule names the owner without personal records.
            if ($entry.Key -eq 'личное имя проекта' -and
                $path.Replace('\','/') -in @('00_READ_FIRST.md','docs/read-first.md') -and
                $line -ceq '1.10. Отчёты по личным задачам Степана (его ПК, дом, сеть) сохраняй в его личном хабе C:\AI-HUB\inbox.') {
                continue
            }
            if ($line -match $entry.Value) {
                Write-Output "${path}:${lineNo} · $($entry.Key)"
                $issues++
            }
        }
        foreach ($id in $closed) {
            if ($line.Contains($id)) {
                Write-Output "${path}:${lineNo} · ID закрытого файла"
                $issues++
            }
        }
    }
}
$site = 'https://kos-company.github.io/kos-rules/'
$routes = @{'index.html' = $true}
$pages = @(Get-ChildItem -LiteralPath (Join-Path $homePath 'docs') -Recurse -Filter '*.md')
foreach ($page in $pages) {
    $route = [regex]::Match([IO.File]::ReadAllText($page.FullName), '(?m)^permalink: /([a-z0-9/-]+\.html)\s*$')
    if (!$route.Success) { throw "У страницы нет латинского адреса: $($page.Name)" }
    $routes[$route.Groups[1].Value] = $true
}
foreach ($page in $pages) {
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($page.FullName), [regex]::Escape($site)+'([a-z0-9/-]+\.html)', 'IgnoreCase')) {
        if (!$routes.ContainsKey($m.Groups[1].Value)) { throw "Ссылка Pages без страницы: $($page.Name)" }
    }
}
foreach ($path in $paths) {
    if ($path -notmatch '^[a-zA-Z0-9._/-]+$') { throw 'Нелатинское имя файла' }
}
if ($issues) { exit 1 }
Write-Output "Автопроверка прошла ($($paths.Count) файлов). Проверьте также смысл и контекст изменений."
