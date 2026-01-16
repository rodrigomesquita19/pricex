@echo off
title PriceX - Compilar e Instalar no Tablet
color 0A

echo ============================================
echo        PriceX - Compilador para Tablet
echo ============================================
echo.

cd /d "F:\ProjetosFlutter\pricex"
if errorlevel 1 (
    echo [ERRO] Nao foi possivel acessar a pasta do projeto!
    pause
    exit
)

echo Pasta do projeto: %cd%
echo.

echo [1] Verificando Flutter...
call flutter --version
if errorlevel 1 (
    echo.
    echo [ERRO] Flutter nao encontrado! Verifique se o Flutter esta no PATH.
    pause
    exit
)
echo.

echo [2] Verificando dispositivos conectados...
echo.
call flutter devices
echo.

echo ============================================
echo Escolha uma opcao:
echo ============================================
echo [1] Instalar no tablet (release)
echo [2] Compilar APK release (para distribuir)
echo [3] Instalar no tablet (debug - com logs)
echo [4] Apenas compilar APK debug
echo [5] Sair
echo.

set /p opcao="Digite a opcao desejada: "

if "%opcao%"=="1" goto release_run
if "%opcao%"=="2" goto release_apk
if "%opcao%"=="3" goto debug_run
if "%opcao%"=="4" goto debug_apk
if "%opcao%"=="5" goto fim

echo [ERRO] Opcao invalida!
pause
goto fim

:release_run
echo.
echo [*] Instalando no tablet em modo release...
echo.
call flutter run --release
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao instalar no tablet!
)
pause
goto fim

:release_apk
echo.
echo [*] Compilando APK release...
echo.
call flutter build apk --release
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao compilar APK!
    pause
    goto fim
)
echo.
echo [OK] APK gerado em: build\app\outputs\flutter-apk\app-release.apk
echo.
start "" "F:\ProjetosFlutter\pricex\build\app\outputs\flutter-apk"
pause
goto fim

:debug_run
echo.
echo [*] Instalando no tablet em modo debug...
echo.
call flutter run --debug
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao instalar no tablet!
)
pause
goto fim

:debug_apk
echo.
echo [*] Compilando APK debug...
echo.
call flutter build apk --debug
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao compilar APK!
    pause
    goto fim
)
echo.
echo [OK] APK gerado em: build\app\outputs\flutter-apk\app-debug.apk
echo.
start "" "F:\ProjetosFlutter\pricex\build\app\outputs\flutter-apk"
pause
goto fim

:fim
echo.
echo ============================================
echo Processo finalizado!
echo ============================================
pause
