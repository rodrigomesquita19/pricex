@echo off
chcp 65001 >nul
title PriceX - Build APK

echo ========================================
echo         PriceX - Build APK
echo ========================================
echo.

:: Verificar se Flutter esta instalado
where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERRO] Flutter nao encontrado no PATH!
    echo Verifique se o Flutter esta instalado corretamente.
    pause
    exit /b 1
)

:: Navegar para o diretorio do projeto
cd /d "%~dp0"

echo [1/4] Limpando build anterior...
call flutter clean

echo.
echo [2/4] Obtendo dependencias...
call flutter pub get

echo.
echo [3/4] Gerando APK em modo Release...
call flutter build apk --release

echo.
if %ERRORLEVEL% equ 0 (
    echo ========================================
    echo [4/4] BUILD CONCLUIDO COM SUCESSO!
    echo ========================================
    echo.
    echo APK gerado em:
    echo %~dp0build\app\outputs\flutter-apk\app-release.apk
    echo.

    :: Abrir pasta do APK
    if exist "build\app\outputs\flutter-apk\app-release.apk" (
        echo Deseja abrir a pasta do APK? (S/N)
        set /p ABRIR=
        if /i "%ABRIR%"=="S" (
            explorer "build\app\outputs\flutter-apk"
        )
    )
) else (
    echo ========================================
    echo [ERRO] Falha ao gerar o APK!
    echo ========================================
    echo Verifique os erros acima.
)

echo.
pause
