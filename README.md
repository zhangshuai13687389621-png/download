# CentOS 7 离线安装指南

这份指南说明了如何使用本仓库中 GitHub Actions 构建出的离线包在没有外网的 CentOS 7 服务器上进行安装。

---

## 目录
1. [离线安装 Cron (cronie) 及依赖](#1-离线安装-cron-cronie-及依赖)
2. [离线安装 Python 3.8.20 及 Kazoo 包](#2-离线安装-python-3820-及-kazoo-包)

---

## 1. 离线安装 Cron (cronie) 及依赖

从 GitHub Actions 的 Artifacts 下载 `cronie-centos7-offline.zip`（解压后会得到 `centos7-cron-offline-packages.tar.gz`）。

### 步骤清单：

**1. 上传文件到 CentOS 7 服务器**  
将 `.tar.gz` 文件通过内网工具（如 WinSCP, MobaXterm 的 SFTP 等）上传到服务器的某目录下。

**2. 解压安装包**
```bash
# 创建一个单独的目录存放 RPM 包
mkdir -p /opt/offline/cronie
cd /opt/offline/cronie

# 解压缩 tar 文件
tar -zxvf /上传的路径/centos7-cron-offline-packages.tar.gz
```

**3. 安装所有的 RPM 包**  
由于包含依赖关系，最简单和安全的方法就是利用 `yum` 统一解决当前目录下的离线包依赖并进行安装。
```bash
# 在当前解压出了大量 .rpm 的目录下执行：
sudo yum localinstall -y *.rpm
```

**4. 启动并启用服务**
```bash
# 开启 crond 服务
sudo systemctl start crond

# 设置为默认开机自启
sudo systemctl enable crond

# 检查服务状态是否为 running
sudo systemctl status crond
```
至此，Cron 服务就可以在 CentOS 7 离线环境运行了。您可以通过 `crontab -e` 编写您的定时任务。

---

## 2. 离线安装 Python 3.8.20 及 Kazoo 包

从 GitHub Actions 的 Artifacts 下载对应打包出来的 `kazoo-py3.8.20-centos7-offline.zip`（解压后会得到类似 `centos7-python-3.8.20-kazoo-offline.tar.gz`）。

> **注意：** GitHub Actions 提供下载的所有 Python 依赖都是给 **Python 3.8 甚至更高版本准备的 `.whl` 或 `tar.gz` 文件**。这代表您的目标 CentOS 7 服务器必须事先已经安装好对应或更高的 Python 环境（CentOS 7 默认只有 Python 2.7 不足以支持现在的众多包）。如果您尚未有 Python 3.8 离线安装过，请务必先将 Python3 的离线源码放入机器进行编译或者内网安装 Python 3。

### 步骤清单（假设您的 CentOS 7 已经安装了 Python3和pip）：

**1. 上传文件到 CentOS 7 服务器**  
将 `.tar.gz` 上传至目标服务器。

**2. 解压所有的离线的 PIP 安装包**
```bash
mkdir -p /opt/offline/python_pkgs
cd /opt/offline/python_pkgs

tar -zxvf /上传的路径/centos7-python-3.8.20-kazoo-offline.tar.gz
```

**3. 离线安装依赖包**  
使用 `pip` 通过指定目录中的文件进行本地依赖寻找并且不检索远程仓库。
```bash
# 这里的 python3 请替换为您主机实际上安装的命令名（例如 python3.8 或者 python3）
# --no-index: 告诉 pip 不要去 PyPI 联网寻找
# --find-links . : 告诉 pip 就在当前目录 "." 下面寻找所有的安装包
python3 -m pip install --no-index --find-links . kazoo
```

如果您的安装过程非常顺利，`pip` 就会按顺序将 `kazoo` 和它对应的传递依赖离线全部安装结束！您可以在命令行中打开 `python3`，并输入 `import kazoo` 检查是否成功。
