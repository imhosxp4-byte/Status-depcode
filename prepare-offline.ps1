# prepare-offline.ps1
# รันสคริปต์นี้บนเครื่องที่มี internet เพื่อสร้าง offline package
# ผลลัพธ์: Status-Depcode-Offline.zip (ใช้ติดตั้งได้โดยไม่ต้องใช้ internet)

$ErrorActionPreference = 'Stop'
$OutDir  = "$PSScriptRoot\offline"
$AppDir  = "$PSScriptRoot"
$ZipPath = "$PSScriptRoot\Status-Depcode-Offline.zip"
$NodeUrl = "https://nodejs.org/dist/v20.19.2/node-v20.19.2-x64.msi"
$NodeMsi = "node-v20.19.2-x64.msi"

Write-Host ""
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host "   เตรียม Offline Package — Status-Depcode" -ForegroundColor Cyan
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host ""

# สร้างโฟลเดอร์ offline
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# ── 1. ดาวน์โหลด Node.js installer ──────────────────────────────────────────
Write-Host "  [1/4] ดาวน์โหลด Node.js installer..." -ForegroundColor Yellow
$nodeDest = Join-Path $OutDir $NodeMsi
if (Test-Path $nodeDest) {
    Write-Host "        มีไฟล์แล้ว — ข้าม" -ForegroundColor Gray
} else {
    Invoke-WebRequest -Uri $NodeUrl -OutFile $nodeDest -UseBasicParsing
    Write-Host "        ดาวน์โหลดสำเร็จ: $nodeDest" -ForegroundColor Green
}

# ── 2. npm install และสร้าง cache ───────────────────────────────────────────
Write-Host ""
Write-Host "  [2/4] ติดตั้ง npm packages และสร้าง cache..." -ForegroundColor Yellow
$CacheDir = Join-Path $OutDir "npm-cache"
Set-Location $AppDir
& npm install --quiet
& npm install --prefer-offline --cache $CacheDir --quiet
Write-Host "        npm cache สำเร็จ: $CacheDir" -ForegroundColor Green

# ── 3. รวมไฟล์โปรแกรม ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [3/4] รวบรวมไฟล์โปรแกรม..." -ForegroundColor Yellow
$AppBundle = Join-Path $OutDir "app"
if (Test-Path $AppBundle) { Remove-Item -Recurse -Force $AppBundle }
New-Item -ItemType Directory -Path $AppBundle | Out-Null

$include = @("server.js","index.html","status.html","settings.html",
             "styles.css","script.js","package.json","package-lock.json",
             "start-server.bat","README.md",".gitignore","setup.bat","launch-server.vbs")
foreach ($f in $include) {
    $src = Join-Path $AppDir $f
    if (Test-Path $src) { Copy-Item $src $AppBundle }
}
# รวม node_modules
$nmSrc = Join-Path $AppDir "node_modules"
if (Test-Path $nmSrc) {
    Write-Host "        รวม node_modules (อาจใช้เวลาสักครู่)..." -ForegroundColor Gray
    Copy-Item -Recurse $nmSrc (Join-Path $AppBundle "node_modules")
}
Write-Host "        รวบรวมไฟล์สำเร็จ" -ForegroundColor Green

# ── 4. บีบอัดเป็น ZIP ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  [4/4] สร้างไฟล์ ZIP..." -ForegroundColor Yellow
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

# สร้าง setup ใน package
$pkgDir = Join-Path $env:TEMP "sdc-package"
if (Test-Path $pkgDir) { Remove-Item -Recurse -Force $pkgDir }
New-Item -ItemType Directory -Path $pkgDir | Out-Null

# คัดลอก offline folder และ setup.bat
Copy-Item -Recurse $OutDir (Join-Path $pkgDir "offline")
Copy-Item (Join-Path $AppDir "setup.bat") $pkgDir

Compress-Archive -Path "$pkgDir\*" -DestinationPath $ZipPath -CompressionLevel Optimal
Remove-Item -Recurse -Force $pkgDir

$size = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host "        สำเร็จ: $ZipPath ($size MB)" -ForegroundColor Green

Write-Host ""
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host "   Offline Package พร้อมแล้ว!" -ForegroundColor Cyan
Write-Host ""
Write-Host "   วิธีใช้บนเครื่องที่ไม่มี internet:" -ForegroundColor White
Write-Host "   1. แตกไฟล์ Status-Depcode-Offline.zip" -ForegroundColor White
Write-Host "   2. รัน setup.bat" -ForegroundColor White
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host ""
