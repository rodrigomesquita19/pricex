@echo off
chcp 65001 >nul
title PriceX - Build APK (Rapido)

echo ========================================
echo    PriceX - Build APK (Rapido)
echo ========================================
echo.
echo [*] Modo rapido - sem flutter clean
echo.

:: Verificar se Flutter esta instalado
where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Flutter nao encontrado no PATH!
    pause
    exit /b 1
)

:: Navegar para o diretorio do projeto
cd /d "%~dp0"

echo [1/2] Gerando APK em modo Release...
call flutter build apk --release

echo.
if %ERRORLEVEL% equ 0 (
    echo ========================================
    echo [2/2] BUILD CONCLUIDO COM SUCESSO!
    echo ========================================
    echo.
    echo APK: build\app\outputs\flutter-apk\app-release.apk
    echo.

    :: Abrir pasta automaticamente
    explorer "build\app\outputs\flutter-apk"
) else (
    echo ========================================
    echo [ERRO] Falha ao gerar o APK!
    echo ========================================
)

echo.
pause
