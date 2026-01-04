# Flutter Panel Systemd 服务说明

## 文件说明

- `flutter-panel.service`: systemd 服务配置文件
- `run-systemd.sh`: 专用于 systemd 服务的启动脚本（移除了 sudo）
- `install-service.sh`: 服务安装脚本

## 服务特性

- ✅ 在 weston 启动后自动启动
- ✅ 启动失败自动重试（最多30次）
- ✅ 重试间隔1秒
- ✅ 开机自启（可选）

## 安装步骤

1. **安装服务**：
   ```bash
   ./install-service.sh
   ```

2. **启动服务**（可选，服务会在 weston 启动后自动启动）：
   ```bash
   sudo systemctl start flutter-panel.service
   ```

## 服务管理命令

```bash
# 查看服务状态
sudo systemctl status flutter-panel.service

# 启动服务
sudo systemctl start flutter-panel.service

# 停止服务
sudo systemctl stop flutter-panel.service

# 重启服务
sudo systemctl restart flutter-panel.service

# 查看实时日志
sudo journalctl -u flutter-panel.service -f

# 查看最近日志
sudo journalctl -u flutter-panel.service -n 100

# 禁用开机自启
sudo systemctl disable flutter-panel.service

# 启用开机自启
sudo systemctl enable flutter-panel.service
```

## 卸载服务

```bash
# 停止并禁用服务
sudo systemctl stop flutter-panel.service
sudo systemctl disable flutter-panel.service

# 删除服务文件
sudo rm /etc/systemd/system/flutter-panel.service

# 重新加载 systemd
sudo systemctl daemon-reload
```

## 注意事项

1. 服务以 root 用户运行（因为需要访问 `/run/user/0`）
2. 服务会在 weston 启动后自动启动
3. 如果应用崩溃，服务会自动重启（最多30次，间隔1秒）
4. 日志会记录到 systemd journal，使用 `journalctl` 查看

## 故障排查

如果服务无法启动，检查：

1. **weston 是否正常运行**：
   ```bash
   sudo systemctl status weston.service
   ```

2. **应用文件是否存在**：
   ```bash
   ls -la /home/neons/flutter_linux_panel/build/elinux/arm64/release/bundle/demo1
   ```

3. **查看详细错误日志**：
   ```bash
   sudo journalctl -u flutter-panel.service -n 50 --no-pager
   ```

4. **手动测试启动脚本**：
   ```bash
   /home/neons/flutter_linux_panel/run-systemd.sh
   ```
