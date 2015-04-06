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
	|| [ -z "$regex_historico_dir" ] \
	|| [ -z "$regex_qtd" ] \
	|| [ -z $(echo $temp_dir | grep -E "$regex_temp_dir") ] \
	|| [ -z $(echo $lock_dir | grep -E "$regex_lock_dir") ] \
	|| [ -z $(echo $cron_log | grep -E "$regex_historico_dir") ] \
	|| [ -z $(echo $qtd_log_cron | grep -E "$regex_qtd") ] \
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

#### Funções ####

function horario {

	echo $(date "+%F %T"):

}

function end {


	##### Remove lockfile e diretório temporário ao fim da execução #####

	erro=$1
	wait

	if [ "$erro" == "0" ]; then
		echo -e "$(horario) Rotina concluída com sucesso.\n"
	else
		echo -e "$(horario) Rotina concluída com erro.\n"
	fi

	if [ -d $temp_dir ]; then
		rm -f $temp_dir/*
		rmdir $temp_dir
	fi

	if [ -f $lock_dir/autodeploy ]; then
		rm -f "$lock_dir/autodeploy" 
	fi

	exit $erro

}

function deploy_auto {

	#### Renovação do ticket kerberos ########
	
	kinit -R || end 1
	
	#### Deploy em todos os ambientes ########
	
	echo "$ambientes" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g' | sed -r 's/ /\n/g'> $temp_dir/lista_ambientes
	
	while read ambiente; do
		grep -REl "^auto_$ambiente='1'$" $parametros_app > $temp_dir/lista_aplicacoes
		sed -i -r "s|^$parametros_app/(.+)\.conf$|\1|g" $temp_dir/lista_aplicacoes
	
		if [ ! -z "$(cat $temp_dir/lista_aplicacoes)" ];then
	        	while read aplicacao; do
				horario
				echo ""
				/bin/bash $deploy_dir/sh/deploy_paginas.sh -f $aplicacao auto $ambiente
				wait
				echo ""
			done < "$temp_dir/lista_aplicacoes"
		else
			echo "$(horario) O deploy automático não foi habilitado no ambiente '$ambiente'"
			echo ""
		fi
	done < "$temp_dir/lista_ambientes"

	end 0

}

trap "end 1" SIGQUIT SIGTERM SIGINT SIGHUP

#### Expurgo de logs #####

touch $cron_log

tail --lines=$qtd_log_cron $cron_log > $temp_dir/cron_log_novo
cp -f $temp_dir/cron_log_novo $cron_log
	
### Execução da rotina ###

deploy_auto >> $cron_log 2>&1

