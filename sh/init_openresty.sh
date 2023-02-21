#!bin/bash

source /sh/init_nginx_env.sh

echo "下面开启openresty"
/usr/bin/openresty -g "daemon off;"