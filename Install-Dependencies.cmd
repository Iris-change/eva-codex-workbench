@echo off
pushd "%~dp0workbench"
call npm.cmd ci
set "EVA_INSTALL_EXIT=%ERRORLEVEL%"
popd
if not "%EVA_INSTALL_EXIT%"=="0" pause
exit /b %EVA_INSTALL_EXIT%
