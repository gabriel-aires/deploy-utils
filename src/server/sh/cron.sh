#!/bin/bash
source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

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

	install_dir=$(dirname $caminho_script)

}

function horario () {

	echo $(date "+%F %T"):

}

function html () {

	arquivo_entrada=$1
	arquivo_saida=$2

	cd $(dirname $arquivo_entrada)

	tail --lines=$history_html_size $arquivo_entrada > $tmp_dir/html_tr

	sed -i -r 's|^(.)|\-\1|' $tmp_dir/html_tr
	sed -i -r "s|^\-(([^;]+;){6}$mensagem_sucesso.*)$|\+\1|" $tmp_dir/html_tr
	sed -i -r 's|;$|</td></tr>|' $tmp_dir/html_tr
	sed -i -r 's|;|</td><td>|g' $tmp_dir/html_tr
	sed -i -r 's|^\-|\t\t\t<tr style="@@html_tr_style_warning@@"><td>|' $tmp_dir/html_tr
	sed -i -r 's|^\+|\t\t\t<tr style="@@html_tr_style_default@@"><td>|' $tmp_dir/html_tr

	cat $html_dir/begin.html > $tmp_dir/html
	cat $tmp_dir/html_tr >> $tmp_dir/html
	cat $html_dir/end.html >> $tmp_dir/html

	sed -i -r "s|@@html_title@@|$html_title|" $tmp_dir/html
	sed -i -r "s|@@html_header@@|$html_header|" $tmp_dir/html
	sed -i -r "s|@@html_table_style@@|$html_table_style|" $tmp_dir/html
	sed -i -r "s|@@html_th_style@@|$html_th_style|" $tmp_dir/html
	sed -i -r "s|@@html_tr_style_default@@|$html_tr_style_default|" $tmp_dir/html
	sed -i -r "s|@@html_tr_style_warning@@|$html_tr_style_warning|" $tmp_dir/html

	cp -f $tmp_dir/html $arquivo_saida

	cd - &> /dev/null
}

function deploy_auto () {

	#### Expurgo de logs #####

	touch $history_dir/$cron_log

	tail --lines=$log_cron_size $history_dir/$cron_log > $tmp_dir/cron_log_new
	cp -f $tmp_dir/cron_log_new $history_dir/$cron_log

	#### Deploy em todos os ambientes ########

	echo "$ambientes" | sed -r 's/,/ /g' | sed -r 's/;/ /g' | sed -r 's/ +/ /g' | sed -r 's/ $//g' | sed -r 's/^ //g' | sed -r 's/ /\n/g'> $tmp_dir/lista_ambientes

	while read ambiente; do
		grep -REl "^auto_$ambiente='1'$" $conf_app_dir > $tmp_dir/lista_aplicacoes
		sed -i -r "s|^$conf_app_dir/(.+)\.conf$|\1|g" $tmp_dir/lista_aplicacoes

		if [ ! -z "$(cat $tmp_dir/lista_aplicacoes)" ];then
	        	while read aplicacao; do
				horario
				echo ""
				/bin/bash $install_dir/sh/deploy_paginas.sh -f $aplicacao auto $ambiente
				wait
				echo ""
			done < "$tmp_dir/lista_aplicacoes"
		else
			echo "$(horario) O deploy automático não foi habilitado no ambiente '$ambiente'"
			echo ""
		fi
	done < "$tmp_dir/lista_ambientes"

	### Geração de logs em formato html ###

	while [ -f "$lock_dir/$history_lock_file" ]; do
		sleep 1
	done

	edit_log=true
	touch $lock_dir/$history_lock_file

	find "$history_dir/" -maxdepth 3 -type f -name "$history_csv_file" > $tmp_dir/logs_csv

	while read log_csv; do
		html $log_csv $history_html_file || end 1
	done < $tmp_dir/logs_csv

	rm -f $lock_dir/$history_lock_file
	edit_log=false

	end 0

}

function end {

	##### Remove lockfile e diretório temporário ao fim da execução #####

	trap "" SIGQUIT SIGTERM SIGINT SIGHUP

	erro=$1
	wait

	if [ "$erro" == "0" ]; then
		echo -e "$(horario) Rotina concluída com sucesso.\n"
	else
		echo -e "$(horario) Rotina concluída com erro.\n"
	fi

	if [ -d $tmp_dir ]; then
		rm -f $tmp_dir/*
		rmdir $tmp_dir
	fi

	if [ -f $lock_dir/autodeploy ]; then
		rm -f "$lock_dir/autodeploy"
	fi

	if $edit_log; then
		rm -f "$lock_dir/$deploy_log_edit"
	fi

	unix2dos $history_dir/$cron_log > /dev/null 2>&1

	exit $erro

}

#### Inicialização #####

find_install_dir

if [ ! -f "$install_dir/conf/global.conf" ]; then
	echo 'Arquivo global.conf não encontrado.'
	exit 1
fi

if [ "$(grep -v --file=$install_dir/template/global.template $install_dir/conf/global.conf | grep -v '^$' | wc -l)" -ne "0" ]; then
	echo 'O arquivo global.conf não atende ao template correspondente.'
	exit 1
fi

source "$install_dir/conf/global.conf" || exit 1						#carrega o arquivo de constantes.

if [ -f "$install_dir/conf/user.conf" ] && [ -f "$install_dir/template/user.template" ]; then
	if [ "$(grep -v --file=$install_dir/template/user.template $install_dir/conf/user.conf | grep -v '^$' | wc -l)" -ne "0" ]; then
		echo 'O arquivo user.conf não atende ao template correspondente.'
		exit 1
	else
		source "$install_dir/conf/user.conf" || exit 1
	fi
fi

tmp_dir="$work_dir/$pid"

if [ -z "$regex_tmp_dir" ] \
	|| [ -z "$regex_lock_dir" ] \
	|| [ -z "$regex_history_dir" ] \
	|| [ -z "$regex_qtd" ] \
	|| [ -z $(echo $tmp_dir | grep -E "$regex_tmp_dir") ] \
	|| [ -z $(echo $lock_dir | grep -E "$regex_lock_dir") ] \
	|| [ -z $(echo $html_dir | grep -E "$regex_html_dir") ] \
	|| [ -z $(echo $log_cron_size | grep -E "$regex_qtd") ] \
	|| [ -z $(echo $history_html_size | grep -E "$regex_qtd") ] \
	|| [ -z "$ambientes" ] \
	|| [ ! -d "$html_dir" ];
then
	echo 'Favor preencher corretamente o arquivo global.conf e tentar novamente.'
	exit 1
fi

mkdir -p $work_dir $lock_dir $history_dir $history_app_parent_dir $conf_app_dir

#### Cria lockfile e diretório temporário #########

if [ -f $lock_dir/autodeploy ]; then
	echo -e "O script de deploy automático já está em execução." && exit 0
else
	touch $lock_dir/autodeploy
	mkdir -p $tmp_dir
fi

trap "end 1" SIGQUIT SIGTERM SIGINT SIGHUP

### Execução da rotina de deploy ###

deploy_auto >> $history_dir/$cron_log 2>&1
