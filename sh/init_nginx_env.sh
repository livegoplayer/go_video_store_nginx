#!/bin/bash
#这个脚本用户初始化nginx相关的初始化环境变量，需要在docker运行之前source一下
#判断WORK_PROCESSES这个env是否存在，如果存在的话则是已经人为设置了，无需更改
#获取当前容器最多可以利用几个cpu核数，nginx将设置worker_processes为可用cpu核数
#####################################初始化nginx.conf中需要使用的环境变量#########################
#获取固定位数的BinnaryStr
getBaseBinaryStr(){
	#获取字符串长度
	local len=${#1}
	local cnt=$((${#2}-$len))
	local returnStr="$1"
	while [[ $cnt>0 ]] 
	do 
		returnStr="0$returnStr"
		cnt=$(($cnt-1))
	done

	echo $returnStr
}

#整数转二进制字符串
toBinaryStr(){
	echo $(echo "obase=2; ibase=10; $((2**($1-1)))"|bc)
}

#worker_processes
if [[ -z $WORK_PROCESSES ]]
then
#直接获取逻辑cpu核数并设置为环境变量
	export WORK_PROCESSES=$(cat /proc/cpuinfo |grep "processor"|wc -l);
fi

#nginx的cpu配置优化，给每一个worker进程分配一个cpu核
#worker_cpu_affinity
#算出最大的cpu核数写法
if [[ -z $WORKER_CPU_AFFINITY && $WORK_PROCESSES>0 ]]
then 
	WORKER_CPU_AFFINITY="";
	maxwcanum=$WORK_PROCESSES
	maxwca="$(toBinaryStr $maxwcanum)"
	wcanum=$maxwcanum;
	while [[ "$wcanum" > 0 ]]     # while test "$var1" != "end"
	do
		wca="$(toBinaryStr $wcanum)"
		wca=$(getBaseBinaryStr $wca $maxwca)
	  	WORKER_CPU_AFFINITY=$wca" "$WORKER_CPU_AFFINITY;
	  	wcanum=$((wcanum>>1))
	done
	export WORKER_CPU_AFFINITY=$WORKER_CPU_AFFINITY;
fi

unset getBaseBinaryStr toBinaryStr

#ulimit -n <文件数目> 　指定同一时间最多可开启的文件数。
#cat /proc/sys/fs/file-max 即file-max是设置 系统所有进程一共可以打开的文件数量
#关于nginx设置nginx可以利用的最大的资源数量，因为nginx一切皆文件，所以又是最多打开的文件资源描述符的数量，因为查过这两个会报错，所以取最小的
#如果查过了nginx设置的数量会报502
if [[ -z $WORKER_RLIMIT_NOFILE  ]]
then
	fileMax=$(cat /proc/sys/fs/file-max)
	unlimit=$(ulimit -n)
	if [[ fileMax>unlimit ]]
	then
		WORKER_RLIMIT_NOFILE=$unlimit
	else
		WORKER_RLIMIT_NOFILE=$fileMax
	fi
fi

if [[ -z $WORKER_CONNECTIONS  ]]
then
	export WORKER_CONNECTIONS=$(($WORKER_RLIMIT_NOFILE/$WORK_PROCESSES))
fi



#client_header_buffer_size 请求头缓存区大小，一般设置为系统分页大小
if [[ -z $ClIENT_HEADER_BUFFER_SIZE  ]]
then
	export ClIENT_HEADER_BUFFER_SIZE=$(getconf PAGESIZE)
fi

#client_body_buffer_size
if [[ -z $ClIENT_BODY_BUFFER_SIZE  ]]
then
	export ClIENT_BODY_BUFFER_SIZE=10m
fi

#client_max_body_size
if [[ -z $ClIENT_MAX_BODY_SIZE  ]]
then
	export ClIENT_MAX_BODY_SIZE=1024m
fi

#proxy_buffer_size 响应头缓冲区大小，设置为系统分页大小
if [[ -z $PROXY_BUFFER_SIZE  ]]
then
	export PROXY_BUFFER_SIZE=$(getconf PAGESIZE)
fi

#proxy_busy_buffers_size 响应头缓冲区大小，设置为系统分页大小
if [[ -z $PROXY_BUSY_BUFFERS_SIZE  ]]
then
	export PROXY_BUSY_BUFFERS_SIZE=$((2*$(getconf PAGESIZE)))
fi

#proxy_temp_path
if [[ -z $PROXY_TEMP_PATH ]]
then
	export PROXY_TEMP_PATH=/tmp/proxy_temp_path
	if [ ! -d $PROXY_TEMP_PATH ]
	then
  		mkdir -p $PROXY_TEMP_PATH
	fi
fi

#client_body_temp_path
if [[ -z $CLIENT_BODY_TEMP_PATH ]]
then
	export CLIENT_BODY_TEMP_PATH=/tmp/client_temp_path
	if [ ! -d $CLIENT_BODY_TEMP_PATH ]
	then
  		mkdir -p $CLIENT_BODY_TEMP_PATH
	fi
fi

#logpath
if [[ -z $LOGPATH ]]
then
	export LOGPATH=/apps/logs
	if [ ! -d $LOGPATH ]
	then
  		mkdir -p $LOGPATH
	fi
fi


#环境设置,如果没有指定则是生产环境
if [[ -z $PROCESS_ENV ]]
then
	export PROCESS_ENV="dev"
fi

#lua的redis 配置
if [[ -z $LUA_REDIS_HOST ]]
then
	export LUA_REDIS_HOST=127.0.0.1
fi
if [[ -z $LUA_REDIS_PORT ]]
then
	export LUA_REDIS_PORT=6379
fi
if [[ -z $LUA_REDIS_AUTH ]]
then 
	export LUA_REDIS_AUTH=""
fi
if [[ -z $LUA_REDIS_DB ]]
then 
	export LUA_REDIS_DB="3"
fi

#FILE_SERVER_NAME
if [[ -z $VIDEO_STORE_NAME ]]
then
	export VIDEO_STORE_NAME="_"
fi

cd /usr/local/openresty/nginx/conf
if [[ -f /usr/local/openresty/nginx/conf/nginx.conf ]]
then
	rm /usr/local/openresty/nginx/conf/nginx.conf
fi

cp /usr/local/openresty/nginx/conf/nginx_template.conf /usr/local/openresty/nginx/conf/nginx.conf  

export WORKER_RLIMIT_NOFILE=${WORKER_RLIMIT_NOFILE}
export WORKER_CONNECTIONS=${WORKER_CONNECTIONS}

envsubst '$LOGPATH $VIDEO_STORE_NAME $user,$WORK_PROCESSES,${WORKER_RLIMIT_NOFILE},$WORKER_CPU_AFFINITY $WORKER_CONNECTIONS $ClIENT_HEADER_BUFFER_SIZE $ClIENT_BODY_BUFFER_SIZE'< /usr/local/openresty/nginx/conf/nginx_template.conf > /usr/local/openresty/nginx/conf/nginx.conf

if [[ -f /etc/nginx/config/http_limit_optimization.conf ]]
then
	rm /etc/nginx/config/http_limit_optimization.conf
fi

cp /etc/nginx/config/http_limit_optimization_template.conf /etc/nginx/config/http_limit_optimization.conf
envsubst '$ClIENT_HEADER_BUFFER_SIZE,$ClIENT_BODY_BUFFER_SIZE,$CLIENT_BODY_TEMP_PATH,$ClIENT_MAX_BODY_SIZE'< /etc/nginx/config/http_limit_optimization_template.conf > /etc/nginx/config/http_limit_optimization.conf

if [[ -f /etc/nginx/config/api_proxy.conf ]]
then
	rm /etc/nginx/config/api_proxy.conf
fi

cp /etc/nginx/config/api_proxy_template.conf /etc/nginx/config/api_proxy.conf
envsubst '$PROXY_BUFFER_SIZE $PROXY_BUSY_BUFFERS_SIZE'< /etc/nginx/config/api_proxy_template.conf > /etc/nginx/config/api_proxy.conf

if [[ -f /etc/nginx/config/grpc_proxy.conf ]]
then
	rm /etc/nginx/config/grpc_proxy.conf
fi

cp /etc/nginx/config/grpc_proxy_template.conf /etc/nginx/config/grpc_proxy.conf
envsubst '$PROXY_BUFFER_SIZE'< /etc/nginx/config/grpc_proxy_template.conf > /etc/nginx/config/grpc_proxy.conf
