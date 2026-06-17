param(
  [Parameter(Mandatory = $true)]
  [string]$ApiBaseUrl
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path "pubspec.yaml")) {
  throw "Run this script from the mobile folder."
}

if ($ApiBaseUrl -notmatch '^https?://') {
  throw "ApiBaseUrl must start with http:// or https://"
}

$flutter = "C:\dev\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
  $flutter = "flutter"
}

& $flutter pub get
& $flutter build apk --release --dart-define="API_BASE_URL=$ApiBaseUrl"

Write-Host "Release APK ready:"
Write-Host "build\app\outputs\flutter-apk\app-release.apk"
