#!/bin/bash

if [ "$(id -u)" -ne "0" ]; then
    echo "Requer usuário root."
    exit 1
fi

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1
source $install_dir/sh/include.sh || exit 1
trap "echo 'Script finalizado com erro'; exit 1; exit 1" SIGQUIT SIGTERM SIGHUP ERR
outdated=true

while $outdated; do

    version_sequential=$(cat $src_dir/conf/version.txt 2> /dev/null || echo 0)

######################### 3.4

    if [ "$version_sequential" -lt "95" ]; then
        echo "Aplicando migrações para a versão 95..."

        find $app_conf_dir/ -type f -iname '*.conf' | while read config; do
            touch $config
            cp $config $config.bak
            sed -rn 's/^share=/share_desenvolvimento=/p' $config >> $config
            sed -rn 's/^share=/share_homologacao=/p' $config >> $config
            sed -rn 's/^share=/share_producao=/p' $config >> $config
            sed -rn 's/^share=/share_sustentacao=/p' $config >> $config
            sed -rn 's/^share=/share_teste=/p' $config >> $config
            sed -i -r '/^share=/d' $config
        done

        echo "95" > $src_dir/conf/version.txt

######################## LATEST

    elif [ "$version_sequential" -le "$version_latest" ]; then
        echo "$version_latest" > $src_dir/conf/version.txt
        echo "$release_latest" > $src_dir/conf/release.txt
        outdated=false
    fi

done

echo "Migrações realizadas com sucesso."
