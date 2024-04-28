# Juicity 一键部署脚本

这个仓库提供了一个便捷的一键部署脚本，用于快速安装和配置 Juicity 协议。Juicity 是一种高效的网络传输协议，旨在提供更好的性能和可靠性。

## 功能特点

- 自动检测操作系统并适配相应的安装方式
- 支持自定义安装选项，如端口、UUID 和密码
- 提供证书申请的多种方式，包括自动申请和手动指定
- 优化的脚本执行流程，提供清晰的用户交互和提示信息
- 集成了启动、停止、重启 Juicity 服务的功能
- 可以方便地修改 Juicity 的配置参数
- 提供一键更新 Juicity 到最新版本的功能
- 显示 Juicity 的配置信息，方便用户查看和管理

## 使用方法

### 安装 Juicity

执行以下命令即可一键部署 Juicity：

```shell
wget -N https://raw.githubusercontent.com/Misaka-blog/juicity-script/main/juicity.sh && bash juicity.sh
```

按照脚本提示进行操作，选择合适的安装选项，即可完成 Juicity 的安装和配置。

### 管理 Juicity

安装完成后，你可以使用以下命令来管理 Juicity 服务：

("update juicity / 更新 Juicity" is currently experimental and limited to juicity_en.sh)

- 启动 Juicity：`bash juicity.sh` 然后选择 "启动 Juicity"
- 停止 Juicity：`bash juicity.sh` 然后选择 "停止 Juicity"
- 重启 Juicity：`bash juicity.sh` 然后选择 "重启 Juicity"
- 修改配置：`bash juicity.sh` 然后选择 "修改 Juicity 配置"
- <del>更新 Juicity：`bash juicity.sh` 然后选择 "更新 Juicity" 
- 查看配置：`bash juicity.sh` 然后选择 "显示 Juicity 配置"

## 贡献

如果你有任何改进或建议，欢迎提交 Issue 或 Pull Request。让我们一起完善这个脚本，使其更加强大和实用。

## 许可证

本项目基于 GNU General Public License v3.0 许可证开源。详细信息请参阅 [LICENSE](LICENSE) 文件。

## 赞助支持

如果这个脚本对你有所帮助，欢迎通过以下方式支持我们：

- 爱发电：https://afdian.net/a/Misaka-blog

![afdian-MisakaNo の 小破站](https://user-images.githubusercontent.com/122191366/211533469-351009fb-9ae8-4601-992a-abbf54665b68.jpg)

感谢你的支持和鼓励！
