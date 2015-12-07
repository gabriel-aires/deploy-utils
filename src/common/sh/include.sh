#!/bin/bash

# As funções abaixo devem ser carregadas antes da execução de qualquer script.

alias find_install_dir="install_dir=$(dirname $(dirname $(readlink -f $0)))"

function write_history () {

	##### LOG DE DEPLOYS GLOBAL #####

	local horario_log=$(echo "$(date +%F_%Hh%Mm%Ss)" | sed -r "s|^(....)-(..)-(..)_(.........)$|\3/\2/\1;\4|")
	local app_log="$(echo "$app" | tr '[:upper:]' '[:lower:]')"
    local rev_log="$(echo "$rev" | tr '[:upper:]' '[:lower:]')"
	local ambiente_log="$(echo "$ambiente" | tr '[:upper:]' '[:lower:]')"
	local host_log="$(echo "$host" | cut -f1 -d '.' | tr '[:upper:]' '[:lower:]')"
    local obs_log="$1"
	local mensagem_log="$horario_log;$app_log;$rev_log;$ambiente_log;$host_log;$obs_log;"

	##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

    local lock_path
    local history_path
    local app_history_path

    case $execution_mode in
        "agent")
            lock_path=$remote_lock_dir
            history_path=$remote_history_dir
            app_history_path=$remote_app_history_dir
            ;;
        "server")
            lock_path=$lock_dir
            history_path=$history_dir
            app_history_path=$app_history_dir
            ;;

    while [ -f "${lock_path}/$history_lock_file" ]; do						#nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
    	sleep 1
    done

	edit_log=1
	touch "${lock_path}/$history_lock_file"

	touch ${history_path}/$history_csv_file
	touch ${app_history_path}/$history_csv_file

	tail --lines=$global_history_size ${history_path}/$history_csv_file > $tmp_dir/deploy_log_new
	tail --lines=$app_history_size ${app_history_path}/$history_csv_file > $tmp_dir/app_log_new

	echo -e "$mensagem_log" >> $tmp_dir/deploy_log_new
	echo -e "$mensagem_log" >> $tmp_dir/app_log_new

	cp -f $tmp_dir/deploy_log_new ${history_path}/$history_csv_file
	cp -f $tmp_dir/app_log_new ${app_history_path}/$history_csv_file

	rm -f ${lock_path}/$history_lock_file    							#remove a trava sobre o arquivo de log tão logo seja possível.
	edit_log=0

}
