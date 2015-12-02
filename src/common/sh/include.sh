#!/bin/bash

# As funções abaixo devem ser carregadas antes da execução de qualquer script.

function install_dir () {										##### Determina o diretório de instalação do script ####

    local caminho_script

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

function write_history () {

	##### LOG DE DEPLOYS GLOBAL #####

    local app_log=$1
    local rev_log=$2
    local ambiente_log=$3
    local host_log=$4
    local obs_log=$5
    local mensagem_log

	horario_log=$(echo "$(date +%F_%Hh%Mm%Ss)" | sed -r "s|^(....)-(..)-(..)_(.........)$|\3/\2/\1;\4|")
	app_log="$(echo "$app_log" | tr '[:upper:]' '[:lower:]')"
	ambiente_log="$(echo "$ambiente_log" | tr '[:upper:]' '[:lower:]')"
	host_log="$(echo "$host_log" | cut -f1 -d '.' | tr '[:upper:]' '[:lower:]')"

	mensagem_log="$horario_log;$app_log;$rev_log;$ambiente_log;$host_log;$obs_log;"

	##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

	while [ -f "${caminho_lock_remoto}/$arq_lock_historico" ]; do						#nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
		sleep 1
	done

	edit_log=1
	touch "${caminho_lock_remoto}/$arq_lock_historico"

	touch ${caminho_historico_remoto}/$arq_historico
	touch ${log_app}/$arq_historico

	tail --lines=$qtd_log_deploy ${caminho_historico_remoto}/$arq_historico > $tmp_dir/deploy_log_novo
	tail --lines=$qtd_log_app ${log_app}/$arq_historico > $tmp_dir/app_log_novo

	echo -e "$mensagem_log" >> $tmp_dir/deploy_log_novo
	echo -e "$mensagem_log" >> $tmp_dir/app_log_novo

	cp -f $tmp_dir/deploy_log_novo ${caminho_historico_remoto}/$arq_historico
	cp -f $tmp_dir/app_log_novo ${log_app}/$arq_historico

	rm -f ${caminho_lock_remoto}/$arq_lock_historico 							#remove a trava sobre o arquivo de log tão logo seja possível.
	edit_log=0
}
