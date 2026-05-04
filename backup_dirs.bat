@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================
rem  Zaloha podadresaru do sifrovanych 7z archivu
rem
rem  Pouziti:
rem    zaloha_adresaru.bat
rem    zaloha_adresaru.bat "D:\Data"
rem
rem  Vysledek:
rem    jmeno_adresare_YYYYMMDD.7z
rem ==========================================================

rem --- Zjisteni zdrojoveho adresare ---
if "%~1"=="" (
    set "ROOT=%CD%"
) else (
    set "ROOT=%~1"
)

if not exist "%ROOT%\" (
    echo Chyba: Zadany adresar neexistuje:
    echo   %ROOT%
    exit /b 1
)

rem --- Najdi 7-Zip ---
set "SEVENZIP="

where 7z.exe >nul 2>nul
if not errorlevel 1 (
    for /f "delims=" %%A in ('where 7z.exe 2^>nul') do (
        if not defined SEVENZIP set "SEVENZIP=%%A"
    )
)

if not defined SEVENZIP if exist "%ProgramFiles%\7-Zip\7z.exe" set "SEVENZIP=%ProgramFiles%\7-Zip\7z.exe"
if not defined SEVENZIP if exist "%ProgramFiles(x86)%\7-Zip\7z.exe" set "SEVENZIP=%ProgramFiles(x86)%\7-Zip\7z.exe"

if not defined SEVENZIP (
    echo Chyba: 7-Zip nebyl nalezen.
    echo Nainstalujte 7-Zip nebo pridejte 7z.exe do PATH.
    exit /b 1
)

rem --- Datum ve formatu YYYYMMDD ---
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd"`) do set "TODAY=%%A"

if not defined TODAY (
    echo Chyba: Nepodarilo se zjistit datum.
    exit /b 1
)

echo.
echo Adresar pro zalohu:
echo   %ROOT%
echo.
echo Zaloha vytvori jeden sifrovany archiv pro kazdy primy podadresar.
echo.

rem --- Kontrola, jestli existuji nejake podadresare ---
set "HASDIRS=0"
for /d %%D in ("%ROOT%\*") do set "HASDIRS=1"

if "%HASDIRS%"=="0" (
    echo V adresari nejsou zadne podadresare k zaloze.
    exit /b 0
)

echo Seznam adresaru, ktere budou zalohovany:
echo.

rem --- Vypis adresaru vcetne velikosti ---
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root = '%ROOT%';" ^
  "$dirs = Get-ChildItem -LiteralPath $root -Directory -Force | Sort-Object Name;" ^
  "foreach ($d in $dirs) {" ^
  "  $size = (Get-ChildItem -LiteralPath $d.FullName -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum;" ^
  "  if ($null -eq $size) { $size = 0 }" ^
  "  $units = 'B','KB','MB','GB','TB';" ^
  "  $i = 0; $n = [double]$size;" ^
  "  while ($n -ge 1024 -and $i -lt $units.Count - 1) { $n = $n / 1024; $i++ }" ^
  "  '{0,-40} {1,12:N2} {2}' -f $d.Name, $n, $units[$i]" ^
  "}"

echo.
echo ----------------------------------------------------------
echo.

rem --- Heslo ---
echo Zadejte heslo pro sifrovane archivy.
echo Pozor: v BAT variante bude heslo pri psani videt.
echo.

set "PASSWORD="
set /p "PASSWORD=Heslo: "

if "%PASSWORD%"=="" (
    echo Chyba: Heslo nesmi byt prazdne.
    exit /b 1
)

set "PASSWORD2="
set /p "PASSWORD2=Heslo znovu: "

if not "%PASSWORD%"=="%PASSWORD2%" (
    echo Chyba: Hesla se neshoduji.
    exit /b 1
)

echo.
echo Zacinam zalohovani...
echo.

pushd "%ROOT%" || (
    echo Chyba: Nepodarilo se vstoupit do adresare:
    echo   %ROOT%
    exit /b 1
)

rem --- Vytvoreni archivu pro kazdy podadresar ---
for /d %%D in (*) do call :BackupOne "%%~fD" "%%~nxD"

popd

set "PASSWORD="
set "PASSWORD2="

echo.
echo Zaloha dokoncena.
exit /b 0


:BackupOne
set "DIR_FULL=%~1"
set "DIR_NAME=%~2"
set "ARCHIVE=%DIR_NAME%_%TODAY%.7z"

echo Zalohuji: %DIR_NAME%
echo Archiv:   %ARCHIVE%

if exist "%ARCHIVE%" (
    echo Archiv uz existuje, preskakuji.
    echo.
    exit /b 0
)

"%SEVENZIP%" a -t7z "%ARCHIVE%" "%DIR_NAME%" -mx=9 -mhe=on -p"%PASSWORD%" -y

if errorlevel 2 (
    echo Chyba pri vytvareni archivu:
    echo   %ARCHIVE%
    echo.
    exit /b 1
)

if errorlevel 1 (
    echo Archiv byl vytvoren s varovanim:
    echo   %ARCHIVE%
    echo.
    exit /b 0
)

echo Hotovo.
echo.
exit /b 0