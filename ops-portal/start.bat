@echo off
chcp 65001 >nul
title Kind Ops Portal - Node.js Server
cd /d "%~dp0"

echo.
echo  ============================================
echo   Kind Ops Portal v2.0
echo   Node.js 版运维平台
echo  ============================================
echo.

where node >nul 2>nul
if errorlevel 1 (
    echo  [X] 未找到 Node.js
    echo.
    echo  请先安装 Node.js 20+:
    echo  https://nodejs.org/
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%v in ('node --version') do set NODEV=%%v
echo  [OK] Node.js %NODEV%

if not exist node_modules (
    echo  [..] 首次运行，安装依赖...
    call npm install --no-audit --no-fund
    if errorlevel 1 (
        echo  [X] 依赖安装失败
        pause
        exit /b 1
    )
    echo  [OK] 依赖安装完成
)
echo.

echo  启动中... 浏览器访问 http://localhost:8099/
echo  关闭本窗口即停止服务
echo.
echo  提示：告警/日志功能需要另外开一个 WSL 窗口做 port-forward：
echo    wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090
echo    wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/loki-gateway 3100:80
echo.

node server/index.js

echo.
echo  服务已停止。
pause
