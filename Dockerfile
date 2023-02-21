# Dockerfile - Debian 10 Buster Fat - DEB version
# https://github.com/openresty/docker-openresty
#
# This builds upon the base OpenResty Buster image,
# adding useful packages and utilities.
#
# Currently it just adds the openresty-opm package.
#

ARG RESTY_IMAGE_BASE="openresty/openresty"
ARG RESTY_IMAGE_TAG="buster"

FROM ${RESTY_IMAGE_BASE}:${RESTY_IMAGE_TAG}

LABEL maintainer="Evan Wies <evan@neomantra.net>"

RUN sed -i s@/deb.debian.org/@/mirrors.aliyun.com/@g /etc/apt/sources.list
RUN sed -i s@/security.debian.org/@/mirrors.aliyun.com/@g /etc/apt/sources.list

# 安装opm包管理工具 
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openresty-opm \
    && apt-get install -y bc \
    && apt-get install -y golang \
    && apt-get install -y git \
    && apt-get -yqq install -y python-pip \ 
    && rm -rf /var/lib/apt/lists/*
#临时目录
COPY ./whl/*.* /tmp/

#安装Supervisor控制脚本
RUN pip2 install /tmp/*.*

# 更新时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

#需要添加的项目相关的用户和用户组
ENV user=www
ENV group=www
RUN groupadd -r $group && useradd -g $group $user

#所有配置文件复制到/etc
#COPY ./conf /etc/

#所有sh文件复制到/sh
RUN mkdir /sh
COPY ./sh /sh/
RUN chmod +x ./sh/*.sh

#复制Supervisor文件
RUN mkdir /supervisor
COPY ./supervisor /supervisor

#调试目录
RUN mkdir /test

#go env
ENV GOPROXY=https://goproxy.io

