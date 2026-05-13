@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title Status-Depcode — Setup

:: ─── CONFIG ────────────────────────────────────────────────────────────────
set "INSTALL_DIR=%USERPROFILE%\Desktop\Status-Depcode"
set "GITHUB_ZIP=https://github.com/imhosxp4-byte/Status-depcode/archive/refs/heads/main.zip"
set "NODE_MSI=https://nodejs.org/dist/v20.19.2/node-v20.19.2-x64.msi"
set "NODE_MSI_NAME=node-v20.19.2-x64.msi"
set "OFFLINE_BUNDLE=%~dp0offline\Status-Depcode-Offline.zip"
set "OFFLINE_NODE=%~dp0offline\%NODE_MSI_NAME%"

echo.
echo  =====================================================
echo   ระบบแสดงรายชื่อผู้ป่วยรอตรวจ ^| Status-Depcode
echo   Setup Installer
echo  =====================================================
echo.

:: ─── STEP 1: Node.js ──────────────────────────────────────────────────────
echo  [1/5] ตรวจสอบ Node.js...
node --version >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%v in ('node --version 2^>nul') do set "NODEVER=%%v"
    echo        พบ Node.js !NODEVER! — ข้ามการติดตั้ง
    goto :step2
)

echo        ไม่พบ Node.js — กำลังติดตั้ง...
if exist "%OFFLINE_NODE%" (
    echo        ใช้ไฟล์ offline: %OFFLINE_NODE%
    set "NODE_INST=%OFFLINE_NODE%"
) else (
    echo        ดาวน์โหลดจาก internet...
    powershell -NoProfile -Command ^
        "Invoke-WebRequest -Uri '%NODE_MSI%' -OutFile '%TEMP%\%NODE_MSI_NAME%' -UseBasicParsing"
    if not exist "%TEMP%\%NODE_MSI_NAME%" (
        echo  [ERROR] ดาวน์โหลด Node.js ไม่สำเร็จ
        goto :fail
    )
    set "NODE_INST=%TEMP%\%NODE_MSI_NAME%"
)
echo        กำลังติดตั้ง Node.js (อาจใช้เวลา 1-2 นาที)...
msiexec /i "!NODE_INST!" /qn /norestart ADDLOCAL=ALL
:: รอและรีเฟรช PATH
timeout /t 5 /nobreak >nul
set "PATH=%PATH%;C:\Program Files\nodejs"
node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] ติดตั้ง Node.js ไม่สำเร็จ
    goto :fail
)
echo        ติดตั้ง Node.js สำเร็จ

:: ─── STEP 2: ดาวน์โหลดโปรแกรม ────────────────────────────────────────────
:step2
echo.
echo  [2/5] ดาวน์โหลดโปรแกรม...
if exist "%INSTALL_DIR%\server.js" (
    echo        พบโปรแกรมเดิมแล้ว — ข้ามการดาวน์โหลด
    goto :step3
)
mkdir "%INSTALL_DIR%" 2>nul

if exist "%OFFLINE_BUNDLE%" (
    echo        ใช้ไฟล์ offline bundle...
    powershell -NoProfile -Command ^
        "Expand-Archive -Path '%OFFLINE_BUNDLE%' -DestinationPath '%TEMP%\sdc-extract' -Force"
) else (
    echo        ดาวน์โหลดจาก GitHub...
    powershell -NoProfile -Command ^
        "Invoke-WebRequest -Uri '%GITHUB_ZIP%' -OutFile '%TEMP%\sdc.zip' -UseBasicParsing"
    if not exist "%TEMP%\sdc.zip" (
        echo  [ERROR] ดาวน์โหลดโปรแกรมไม่สำเร็จ
        goto :fail
    )
    powershell -NoProfile -Command ^
        "Expand-Archive -Path '%TEMP%\sdc.zip' -DestinationPath '%TEMP%\sdc-extract' -Force"
)

:: คัดลอกไฟล์
for /d %%d in ("%TEMP%\sdc-extract\*") do (
    xcopy /E /I /Y /Q "%%d\*" "%INSTALL_DIR%\" >nul
)
if not exist "%INSTALL_DIR%\server.js" (
    echo  [ERROR] ไม่พบไฟล์โปรแกรม
    goto :fail
)
echo        คัดลอกไฟล์สำเร็จ

:: ─── STEP 3: ติดตั้ง npm packages ────────────────────────────────────────
:step3
echo.
echo  [3/5] ติดตั้ง packages...
if exist "%INSTALL_DIR%\node_modules\express" (
    echo        พบ packages เดิมแล้ว — ข้ามการติดตั้ง
    goto :step4
)
cd /d "%INSTALL_DIR%"

:: เช็ค offline npm cache
if exist "%~dp0offline\npm-cache" (
    echo        ใช้ npm offline cache...
    call npm install --prefer-offline --cache "%~dp0offline\npm-cache" --quiet
) else (
    echo        ดาวน์โหลด packages จาก internet...
    call npm install --quiet
)
if %errorlevel% neq 0 (
    echo  [ERROR] ติดตั้ง packages ไม่สำเร็จ
    goto :fail
)
echo        ติดตั้ง packages สำเร็จ

:: ─── STEP 4: สร้าง launcher (ไม่มี command prompt) ─────────────────────
:step4
echo.
echo  [4/5] สร้าง launcher...

:: สร้าง VBScript launcher
(
echo Set sh = CreateObject^("WScript.Shell"^)
echo sh.CurrentDirectory = "%INSTALL_DIR%"
echo sh.Run "cmd /c node server.js ^>^> ""%INSTALL_DIR%\server.log"" 2^>^&1", 0, False
) > "%INSTALL_DIR%\launch-server.vbs"

:: สร้าง stop-server.bat
(
echo @echo off
echo taskkill /F /IM node.exe /T ^>nul 2^>^&1
echo echo Server หยุดทำงานแล้ว
echo timeout /t 2 /nobreak ^>nul
) > "%INSTALL_DIR%\stop-server.bat"

echo        สร้าง launcher สำเร็จ

:: ─── STEP 5: สร้าง Shortcuts ─────────────────────────────────────────────
:step5
echo.
echo  [5/5] สร้าง shortcut...

:: Desktop shortcut
set "DESK=%USERPROFILE%\Desktop"
powershell -NoProfile -Command ^
    "$s=(New-Object -COM WScript.Shell).CreateShortcut('%DESK%\Status-Depcode.lnk');$s.TargetPath='%INSTALL_DIR%\launch-server.vbs';$s.WorkingDirectory='%INSTALL_DIR%';$s.Description='เปิดระบบแสดงรายชื่อผู้ป่วยรอตรวจ';$s.Save()"

:: Windows Startup shortcut
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
powershell -NoProfile -Command ^
    "$s=(New-Object -COM WScript.Shell).CreateShortcut('%STARTUP%\Status-Depcode.lnk');$s.TargetPath='%INSTALL_DIR%\launch-server.vbs';$s.WorkingDirectory='%INSTALL_DIR%';$s.Description='Auto-start Status-Depcode';$s.Save()"

echo        สร้าง shortcut บน Desktop และ Startup สำเร็จ

:: ─── เสร็จสิ้น ─────────────────────────────────────────────────────────
echo.
echo  =====================================================
echo   ติดตั้งเสร็จเรียบร้อย!
echo.
echo   - ไฟล์ติดตั้งที่: %INSTALL_DIR%
echo   - เปิด shortcut "Status-Depcode" บน Desktop
echo   - เปิด browser: http://localhost:5000
echo   - เริ่มต้นอัตโนมัติทุกครั้งที่เปิดเครื่อง
echo  =====================================================
echo.

:: เปิด server ทันที
start "" "%INSTALL_DIR%\launch-server.vbs"
timeout /t 3 /nobreak >nul
start "" "http://localhost:5000"

echo  กด Enter เพื่อปิดหน้าต่างนี้
pause >nul
exit /b 0

:fail
echo.
echo  [!] การติดตั้งไม่สำเร็จ กรุณาลองใหม่หรือติดต่อผู้ดูแลระบบ
echo.
pause
exit /b 1
