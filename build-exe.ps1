# build-exe.ps1 — สร้าง Status-Depcode-Setup.exe ด้วย IExpress (built-in Windows)
$ErrorActionPreference = 'Stop'

$Root    = $PSScriptRoot
$ExeOut  = "$Root\Status-Depcode-Setup.exe"
$SedFile = "$env:TEMP\sdc-setup.sed"
$WorkDir = "$env:TEMP\sdc-iexpress"

Write-Host "สร้างโฟลเดอร์ชั่วคราว..." -ForegroundColor Cyan
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

# คัดลอกไฟล์ที่ต้องใส่ใน .exe
Copy-Item "$Root\setup.bat"          "$WorkDir\setup.bat"
Copy-Item "$Root\prepare-offline.ps1" "$WorkDir\prepare-offline.ps1"
Copy-Item "$Root\launch-server.vbs"  "$WorkDir\launch-server.vbs"

# สร้าง README สั้นๆ
@"
Status-Depcode Setup
====================
รันไฟล์ setup.bat เพื่อติดตั้งระบบ
"@ | Out-File "$WorkDir\README.txt" -Encoding UTF8

# สร้าง .sed (IExpress Script)
$files = Get-ChildItem $WorkDir -File
$fileList = ($files | ForEach-Object { "$($_.Name)=" }) -join "`r`n"

$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$ExeOut
FriendlyName=Status-Depcode Setup
AppLaunched=cmd /c setup.bat
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
[SourceFiles]
SourceFiles0=$WorkDir
[SourceFiles0]
$fileList
"@

$sed | Out-File -FilePath $SedFile -Encoding ASCII

Write-Host "รัน IExpress เพื่อสร้าง .exe..." -ForegroundColor Cyan
$iexpress = "$env:windir\System32\iexpress.exe"
$proc = Start-Process -FilePath $iexpress -ArgumentList "/N /Q `"$SedFile`"" -Wait -PassThru

if (Test-Path $ExeOut) {
    $size = [math]::Round((Get-Item $ExeOut).Length / 1KB)
    Write-Host "สร้างสำเร็จ: $ExeOut ($size KB)" -ForegroundColor Green
} else {
    Write-Host "[ERROR] สร้าง .exe ไม่สำเร็จ exit=$($proc.ExitCode)" -ForegroundColor Red
}
Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
