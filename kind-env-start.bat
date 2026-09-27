@echo off
chcp 65001 >nul
echo [1/4] 清理旧进程...
wsl -d Ubuntu bash -c "pkill -f 'port-forward.*30300' 2>/dev/null; pkill -f 'port-forward.*30080' 2>/dev/null; echo done"
echo.
echo [2/4] 启动 Grafana port-forward (localhost:30300)...
start "KindGrafanaPF" wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward --address 172.30.156.99 svc/prometheus-grafana 30300:80
timeout /t 4 /nobreak >nul

echo [3/4] 启动 ArgoCD port-forward (localhost:30080)...
start "KindArgoCDPF" wsl -d Ubuntu kubectl --context kind-ops-mgmt -n argocd port-forward --address 172.30.156.99 svc/argocd-server 30080:443
timeout /t 4 /nobreak >nul

echo [4/4] 启动 wsl_proxy.py (Windows->WSL2 代理层)...
start "KindProxy" python "%~dp0wsl_proxy.py"
timeout /t 3 /nobreak >nul

echo.
echo === 启动完成 ===
echo.
echo   Grafana:  http://localhost:30300
echo   ArgoCD:   https://localhost:30080
echo.
echo   Grafana:  admin / admin123
echo   ArgoCD:   admin / wG0YYYIbLXX31dVf
echo.
echo   不要关闭这些窗口! 关闭窗口会中断服务
echo.
pause
