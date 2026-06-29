@echo off
REM liboqs 构建脚本 — Windows (需要 CMake + Visual Studio 或 MinGW)
REM
REM 用法:
REM   setup_liboqs.bat
REM
REM 输出:
REM   build\liboqs\bin\oqs.dll

setlocal enabledelayedexpansion

set LIBOQS_VERSION=0.10.1
set SCRIPT_DIR=%~dp0
set PROJECT_DIR=%SCRIPT_DIR%..
set BUILD_DIR=%PROJECT_DIR%\build\liboqs
set LIBOQS_SRC=%BUILD_DIR%\src

echo === 编译 liboqs v%LIBOQS_VERSION% ===

REM 1. 下载 liboqs
if not exist "%LIBOQS_SRC%" (
    echo [1/4] 下载 liboqs...
    mkdir "%BUILD_DIR%" 2>nul

    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/open-quantum-safe/liboqs/archive/refs/tags/%LIBOQS_VERSION%.tar.gz' -OutFile '%BUILD_DIR%\liboqs.tar.gz'"

    REM 解压 (需要 tar, Windows 10 build 17063+)
    tar xzf "%BUILD_DIR%\liboqs.tar.gz" -C "%BUILD_DIR%"
    move "%BUILD_DIR%\liboqs-%LIBOQS_VERSION%" "%LIBOQS_SRC%"
    del "%BUILD_DIR%\liboqs.tar.gz"
) else (
    echo [1/4] liboqs 源码已存在
)

REM 2. CMake 配置
echo [2/4] 配置 CMake...
mkdir "%LIBOQS_SRC%\build" 2>nul
cd /d "%LIBOQS_SRC%\build"

cmake .. ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DOQS_MINIMAL_BUILD="OQS_KEM_alg_ml_kem_768" ^
    -DBUILD_SHARED_LIBS=ON ^
    -DCMAKE_INSTALL_PREFIX="%BUILD_DIR%"

REM 3. 编译
echo [3/4] 编译...
cmake --build . --config Release --parallel

REM 4. 安装
echo [4/4] 安装到 %BUILD_DIR%...
cmake --install . --config Release

echo === 完成 ===
echo.
echo DLL 位置: %BUILD_DIR%\bin\oqs.dll
echo.
echo 部署:
echo   复制 %BUILD_DIR%\bin\oqs.dll 到应用的运行目录
echo   或 windows\flutter\ephemeral\
