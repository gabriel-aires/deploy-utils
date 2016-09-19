#!/bin/bash

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1

if [ "$(id -u)" -ne "0" ]; then
    log "ERRO" "Requer usuário root."
    exit 1
fi

trap "log 'ERRO' 'Script finalizado com erro'; exit 1; exit 1" SIGQUIT SIGTERM SIGHUP ERR
outdated=true

while $outdated; do

    version_sequential=$(cat $version_file 2> /dev/null || echo 0)

######################### 3.3

    if [ "$version_sequential" -lt "95" ]; then
        log "INFO" "Aplicando migrações para a versão 95..."

        find $app_conf_dir/ -type f -iname '*.conf' | while read config; do
            touch $config
            cp $config $config.bak
            sed -rn 's/^share=/share_desenvolvimento=/p' $config >> $config
            sed -rn 's/^share=/share_homologacao=/p' $config >> $config
            sed -rn 's/^share=/share_producao=/p' $config >> $config
            sed -rn 's/^share=/share_sustentacao=/p' $config >> $config
            sed -rn 's/^share=/share_teste=/p' $config >> $config
            sed -i -r '/^share=/d' $config
            reset_config.sh "$config" "$install_dir/template/app.template"
            chown $apache_user:$apache_group $config
        done

        echo "95" > $version_file

######################### 3.4.2

    elif [ "$version_sequential" -lt "101" ]; then
        log "INFO" "Aplicando migrações para a versão 101..."

        find $gent_conf_dir/ -type f -iname '*.conf' | while read config; do
            grep -E "^agent_name=[\"']?jboss_4_5[\"']?$" $config > /dev/null || continue
            touch $config
            cp $config $config.bak
            echo "log_limit='100'" >> $config
            reset_config.sh "$config" "$src_dir/agents/template/jboss_4_5.template"
            chown $apache_user:$apache_group $config
        done

        echo "101" > $version_file

######################## LATEST

    elif [ "$version_sequential" -le "$version_latest" ]; then
        echo "$version_latest" > $version_file
        echo "$release_latest" > $release_file
        outdated=false
    fi

done

log "INFO" "Migrações realizadas com sucesso."
