#!/bin/bash

pid=$$
edit_log=false

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
	echo "Requer usuário root."
	exit 1
fi

#### Funções ####

function install_dir () {										##### Determina o diretório de instalação do script ####

	if [ -L $0 ]; then
		caminho_script=$(dirname $(readlink $0))
	else
		caminho_script=$(dirname $BASH_SOURCE)
	fi
	
	if [ -z $(echo $caminho_script | grep -Ex "^/.*$") ]; then 					#caminho é relativo
		
		if [ "$caminho_script" == "." ]; then
			caminho_script="$(pwd)"
		else
			caminho_script="$(pwd)/$caminho_script"
	
			while [ $(echo "$caminho_script" | grep -E "/\./" | wc -l) -ne 0 ]; do   	#substitui /./ por /
				caminho_script=$(echo "$caminho_script" | sed -r "s|/\./|/|")
			done
	
			while [ $(echo "$caminho_script" | grep -E "/\.\./" | wc -l) -ne 0 ]; do   	#corrige a string caso o script tenha sido chamado a partir de um subdiretório
				caminho_script=$(echo "$caminho_script" | sed -r "s|[^/]+/\.\./||")
			done
		fi
	fi
	
	diretorio_instalacao=$(dirname $caminho_script)

}

function horario () {

	echo $(date "+%F %T"):

}

function deploy_auto () {

	#### Deploy em todos os ambientes ########
	
	echo "$ambientes" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g' | sed -r 's/ /\n/g'> $temp_dir/lista_ambientes
	
	while read ambiente; do
		grep -REl "^auto_$ambiente='1'$" $conf_app_dir > $temp_dir/lista_aplicacoes
		sed -i -r "s|^$conf_app_dir/(.+)\.conf$|\1|g" $temp_dir/lista_aplicacoes
	
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

}

function html () {

	arquivo_entrada=$1
	arquivo_saida=$2

	cd $(dirname $arquivo_entrada)

	tail --lines=$qtd_log_html $arquivo_entrada > $temp_dir/html_tr

	sed -i -r 's|^(.)|\-\1|' $temp_dir/html_tr
	sed -i -r "s|^\-(([^;]+;){6}$mensagem_sucesso.*)$|\+\1|" $temp_dir/html_tr
	sed -i -r 's|;$|</td></tr>|' $temp_dir/html_tr
	sed -i -r 's|;|</td><td>|g' $temp_dir/html_tr
	sed -i -r 's|^\-|\t\t\t<tr style="@@html_tr_style_warning@@"><td>|' $temp_dir/html_tr
	sed -i -r 's|^\+|\t\t\t<tr style="@@html_tr_style_default@@"><td>|' $temp_dir/html_tr
	
	cat $html_dir/begin.html > $temp_dir/html
	cat $temp_dir/html_tr >> $temp_dir/html
	cat $html_dir/end.html >> $temp_dir/html

	sed -i -r "s|@@html_title@@|$html_title|" $temp_dir/html
	sed -i -r "s|@@html_header@@|$html_header|" $temp_dir/html
	sed -i -r "s|@@html_table_style@@|$html_table_style|" $temp_dir/html
	sed -i -r "s|@@html_th_style@@|$html_th_style|" $temp_dir/html
	sed -i -r "s|@@html_tr_style_default@@|$html_tr_style_default|" $temp_dir/html
	sed -i -r "s|@@html_tr_style_warning@@|$html_tr_style_warning|" $temp_dir/html

	cp -f $temp_dir/html $arquivo_saida

	cd -
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

	if $edit_log; then
		rm -f "$lock_dir/$deploy_log_edit"
	fi

	unix2dos $log_dir/$cron_log > /dev/null 2>&1

	exit $erro

}

#### Inicialização #####

install_dir

if [ -d "$diretorio_instalacao" ] && [ -f "$diretorio_instalacao/conf/global.conf" ]; then
	deploy_dir="$diretorio_instalacao"
elif [ -f '/opt/autodeploy-paginas/conf/global.conf' ]; then
	deploy_dir='/opt/autodeploy-paginas'						#local de instalação padrão
else
	echo 'Arquivo global.conf não encontrado.'
	exit 1
fi

if [ "$(grep -v --file=$deploy_dir/template/global.template $deploy_dir/conf/global.conf | grep -v '^$' | wc -l)" -ne "0" ]; then
	echo 'O arquivo global.conf não atende ao template correspondente.'
	exit 1
fi

source "$deploy_dir/conf/global.conf" || exit 1						#carrega o arquivo de constantes.

if [ -f "$deploy_dir/conf/user.conf" ] && [ -f "$deploy_dir/template/user.template" ]; then
	if [ "$(grep -v --file=$deploy_dir/template/user.template $deploy_dir/conf/user.conf | grep -v '^$' | wc -l)" -ne "0" ]; then
		echo 'O arquivo user.conf não atende ao template correspondente.'
		exit 1
	else
		source "$deploy_dir/conf/user.conf" || exit 1
	fi
fi

temp_dir="$temp/$pid"

if [ -z "$regex_temp_dir" ] \
	|| [ -z "$regex_lock_dir" ] \
	|| [ -z "$regex_log_dir" ] \
	|| [ -z "$regex_qtd" ] \
	|| [ -z $(echo $temp_dir | grep -E "$regex_temp_dir") ] \
	|| [ -z $(echo $lock_dir | grep -E "$regex_lock_dir") ] \
	|| [ -z $(echo $html_dir | grep -E "$regex_html_dir") ] \ 
	|| [ -z $(echo $qtd_log_cron | grep -E "$regex_qtd") ] \
	|| [ -z $(echo $qtd_log_html | grep -E "$regex_qtd") ] \
	|| [ -z "$ambientes" ] \
	|| [ ! -d "$html_dir" ];
then
	echo 'Favor preencher corretamente o arquivo global.conf e tentar novamente.'
	exit 1
fi

mkdir -p $temp $lock_dir $log_dir $log_app_dir $conf_app_dir

#### Cria lockfile e diretório temporário #########

if [ -f $lock_dir/autodeploy ]; then
	echo -e "O script de deploy automático já está em execução." && exit 0
else
	touch $lock_dir/autodeploy
	mkdir -p $temp_dir
fi

trap "end 1" SIGQUIT SIGTERM SIGINT SIGHUP

#### Expurgo de logs #####

touch $log_dir/$cron_log

tail --lines=$qtd_log_cron $log_dir/$cron_log > $temp_dir/cron_log_novo
cp -f $temp_dir/cron_log_novo $log_dir/$cron_log
	
### Execução da rotina de deploy ###

deploy_auto >> $log_dir/$cron_log 2>&1

### Geração de logs em formato html ###

while [ -f "$lock_dir/$deploy_log_lock" ]; do
	sleep 1
done

edit_log=true
touch $lock_dir/$deploy_log_lock

find "$log_dir/" -type f -name "$deploy_log_csv" > $temp_dir/logs_csv

while read log_csv; do
	html log_csv $deploy_log_html || end 1
done < $temp_dir/logs_csv

rm -f $lock_dir/$deploy_log_lock
edit_log=false

end 0
