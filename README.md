# gcp-cloudcdn-onekeydeployment 简介

GCP(Google Cloud Platform) 创建 Cloud CDN 对于初学者来说并不是十分的友好! 

如需配置多个加速域名，较耗时且易出错.

本项目能通过一键脚本创建外部源站 CDN, 并统计域名信息.


## 脚本执行方式

1. 登陆 GCP Console，打开 Cloud Shell
2. 将此脚本上传到 GCP 的 Cloud Shell 中
3. 执行以下命令:

```sh
bash deploy_gcp_cdn.sh  accelerate_domain  source_domain  source_protocol  source_host  cache_param  cache_seconds
```

## 参数说明

```sh
#
# accelerate_domain: 前端加速域名, 不需要带 http(s)://
# source_domain: 回源域名, 不需要带 http(s)://
# source_protocol: 回源协议, http or https
# source_host: 回源主机, 主机名, 不需要带 http(s)://
# cache_no_param: 是否去参缓存, yes or no
# cache_seconds: 缓存秒数，最大 31622400 秒
#
```

如果需要删除域名，请在参数最后增加 `remove`  ，请谨慎操作!


