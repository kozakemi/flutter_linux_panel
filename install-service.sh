#!/bin/bash
# Flutter Panel Systemd 服务安装脚本

SERVICE_NAME="flutter-panel.service"
SERVICE_FILE="/home/neons/flutter_linux_panel/flutter-panel.service"
SYSTEMD_DIR="/etc/systemd/system"

echo "正在安装 Flutter Panel systemd 服务..."

# 检查服务文件是否存在
if [ ! -f "$SERVICE_FILE" ]; then
    echo "错误: 服务文件不存在: $SERVICE_FILE"
    exit 1
fi

# 复制服务文件到 systemd 目录
echo "复制服务文件到 $SYSTEMD_DIR..."
sudo cp "$SERVICE_FILE" "$SYSTEMD_DIR/$SERVICE_NAME"

# 重新加载 systemd
echo "重新加载 systemd..."
sudo systemctl daemon-reload

# 启用服务（开机自启）
echo "启用服务..."
sudo systemctl enable "$SERVICE_NAME"

echo ""
echo "服务安装完成！"
echo ""
echo "使用以下命令管理服务："
echo "  启动服务: sudo systemctl start $SERVICE_NAME"
echo "  停止服务: sudo systemctl stop $SERVICE_NAME"
echo "  重启服务: sudo systemctl restart $SERVICE_NAME"
echo "  查看状态: sudo systemctl status $SERVICE_NAME"
echo "  查看日志: sudo journalctl -u $SERVICE_NAME -f"
echo "  禁用服务: sudo systemctl disable $SERVICE_NAME"
echo ""
echo "注意: 服务会在 weston 启动后自动启动，失败时会自动重试（最多30次，间隔1秒）"
