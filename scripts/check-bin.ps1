param(
    [String]$tag,
    [String]$name
    )

Start-Process gh -ArgumentList "release download $tag --pattern $name-x86_64-pc-windows-msvc.exe --repo holochain/holochain" -Wait

$proc = Start-Process "$name-x86_64-pc-windows-msvc.exe" -ArgumentList "--version" -PassThru -Wait
$exit_code = $proc.ExitCode
echo "$name-result=[$exit_code]" >> $env:GITHUB_OUTPUT
