param(
    [string]$DatabaseUrl = "postgres://postgres:postgres@localhost:5432/p2p_dev?sslmode=disable",
    [string]$JwtSecret = "change-me-in-development",
    [string]$ApiAddr = ":8080"
)

# Configure env vars for the backend run
$env:DATABASE_URL = $DatabaseUrl
$env:JWT_SECRET = $JwtSecret
$env:ALLOW_INSECURE_DEV = "true"
$env:OTP_DEV_MODE = "true"
$env:API_ADDR = $ApiAddr

Write-Host "Using DATABASE_URL=$DatabaseUrl"
Write-Host "Using JWT_SECRET=$JwtSecret"
Write-Host "API will listen on $ApiAddr"

# Move to repository root (backend folder)
$psPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Push-Location $psPath
Set-Location ..

Write-Host "Running backend... (go run ./cmd/api)"
go run ./cmd/api

Pop-Location
