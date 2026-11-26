[CmdletBinding()]
param([Parameter(Mandatory)][string]$Archive)

$ErrorActionPreference = 'Stop'
$work = Join-Path ([IO.Path]::GetTempPath()) ('Inkrail-editor-' + [guid]::NewGuid().ToString('N'))
try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $work
    $app = @(Get-ChildItem -LiteralPath $work -Filter Inkrail.exe -File -Recurse)
    if ($app.Count -ne 1) { throw 'Expected one Inkrail executable in the portable ZIP.' }
    $page = Join-Path $app[0].DirectoryName 'check-editor.html'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'check-editor.html') -Destination $page
    $browser = @(
        ${env:ProgramFiles(x86)}, $env:ProgramFiles | Where-Object { $_ } | ForEach-Object {
            Join-Path $_ 'Microsoft\Edge\Application\msedge.exe'
        } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    ) | Select-Object -First 1
    if (-not $browser) { throw 'Microsoft Edge was not found on this runner.' }
    $profile = Join-Path $work 'browser-profile'
    $uri = [uri]::new($page).AbsoluteUri
    if (Test-Path -LiteralPath (Join-Path $app[0].DirectoryName 'ui/interactive-letter.js')) {
        $uri += '?interactive'
        if (Test-Path -LiteralPath (Join-Path $app[0].DirectoryName 'ui/assets/ProtectedInteractiveLetter.html')) {
            $uri += '&protected'
        }
    }
    # Web Crypto runs on a worker. A virtual-time DOM snapshot can finish before key derivation.
    $log = Join-Path $work 'editor-check.log'
    $flags = @('--headless', '--disable-gpu', '--no-first-run', '--allow-file-access-from-files', '--enable-logging',
               "--log-file=`"$log`"", "--user-data-dir=`"$profile`"", "`"$uri`"")
    $process = Start-Process -FilePath $browser -ArgumentList $flags -PassThru
    try {
        $deadline = (Get-Date).AddSeconds(60)
        do {
            if (Test-Path -LiteralPath $log) {
                $result = Select-String -LiteralPath $log -SimpleMatch 'INKRAIL_EDITOR_RESULT ' | Select-Object -First 1
                if ($result) {
                    if ($result.Line -notmatch '\bINKRAIL_EDITOR_RESULT PASS\b') { throw $result.Line }
                    Write-Output 'Packaged editor regression passed.'
                    return
                }
            }
            if ($process.HasExited) { throw 'The browser exited before reporting the editor check result.' }
            Start-Sleep -Milliseconds 200
        } while ((Get-Date) -lt $deadline)
        throw 'The packaged editor did not finish its checks within 60 seconds.'
    } finally {
        if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
