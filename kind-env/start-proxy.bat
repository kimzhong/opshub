@echo off
chcp 65001 >nul
echo ================================================
echo  Kind 多集群服务代理启动器
echo  保持此窗口运行，Grafana/ArgoCD 即可访问
echo  关闭窗口 = 停止代理
echo ================================================
echo.

REM 清理旧的 kubectl port-forward 进程
wsl -d Ubuntu bash -c "pkill -f 'port-forward.*30300' 2>/dev/null; pkill -f 'port-forward.*30080' 2>/dev/null; echo [cleanup] old port-forwards removed"
echo.

REM 启动 Grafana port-forward (绑定到 WSL2 IP)
start "KindGrafana" wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward --address 172.30.156.99 svc/prometheus-grafana 30300:80
echo [OK] Grafana port-forward 启动中 (localhost:30300)
timeout /t 3 /nobreak >nul

REM 启动 ArgoCD port-forward (绑定到 WSL2 IP)
start "KindArgoCD" wsl -d Ubuntu kubectl --context kind-ops-mgmt -n argocd port-forward --address 172.30.156.99 svc/argocd-server 30080:443
echo [OK] ArgoCD port-forward 启动中 (localhost:30080)
timeout /t 3 /nobreak >nul

REM 启动 wsl_proxy.py (Windows -> WSL2 代理)
echo [OK] 启动 wsl_proxy.py (Windows 代理层)...
start "KindProxy" python "%~dp0wsl_proxy.py"

echo.
echo ================================================
echo  所有服务已启动!
echo.
echo  Grafana:  http://localhost:30300
echo  ArgoCD:   https://localhost:30080
echo  ArgoCD 用户名: admin
echo  ArgoCD 密码: wG0YYYIbLXX31dVf
echo  Grafana 用户名: admin
echo  Grafana 密码: admin123
echo ================================================
echo.
echo  此窗口不要关闭! 按任意键退出...
pause >nul
