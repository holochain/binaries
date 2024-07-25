param(
    [String]$tag,
    [String]$name
    )

Start-Process gh -ArgumentList "release download $tag --pattern $name-x86_64-windows.exe --repo holochain/holochain"

$proc = Start-Process "$name-x86_64-windows.exe" -ArgumentList "--version" -PassThru -Wait
$exit_code = $proc.ExitCode
echo "$name-result=[$exit_code]" >> $env:GITHUB_OUTPUT
