#!/bin/bash

pid=$$

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
	echo "Requer usuário root."
	exit 1
fi

#### Inicialização #####

deploy_dir="/opt/autodeploy-paginas"									#diretório de instalação.
source $deploy_dir/conf/global.conf || exit 1								#carrega o arquivo de constantes.

temp_dir="$temp/$pid"

if [ -z "$regex_temp_dir" ] \
	|| [ -z "$regex_lock_dir" ] \
	|| [ -z $(echo $temp_dir | grep -E "$regex_temp_dir") ] \
	|| [ -z $(echo $lock_dir | grep -E "$regex_lock_dir") ] \
	|| [ ! -d "$temp" ] \
	|| [ ! -d "$lock_dir" ] \
	|| [ ! -d "$parametros_app" ] \
	|| [ -z "$ambientes" ];
then
	echo 'Favor preencher corretamente o arquivo global.conf e tentar novamente.'
	exit 1
fi

#### Cria lockfile e diretório temporário #########

if [ -f $lock_dir/autodeploy ]; then
	echo -e "O script de deploy automático já está em execução." && exit 0
else
	touch $lock_dir/autodeploy
	mkdir -p $temp_dir
fi

#### Renovação do ticket kerberos ########

kinit -R || exit 1

#### Deploy em todos os ambientes ########

echo "$ambientes" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g' | sed -r 's/ /\n/g'> $temp_dir/lista_ambientes

while read ambiente; do
	grep -REl "^auto_$ambiente='1'$" $parametros_app > $temp_dir/lista_aplicacoes
	sed -i -r "s|^$parametros_app/(.+)\.conf$|\1|g" $temp_dir/lista_aplicacoes

	if [ ! -z "$(cat $temp_dir/lista_aplicacoes)" ];then
        	while read aplicacao; do
			/bin/bash $deploy_dir/sh/deploy_paginas.sh -f $aplicacao auto $ambiente
			wait
			echo -e "\n------------------------------------------------------\n"
		done < "$temp_dir/lista_aplicacoes"
	else
		echo "O deploy automático não foi habilitado no ambiente '$ambiente'"
		echo -e "\n------------------------------------------------------\n"
	fi
done < "$temp_dir/lista_ambientes"

##### Remove lockfile e diretório temporário #####

rm -f $temp_dir/*
rmdir $temp_dir
rm -f "$lock_dir/autodeploy"
exit 0
