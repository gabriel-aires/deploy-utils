#!/bin/bash

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
	echo "Requer usuário root."
	exit 1
fi

#### Inicialização #####

deploy_dir="/opt/autodeploy-paginas"									#diretório de instalação.
source $deploy_dir/conf/global.conf || exit	1							#carrega o arquivo de constantes.

#### Cria lockfile #########

if [ -d $lock_dir ]; then
	if [ -f $lock_dir/autodeploy ]; then
		echo -e "O script de deploy automático já está em execução." && exit 0
	else
		touch $lock_dir/autodeploy 
	fi
else
	echo "A variável lock_dir deve ser preenchida no arquivo global.conf" && exit 1
fi

#### Renovação do ticket kerberos ########

kinit -R || exit 1

#### Deploy em todos os ambientes ########

if [ ! -z "$ambientes" ]; then
    lista_ambientes=$(echo "$ambientes" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g')
else
    echo "A variável ambientes deve ser preenchida no arquivo global.conf" && exit 1
fi

if [ -d "$parametros_app"; then
    while read -d ' ' ambiente; do
        lista_aplicacoes=$(grep -REl "^auto_desenvolvimento='1'$" $parametros_app | sed -r "s|$parametros_app/(.+)\.conf|\1|g")
        if [ ! -z "$lista_aplicacoes" ];then
            while read -d ' ' aplicacao; do
                $deploy_dir/deploy_paginas.sh -f $aplicacao auto $ambiente
                wait
            done < $lista_aplicacoes
        else
            echo "O deploy automático não foi habilitado no ambiente '$ambiente'"
        fi
    done < $lista_ambientes
else
    echo "Não foi encontrado o diretório que contém os parâmetros de deploy das aplicações." && exit 1
fi

##### Remove lockfile #####

rm -f $lock_dir/autodeploy

exit 0