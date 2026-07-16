$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$appProject = Join-Path $repoRoot "windows\VpnRouter.App\VpnRouter.App.csproj"

dotnet build $appProject -p:Platform=x64
dotnet run --project $appProject --no-build -p:Platform=x64
