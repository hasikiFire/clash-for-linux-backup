#!/bin/bash

# 加载本地文件
# 加载本地系统函数库(Only for RHEL Linux)
# [ -f /etc/init.d/functions ] && source /etc/init.d/functions

#################### 脚本初始化任务 ####################

# 获取脚本工作目录绝对路径
export Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

# 加载.env变量文件
source $Server_Dir/.env

# 给二进制启动程序、脚本等添加可执行权限
chmod +x $Server_Dir/bin/*
chmod +x $Server_Dir/scripts/*
chmod +x $Server_Dir/tools/subconverter/subconverter

#################### 变量设置 ####################

Conf_Dir="$Server_Dir/conf"
Temp_Dir="$Server_Dir/temp"
Log_Dir="$Server_Dir/logs"

# 将 CLASH_URL 变量的值赋给 URL 变量，并检查 CLASH_URL 是否为空
URL=${CLASH_URL:?Error: CLASH_URL variable is not set or empty}

# 获取 CLASH_SECRET 值，如果不存在则生成一个随机数
Secret=${CLASH_SECRET:-$(openssl rand -hex 32)}

#################### 函数定义 ####################

# 自定义action函数，实现通用action功能
success() {
	echo -en "\\033[60G[\\033[1;32m  OK  \\033[0;39m]\r"
	return 0
}

failure() {
	local rc=$?
	echo -en "\\033[60G[\\033[1;31mFAILED\\033[0;39m]\r"
	[ -x /bin/plymouth ] && /bin/plymouth --details
	return $rc
}

action() {
	local STRING rc

	STRING=$1
	echo -n "$STRING "
	shift
	"$@" && success $"$STRING" || failure $"$STRING"
	rc=$?
	echo
	return $rc
}

# 判断命令是否正常执行 函数
if_success() {
	local ReturnStatus=$3
	if [ $ReturnStatus -eq 0 ]; then
		action "$1" /bin/true
	else
		action "$2" /bin/false
		exit 1
	fi
}

#################### 任务执行 ####################

## 获取CPU架构信息
# Source the script to get CPU architecture
source $Server_Dir/scripts/get_cpu_arch.sh

# Check if we obtained CPU architecture
if [[ -z "$CpuArch" ]]; then
	echo "Failed to obtain CPU architecture"
	exit 1
fi

export CpuArch=$CpuArch

## 临时取消环境变量
unset http_proxy
unset https_proxy
unset no_proxy
unset HTTP_PROXY
unset HTTPS_PROXY
unset NO_PROXY

## Clash 配置文件处理
echo -e '\n正在处理Clash配置文件...'

# 假设本地的配置文件路径为 $Conf_Dir/local_clash.yaml
Text3="配置文件config.yaml处理成功！"
Text4="配置文件config.yaml处理失败，退出启动！"

# 将本地文件复制到临时目录
\cp -a $Conf_Dir/local_clash.yaml $Temp_Dir/clash_config.yaml
ReturnStatus=$?
if_success $Text3 $Text4 $ReturnStatus

# 取出代理相关配置 
sed -n '/^proxies:/,$p' $Temp_Dir/clash_config.yaml > $Temp_Dir/proxy.txt

# 合并形成新的config.yaml
cat $Temp_Dir/templete_config.yaml > $Temp_Dir/config.yaml
cat $Temp_Dir/proxy.txt >> $Temp_Dir/config.yaml
\cp $Temp_Dir/config.yaml $Conf_Dir/

# Configure Clash Dashboard
Work_Dir=$(cd $(dirname $0); pwd)
Dashboard_Dir="${Work_Dir}/dashboard/public"
sed -ri "s@^# external-ui:.*@external-ui: ${Dashboard_Dir}@g" $Conf_Dir/config.yaml
sed -r -i '/^secret: /s@(secret: ).*@\1'${Secret}'@g' $Conf_Dir/config.yaml

## 启动Clash服务
echo -e '\n正在启动Clash服务...'
Text5="服务启动成功！"
Text6="服务启动失败！"
if [[ $CpuArch =~ "x86_64" || $CpuArch =~ "amd64"  ]]; then
	nohup $Server_Dir/bin/clash-linux-amd64 -d $Conf_Dir &> $Log_Dir/clash.log &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
elif [[ $CpuArch =~ "aarch64" ||  $CpuArch =~ "arm64" ]]; then
	nohup $Server_Dir/bin/clash-linux-arm64 -d $Conf_Dir &> $Log_Dir/clash.log &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
elif [[ $CpuArch =~ "armv7" ]]; then
	nohup $Server_Dir/bin/clash-linux-armv7 -d $Conf_Dir &> $Log_Dir/clash.log &
	ReturnStatus=$?
	if_success $Text5 $Text6 $ReturnStatus
else
	echo -e "\033[31m\n[ERROR] Unsupported CPU Architecture！\033[0m"
	exit 1
fi

# Output Dashboard access address and Secret
echo ''
echo -e "Clash Dashboard 访问地址: http://<ip>:9090/ui"
echo -e "Secret: ${Secret}"
echo ''

# 添加环境变量(root权限)
cat>/etc/profile.d/clash.sh<<EOF
# 开启系统代理
proxy_on() {
	export http_proxy=http://127.0.0.1:7890
	export https_proxy=http://127.0.0.1:7890
	export no_proxy=127.0.0.1,localhost
    	export HTTP_PROXY=http://127.0.0.1:7890
    	export HTTPS_PROXY=http://127.0.0.1:7890
 	export NO_PROXY=127.0.0.1,localhost
	echo -e "\033[32m[√] 已开启代理\033[0m"
}

# 关闭系统代理
proxy_off(){
	unset http_proxy
	unset https_proxy
	unset no_proxy
  	unset HTTP_PROXY
	unset HTTPS_PROXY
	unset NO_PROXY
	echo -e "\033[31m[×] 已关闭代理\033[0m"
}
EOF
