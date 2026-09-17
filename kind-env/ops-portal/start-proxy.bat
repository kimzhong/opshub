@echo off
:: ops-portal 代理服务启动器
:: 将此文件放入 WSL Ubuntu 的 /mnt/c/Users/kim/kind-env/ops-portal/ 并双击运行
title Ops Portal Proxy
cd /d C:\Users\kim\kind-env\ops-portal
echo ==========================================
echo  ops-portal 代理服务
echo  API: http://localhost:8099
echo  Health: http://localhost:8099/health
echo ==========================================
echo.
echo  所需端口转发（另开 WSL 终端运行）:
echo  wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090 ^&^
echo  wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/loki-gateway 3100:80 ^&^
echo.
python3 proxy_server.py
pause
