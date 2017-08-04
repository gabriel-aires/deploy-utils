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
            log "INFO" "Arquivo $config atualizado com sucesso."
        done

        echo "95" > $version_file

######################### 3.4.2

    elif [ "$version_sequential" -lt "101" ]; then
        log "INFO" "Aplicando migrações para a versão 101..."

        find $agent_conf_dir/ -type f -iname '*.conf' | while read config; do
            grep -E "^agent_name=[\"']?wildfly_8[\"']?$" $config > /dev/null || continue
            touch $config
            cp $config $config.bak
            sed -i -r '/^log_limit=/d' $config
            reset_config.sh "$config" "$src_dir/agents/template/wildfly_8.template"
            chown $apache_user:$apache_group $config
            log "INFO" "Arquivo $config atualizado com sucesso."
        done

        echo "101" > $version_file

######################### 3.8.2

    elif [ "$version_sequential" -lt "110" ]; then
        log "INFO" "Aplicando migrações para a versão 110..."

        find $agent_conf_dir/ -type f -iname '*.conf' | while read config; do
            grep -E "^agent_name=[\"']?wildfly_8_standalone[\"']?$" $config > /dev/null || continue
            touch $config
            cp $config $config.bak
            sed -i -r "s/^agent_name=.*$/agent_name='jboss_7_8_standalone'/" $config
            sed -i -r "s/^wildfly_servers_dir=/jboss_servers_dir=/" $config
            echo "jboss_uid='wildfly'" >> $config
            echo "jboss_gid='wildfly'" >> $config
            reset_config.sh "$config" "$src_dir/agents/template/jboss_7_8_standalone.template"
            chown $apache_user:$apache_group $config
            log "INFO" "Arquivo $config atualizado com sucesso."
        done

        echo "110" > $version_file

######################### 4.0-alfa1

    elif [ "$version_sequential" -lt "112" ]; then
        log "INFO" "Aplicando migrações para a versão 112..."

        find $app_conf_dir/ -type f -iname '*.conf' | while read config; do
            touch $config
            sed -i.bak -r 's/^(auto|branch|revisao|hosts|share|modo)_([^=]+)=/\1\[\2\]=/' $config
            reset_config.sh "$config" "$install_dir/template/app.template"
            chown $apache_user:$apache_group $config
            log "INFO" "Arquivo $config atualizado com sucesso."
        done

        echo "112" > $version_file        

######################## LATEST

    elif [ "$version_sequential" -le "$version_latest" ]; then
        echo "$version_latest" > $version_file
        echo "$release_latest" > $release_file
        outdated=false
    fi

done

log "INFO" "Migrações realizadas com sucesso."
