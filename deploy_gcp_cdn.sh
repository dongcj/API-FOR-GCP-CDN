#!/bin/bash
# Author: krrish
# Create or Update scripts for Cloud CDN
# usage: ./$0 <accelerate_domain> <source_domain> <source_protocol> <source_host> <cache_no_param> <cache_seconds>
#
# accelerate_domain: 前端加速域名, 不需要带 http(s)://
# source_domain: 回源域名, 不需要带 http(s)://
# source_protocol: 回源协议, http or https
# source_host: 回源主机, 主机名, 不需要带 http(s)://
# cache_no_param: 是否去参缓存, yes or no
# cache_seconds: 缓存秒数，最大 31622400 秒
#

# 如果不指定 PROJECT_ID, 即为当前所在 project
# 查看当前环境所在项目: gcloud config get-value project 
PROJECT_ID=""

# CDN 域名配置表, 每次配置完后, 将此次配置域名写入一个 CSV 文件中
DOMAIN_CONFIG_FILE="cdn_domain_config.csv"

# 日志位置
LOG_FILE=/tmp/`basename ${0%.*}`.log


ACCELERATE_DOMAIN=$1
SOURCE_DOMAIN=$2
SOURCE_PROTOCOL=$3
SOURCE_HOST=$4
CACHE_NO_PARAM=$5
CACHE_SECONDS=$6

ACCELERATE_DOMAIN_SERVICENAME=${ACCELERATE_DOMAIN//./-}


if [ -z "$PROJECT_ID" ]; then 
    PROJECT_STR=" --quiet --verbosity=critical"
else
    PROJECT_STR=" --project=$PROJECT_ID --quiet --verbosity=critical"
fi


Is_Domain() {

    object=$1
    if [ `echo "$object" | xargs -n 1 | wc -l` -ne 1 ]; then
        echo "object \"$object\" is not \"domain\" type"
        return 1
    fi

    # only can contain ".[0-9a-zA-Z-]"
    if [ -n "`echo "$object" | tr -d '.\[0-9a-zA-Z-\]'`" ]; then
        echo "object \"$object\" is not \"domain\" type"
        return 1
    fi

    # the domain shout contain at least "xx.xx"
    if ! echo $object | grep "[0-9a-zA-Z-]\{1,\}\.[0-9a-zA-Z]\{1,\}" >/dev/null 2>&1;then
        echo "object \"$object\" is not \"domain\" type"
        return 1
    fi
}

if [ -z "$ACCELERATE_DOMAIN" -o -z "$SOURCE_DOMAIN" -o -z "$SOURCE_PROTOCOL" -o \
     -z "$SOURCE_HOST" -o -z "$CACHE_NO_PARAM" -o -z "$CACHE_SECONDS" ]; then
    echo "usage error, exit"; 
    echo "usage: $0 <ACCELERATE_DOMAIN> <SOURCE_DOMAIN> <SOURCE_PROTOCOL> <SOURCE_HOST> <CACHE_NO_PARAM> <CACHE_SECONDS>"
    echo "ACCELERATE_DOMAIN---加速域名"
    echo "SOURCE_DOMAIN---回源域名"
    echo "SOURCE_PROTOCOL---回源协议"
    echo "SOURCE_HOST---回源主机"
    echo "CACHE_NO_PARAM---是否去参缓存"
    echo "CACHE_SECONDS---缓存秒数"
    echo 
    exit 1;
fi

# check the args
Is_Domain $ACCELERATE_DOMAIN || exit 2
Is_Domain $SOURCE_DOMAIN || exit 2
Is_Domain $SOURCE_HOST || exit 2

# the biggest cache seconds is 31622400
if [ $CACHE_SECONDS -gt 31622400 ]; then
    CACHE_SECONDS=31622400
fi


case $SOURCE_PROTOCOL in
    http|HTTP) SOURCE_PORT=80;
    ;;
    https|HTTPS) SOURCE_PORT=443;
    ;;
    *) echo "SOURCE_PROTOCOL must be http / https" && exit 3
esac

case $CACHE_NO_PARAM in
    yes|YES) CACHE_NO_PARAM="yes";
    ;;
    no|NO) CACHE_NO_PARAM="no";
    ;;
    *) echo "CACHE_NO_PARAM must be yes / no" && exit 4
esac

# name settings
export NEG_NAME=neg-$ACCELERATE_DOMAIN_SERVICENAME
export BACKEND_SERIVCE_NAME=bs-$ACCELERATE_DOMAIN_SERVICENAME
export URLMAP_NAME=lb-$ACCELERATE_DOMAIN_SERVICENAME
export TARGET_HTTP_PROXY_NAME=target-http-$ACCELERATE_DOMAIN_SERVICENAME
export TARGET_HTTPS_PROXY_NAME=target-https-$ACCELERATE_DOMAIN_SERVICENAME
export IPV4_RESERVED_NAME=ipv4-reserved-$ACCELERATE_DOMAIN_SERVICENAME
export IPV6_RESERVED_NAME=ipv6-reserved-$ACCELERATE_DOMAIN_SERVICENAME
export FORWARD_RULE_IPV4_HTTP=fr-ipv4-http-$ACCELERATE_DOMAIN_SERVICENAME
export FORWARD_RULE_IPV4_HTTPS=fr-ipv4-https-$ACCELERATE_DOMAIN_SERVICENAME
export FORWARD_RULE_IPV6_HTTP=fr-ipv6-http-$ACCELERATE_DOMAIN_SERVICENAME
export FORWARD_RULE_IPV6_HTTPS=fr-ipv6-https-$ACCELERATE_DOMAIN_SERVICENAME


Echo_To_Log() {
  LOGTIME='eval date "+%Y-%m-%d %H:%M:%S"'
  local info="$*"
  # echo -e "`$LOGTIME` $info"
  echo -e "`$LOGTIME` $info" >>${LOG_FILE} 2>&1

}


if [ "$7" == "remove" ]; then

    Echo_To_Log "############ deleting begin ############"
    Echo_To_Log "delete forwarding rules"
    gcloud compute forwarding-rules delete $FORWARD_RULE_IPV4_HTTP $PROJECT_STR --global
    gcloud compute forwarding-rules delete $FORWARD_RULE_IPV4_HTTPS $PROJECT_STR --global
    gcloud compute forwarding-rules delete $FORWARD_RULE_IPV6_HTTP $PROJECT_STR --global
    gcloud compute forwarding-rules delete $FORWARD_RULE_IPV6_HTTPS $PROJECT_STR --global
    
    Echo_To_Log "delete target proxies"
    gcloud compute target-http-proxies delete $TARGET_HTTP_PROXY_NAME $PROJECT_STR
    gcloud compute target-https-proxies delete $TARGET_HTTPS_PROXY_NAME $PROJECT_STR
    
    Echo_To_Log "delete url map"
    gcloud beta compute url-maps  delete $URLMAP_NAME $PROJECT_STR
    
    Echo_To_Log "delete backend services"
    gcloud beta compute backend-services delete $BACKEND_SERIVCE_NAME $PROJECT_STR --global
    
    Echo_To_Log "delete NEG"
    gcloud compute network-endpoint-groups delete $NEG_NAME $PROJECT_STR --global
    
    Echo_To_Log "delete ip addresses"
    gcloud compute addresses delete $IPV4_RESERVED_NAME $PROJECT_STR --global
    gcloud compute addresses delete $IPV6_RESERVED_NAME $PROJECT_STR --global
    
    # call the scripts to delete 
    if [ -f $DOMAIN_CONFIG_FILE ]; then
    
        # if exists the urlmap, delete 
        if grep -wq $URLMAP_NAME $DOMAIN_CONFIG_FILE; then
            Echo_To_Log "delete $URLMAP_NAME in config files"
            sed -i "/$URLMAP_NAME/d" $DOMAIN_CONFIG_FILE
        fi
        
    fi
    
    Echo_To_Log "############ deleting end ############"
    
    exit 99
fi

#set -euo pipefail
#trap "echo 'error: Script failed: see failed command above'" ERR

Echo_To_Log "-------------------------------"
Echo_To_Log "ACCELERATE_DOMAIN: $ACCELERATE_DOMAIN"
Echo_To_Log "SOURCE_DOMAIN: $SOURCE_DOMAIN"
Echo_To_Log "SOURCE_PROTOCOL: $SOURCE_PROTOCOL"
Echo_To_Log "SOURCE_HOST: $SOURCE_HOST"
Echo_To_Log "CACHE_NO_PARAM: $CACHE_NO_PARAM"
Echo_To_Log "CACHE_SECONDS: $CACHE_SECONDS"
Echo_To_Log "-------------------------------"

# Create NEG
ORIGIN_NEG_NAME=`gcloud compute network-endpoint-groups list \
    --filter="name=$NEG_NAME" \
    --format="csv[no-heading](name)"`
    
if [ -z "$ORIGIN_NEG_NAME" ]; then
    UPDATE=false
    Echo_To_Log "creating neg $NEG_NAME"
    gcloud compute \
    network-endpoint-groups create $NEG_NAME \
      --project=$PROJECT_ID \
      --subnet=default \
      --network-endpoint-type=INTERNET_FQDN_PORT \
      --default-port=$SOURCE_PORT \
      --global >>$LOG_FILE 2>&1
else
    UPDATE=true
    Echo_To_Log "skip neg create"
fi

NEG_ENDPOINT=`gcloud compute network-endpoint-groups \
  list-network-endpoints $NEG_NAME $PROJECT_STR --global \
  --format="csv[no-heading](FQDN,PORT)"`
  
if [ -z "$NEG_ENDPOINT" ]; then
  
    Echo_To_Log "adding endpoint fqdn: $SOURCE_DOMAIN,port=$SOURCE_PORT for neg: $NEG_NAME"
    gcloud compute \
    network-endpoint-groups update $NEG_NAME $PROJECT_STR \
      --add-endpoint=fqdn=$SOURCE_DOMAIN,port=$SOURCE_PORT \
      --global >>$LOG_FILE 2>&1
else
    # if update 
    if $UPDATE; then
    
        # if the fqdn,port == SOURCE_DOMAIN,SOURCE_PROTOCOL
        if [ "$NEG_ENDPOINT" == "${SOURCE_DOMAIN},${SOURCE_PORT}" ]; then
            Echo_To_Log "skip endpoint add"
            
        else
            CUR_FQDN=`echo ${NEG_ENDPOINT} | awk -F',' '{print $1}'`
            CUR_PORT=`echo ${NEG_ENDPOINT} | awk -F',' '{print $2}'`
            # first, delete the endpoint
            
            Echo_To_Log "updating endpoint fqdn"
            Echo_To_Log "deleting endpoint fqdn: $CUR_FQDN,port=$CUR_PORT for neg: $NEG_NAME"
            gcloud compute network-endpoint-groups update  $NEG_NAME $PROJECT_STR \
              --remove-endpoint=fqdn=$CUR_FQDN,port=$CUR_PORT \
              --global >>$LOG_FILE 2>&1
              
            # then, add a new endpoint
            Echo_To_Log "adding endpoint fqdn: $SOURCE_DOMAIN,port=$SOURCE_PORT for neg: $NEG_NAME"
            gcloud compute network-endpoint-groups update $NEG_NAME $PROJECT_STR \
              --add-endpoint=fqdn=$SOURCE_DOMAIN,port=$SOURCE_PORT \
              --global >>$LOG_FILE 2>&1
        fi
    

    fi
    
fi


CUR_BACKEND_SERIVCE=`gcloud beta compute backend-services describe $BACKEND_SERIVCE_NAME $PROJECT_STR \
   --format="csv[no-heading](cdnPolicy.cacheKeyPolicy.includeQueryString,customRequestHeaders)" --global`
   
   
if [ $CACHE_NO_PARAM = "yes" ]; then
    CACHE_NO_PARAM_IN_RESULT="False"
    PARAM_INCLUDE_QUERY_STRING=" --no-cache-key-include-query-string"
else 
    CACHE_NO_PARAM_IN_RESULT="True"
    PARAM_INCLUDE_QUERY_STRING=" --cache-key-include-query-string"
fi

if [ -z "$CUR_BACKEND_SERIVCE" ]; then
  
    Echo_To_Log "creating backend-services $BACKEND_SERIVCE_NAME"
    gcloud beta compute \
    backend-services create $BACKEND_SERIVCE_NAME $PROJECT_STR\
      --protocol=HTTP \
      --global \
      --enable-cdn \
      --enable-logging \
      --no-cache-key-include-host \
      --no-cache-key-include-protocol \
      $PARAM_INCLUDE_QUERY_STRING \
      --default-ttl=$CACHE_SECONDS \
      --cache-mode=force_cache_all \
      --custom-request-header="Host: $SOURCE_HOST" \
      --client-ttl=86400 \
      --timeout=600 >>$LOG_FILE 2>&1
else

    if $UPDATE; then
    
        # if the fqdn,port == SOURCE_DOMAIN,SOURCE_PROTOCOL
        if [ "$CUR_BACKEND_SERIVCE" == "${CACHE_NO_PARAM_IN_RESULT},Host: ${SOURCE_HOST}" ]; then
            Echo_To_Log "skip endpoint add"
            
        else
            
            Echo_To_Log "updating backend-service: $BACKEND_SERIVCE_NAME"
            
            gcloud beta compute backend-services update $BACKEND_SERIVCE_NAME $PROJECT_STR \
              --protocol=HTTP \
              --global \
              --enable-cdn \
              --enable-logging \
              --no-cache-key-include-host \
              --no-cache-key-include-protocol \
              $PARAM_INCLUDE_QUERY_STRING \
              --default-ttl=$CACHE_SECONDS \
              --cache-mode=force_cache_all \
              --custom-request-header="Host: $SOURCE_HOST" \
              --client-ttl=86400 \
              --timeout=600 >>$LOG_FILE 2>&1
            
            
        fi
    fi
fi

# add backend
if [ -z "`gcloud beta compute backend-services list $PROJECT_STR \
  --filter="NAME=$BACKEND_SERIVCE_NAME" \
  --format="csv[no-heading](backends)"`" ]; then
  
    Echo_To_Log "adding backend neg: $NEG_NAME for backend: $BACKEND_SERIVCE_NAME"
    gcloud compute \
    backend-services add-backend $BACKEND_SERIVCE_NAME $PROJECT_STR \
      --capacity-scaler=1 \
      --global-network-endpoint-group \
      --network-endpoint-group $NEG_NAME \
      --global >>$LOG_FILE 2>&1
else
    Echo_To_Log "skip backend add"
fi
    
# create urlmap
if [ -z "`gcloud beta compute url-maps list $PROJECT_STR \
  --filter="NAME=$URLMAP_NAME" \
  --format="csv[no-heading](name)"`" ]; then
  
    Echo_To_Log "creating urlmap: $URLMAP_NAME with default service: $BACKEND_SERIVCE_NAME"
    gcloud compute url-maps create $URLMAP_NAME $PROJECT_STR \
      --default-service $BACKEND_SERIVCE_NAME >>$LOG_FILE 2>&1
else
    Echo_To_Log "skip urlmap create"
fi


# create target http proxy
if [ -z "`gcloud compute target-http-proxies list \
  --filter="NAME=$TARGET_HTTP_PROXY_NAME" \
  --format="csv[no-heading](name)"`" ]; then
    
    Echo_To_Log "creating target-http-proxy: $TARGET_HTTP_PROXY_NAME for urlmap: $URLMAP_NAME"
    gcloud compute target-http-proxies create $TARGET_HTTP_PROXY_NAME $PROJECT_STR \
      --url-map $URLMAP_NAME >>$LOG_FILE 2>&1
else
    Echo_To_Log "skip target-http-proxy create"
fi


# get the best certs for this domain
Echo_To_Log "getting the best certs for $ACCELERATE_DOMAIN"

ALL_SSL_CERTS=`gcloud beta compute ssl-certificates list $PROJECT_STR \
  --format="csv[no-heading](name)"`


# First：find the cert match name: cert-$ACCELERATE_DOMAIN_SERVICENAME
CERTS_MATCH=`echo "$ALL_SSL_CERTS" | grep -w "cert-${ACCELERATE_DOMAIN_SERVICENAME}"`

if [ -n "$CERTS_MATCH" ]; then
    BEST_CERT=`echo "$CERTS_MATCH" | sed -n '1p'`
    
else
  
    # if match cert-FirstLevelDOMAIN;
    FIRST_LEVEL_DOMAIN=${ACCELERATE_DOMAIN_SERVICENAME#*-}
    
    # if has the wildcard domain
    WILDCARD_DOMAIN=`echo "$ALL_SSL_CERTS" | grep -w "cert-$FIRST_LEVEL_DOMAIN"`
    
    if [ -n "$WILDCARD_DOMAIN" ]; then
        
        for wd in $WILDCARD_DOMAIN; do
    
            # look into the ssl cert
            if gcloud beta compute ssl-certificates describe  $wd $PROJECT_STR \
              --format=json | jq ".subjectAlternativeNames" | grep -q "*"; then
                
                BEST_CERT=$wd
                break
            else
                continue
            fi
        done
        
        
    else
        unset BEST_CERT
    fi
    
fi



# create target https proxy
if [ -z "$BEST_CERT" ]; then

    Echo_To_Log "[ no cert found ], so skip create https target proxy"

else
    Echo_To_Log "The match cert: $BEST_CERT"
    if [ -z "`gcloud compute target-https-proxies list $PROJECT_STR \
      --filter="NAME=$TARGET_HTTPS_PROXY_NAME" \
      --format="csv[no-heading](name)"`" ]; then
    
        Echo_To_Log "creating target-https-proxy: $TARGET_HTTPS_PROXY_NAME for urlmap: $URLMAP_NAME"
        gcloud compute target-https-proxies create $TARGET_HTTPS_PROXY_NAME $PROJECT_STR \
          --url-map $URLMAP_NAME \
          --ssl-certificates $BEST_CERT >>$LOG_FILE 2>&1
    else
        Echo_To_Log "skip target-https-proxy create"
    fi
    
fi

# create reserved ipv4 address
IPV4_ADDRESS_FORMER=`gcloud compute addresses list $PROJECT_STR \
  --filter="NAME=$IPV4_RESERVED_NAME" \
  --format="csv[no-heading](address)"`

if [ -z "$IPV4_ADDRESS_FORMER" ]; then

    Echo_To_Log "creating ipv4 address for $IPV4_RESERVED_NAME"
    # create reserved ip address
    gcloud compute addresses create $IPV4_RESERVED_NAME $PROJECT_STR --global >>$LOG_FILE 2>&1
    # get ip address 
    IPV4_RESERVED=`gcloud compute addresses list $PROJECT_STR \
      --filter="NAME=$IPV4_RESERVED_NAME" \
      --format="csv[no-heading](address)"`
else
    IPV4_RESERVED=$IPV4_ADDRESS_FORMER
fi

Echo_To_Log "ipv4 address for $IPV4_RESERVED_NAME is: $IPV4_RESERVED"
      

if [ -n "$BEST_CERT" ]; then

    # create reserved ipv6 address
    IPV6_ADDRESS_FORMER=`gcloud compute addresses list $PROJECT_STR \
      --filter="NAME=$IPV6_RESERVED_NAME" \
      --format="csv[no-heading](address)"`

    if [ -z "$IPV6_ADDRESS_FORMER" ]; then

        Echo_To_Log "creating ipv6 address for $IPV6_RESERVED_NAME"

        # create reserved ip address
        gcloud compute addresses create $IPV6_RESERVED_NAME $PROJECT_STR \
          --global --ip-version=ipv6 >>$LOG_FILE 2>&1
        # get ip address 
        IPV6_RESERVED=`gcloud compute addresses list $PROJECT_STR \
          --filter="NAME=$IPV6_RESERVED_NAME" \
          --format="csv[no-heading](address)"`
    else
        IPV6_RESERVED=$IPV6_ADDRESS_FORMER
    fi

    Echo_To_Log "ipv6 address for $IPV6_RESERVED_NAME is: $IPV6_RESERVED"

else
    Echo_To_Log "skip ipv6 create because of none cert found"

fi


# create forwarding rules http
if [ -z "`gcloud compute forwarding-rules list \
  --filter="NAME=$FORWARD_RULE_IPV4_HTTP" \
  --format="csv[no-heading](name)"`" ]; then
  
    Echo_To_Log "creating forwarding-rule: $FORWARD_RULE_IPV4_HTTP for target-http-proxy: $TARGET_HTTP_PROXY_NAME"
    gcloud compute forwarding-rules create $FORWARD_RULE_IPV4_HTTP $PROJECT_STR \
      --global --target-http-proxy=$TARGET_HTTP_PROXY_NAME \
      --ports=80  --address=$IPV4_RESERVED >>$LOG_FILE 2>&1
else
    Echo_To_Log "skip forwarding-rules-ipv4-http create"
fi


if [ -z "`gcloud compute forwarding-rules list \
  --filter="NAME=$FORWARD_RULE_IPV6_HTTP" \
  --format="csv[no-heading](name)"`" ]; then
  
    Echo_To_Log "creating forwarding-rule: $FORWARD_RULE_IPV6_HTTP for target-http-proxy: $TARGET_HTTP_PROXY_NAME"
    gcloud compute forwarding-rules create $FORWARD_RULE_IPV6_HTTP $PROJECT_STR \
      --global --target-http-proxy=$TARGET_HTTP_PROXY_NAME \
      --ports=80 --address=$IPV6_RESERVED >>$LOG_FILE 2>&1
else
    Echo_To_Log "skip forwarding-rules-ipv6-http create"
fi


# create forwarding rules https
if [ -z "$BEST_CERT" ]; then
    Echo_To_Log "[ no cert found ], so skip create forwarding rule for https target proxy"

else


    if [ -z "`gcloud compute forwarding-rules list $PROJECT_STR \
      --filter="NAME=$FORWARD_RULE_IPV4_HTTPS" \
      --format="csv[no-heading](name)"`" ]; then
        
        Echo_To_Log "creating forwarding-rule: $FORWARD_RULE_IPV4_HTTPS for target-https-proxy: $TARGET_HTTPS_PROXY_NAME"
        gcloud compute forwarding-rules create $FORWARD_RULE_IPV4_HTTPS $PROJECT_STR \
        --global --target-https-proxy=$TARGET_HTTPS_PROXY_NAME --ports=443 \
        --address=$IPV4_RESERVED >>$LOG_FILE 2>&1
    else
        Echo_To_Log "skip forwarding-rules-ipv4-https create"
    fi
    
    if [ -z "`gcloud compute forwarding-rules list $PROJECT_STR \
      --filter="NAME=$FORWARD_RULE_IPV6_HTTPS" \
      --format="csv[no-heading](name)"`" ]; then
    
        Echo_To_Log "creating forwarding-rule: $FORWARD_RULE_IPV6_HTTPS for target-https-proxy: $TARGET_HTTPS_PROXY_NAME"
        gcloud compute forwarding-rules create $FORWARD_RULE_IPV6_HTTPS $PROJECT_STR \
        --global --target-https-proxy=$TARGET_HTTPS_PROXY_NAME --ports=443 \
        --address=$IPV6_RESERVED >>$LOG_FILE 2>&1
    else
        Echo_To_Log "skip forwarding-rules-ipv6-https create"
    fi
fi    

# Echo_To_Log "collecting domain config to $DOMAIN_CONFIG_FILE"
# bash collect_domain_config.sh >>$LOG_FILE 2>&1

Echo_To_Log "done"


