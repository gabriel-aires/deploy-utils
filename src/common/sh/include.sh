#!/bin/bash

# As funções abaixo devem ser carregadas antes da execução de qualquer script.

alias find_install_dir="install_dir=$(dirname $(dirname $(readlink -f $0)))"

function paint () {

	if $interactive; then
		local color

		case $2 in
			black)		color=0;;
			red)		color=1;;
			green)		color=2;;
			yellow)		color=3;;
			blue)		color=4;;
			magenta)	color=5;;
			cyan)		color=6;;
			white)		color=7;;
		esac

		case $1 in
			fg)			tput setaf $color;;
			bg)			tput setab $color;;
			default)	tput sgr0;;
		esac
	fi

	return 0

}

function chk_template () {

	if [ -f "$1" ] && [ "$#" -le 3 ]; then

		local arquivo="$1"
		local nome_template="$2"		# parâmetro opcional, especifica um template para validação do arquivo.
		local flag="$3"					# indica se o script deve ser encerrado ou não ao encontrar inconsistências. Para prosseguir, deve ser passado o valor "continue"

		if [ -z "$nome_template" ]; then
			nome_template=$(find $install_dir/template/ -maxdepth 1 -type f -name "$(basename $arquivo | cut -f1 -d '.').template" )
		fi

		if [ -z $nome_template ]; then
			echo -e "\nErro. Não foi indentificado um template para validação do arquivo $arquivo."
			end 1 2> /dev/null || exit 1

		elif [ ! -f "$install_dir/template/$nome_template.template" ]; then
			echo -e "\nErro. O template espeficicado não foi encontrado."
			end 1 2> /dev/null || exit 1

		elif [ "$(grep -v --file=$install_dir/template/$nome_template.template $arquivo | wc -l)" -ne "0" ]; then
			echo -e "\nErro. Há parâmetros incorretos no arquivo $arquivo:"
			grep -v --file="$install_dir/template/$nome_template.template" "$arquivo"

			if [ "$flag" == "continue" ]; then
				return 1
			else
				end 1 2> /dev/null || exit 1
			fi
		fi

	else
		end 1 2> /dev/null || exit 1
	fi

	return 0

}

function valid () {	#argumentos: nome_variável (nome_regra) (nome_regra_inversa) mensagem_erro.

	if [ ! -z "$1" ] && [ ! -z "${!#}" ]; then

		local nome_var="$1"			# obrigatório
		local nome_regra			# opcional, se informado, é o segundo argumento.
		local nome_regra_inversa	# opcional, se informado, é o terceiro argumento.
		local msg="${!#}"			# obrigatório: a mensagem de erro é o último argumento

		local valor
		local regra
		local regra_inversa

		if [ "$#" -gt "2" ] && [ ! -z "$2" ]; then
			nome_regra="$2"

			if [ $(echo "$nome_regra" | grep -Ex "^regex_[a-z_]+$" | wc -l) -ne 1 ]; then
				echo "Erro. O argumento especificado não é uma regra de validação."
				end 1 2> /dev/null || exit 1
			fi

			if [ "$#" -gt "3" ] && [ ! -z "$3" ]; then
				nome_regra_inversa="$3"

				if [ $(echo "${nome_regra_inversa}" | grep -Ex "^not_regex_[a-z_]+$" | wc -l) -ne 1 ]; then
					echo "Erro. O argumento especificado não é uma regra de validação inversa."
					end 1 2> /dev/null || exit 1
				fi
			fi

		else
			end 1 2> /dev/null || exit 1
		fi

		if [ -z "$nome_regra" ]; then
			regra="echo \$regex_${nome_var}"
		else
			regra="echo \$$nome_regra"
		fi

		if [ -z "${nome_regra_inversa}" ]; then
			regra_inversa="echo \$not_regex_${nome_var}"
		else
			regra_inversa="echo \$${nome_regra_inversa}"
		fi

		regra="$(eval $regra)"
		regra_inversa="$(eval ${regra_inversa})"

		valor="echo \$${nome_var}"
		valor="$(eval $valor)"

		if [ -z "$regra" ]; then
			echo "Erro. Não há uma regra para validação da variável $nome_var"
			end 1 2> /dev/null || exit 1

		elif "$interactive"; then
			edit_var=0
			while [ $(echo "$valor" | grep -Ex "$regra" | grep -Exv "${regra_inversa}" | wc -l) -eq 0 ]; do
				paint 'fg' 'yellow'
				echo -e "$msg"
				paint 'default'
				read -p "$nome_var: " -e -r $nome_var
				edit_var=1
                valor="echo \$${nome_var}"
		        valor="$(eval $valor)"
			done

		elif [ $(echo "$valor" | grep -Ex "$regra" | grep -Exv "${regra_inversa}" | wc -l) -eq 0 ]; then
			echo -e "$msg"
			end 1 2> /dev/null || exit 1

		fi

	else
		end 1 2> /dev/null || exit 1
	fi

	return 0		# o script continua somente se a variável tiver sido validada corretamente.

}

function write_history () {

	##### LOG DE DEPLOYS GLOBAL #####

	local horario_log=$(echo "$(date +%F_%Hh%Mm%Ss)" | sed -r "s|^(....)-(..)-(..)_(.........)$|\3/\2/\1;\4|")
	local app_log="$(echo "$app" | tr '[:upper:]' '[:lower:]')"
    local rev_log="$(echo "$rev" | tr '[:upper:]' '[:lower:]')"
	local ambiente_log="$(echo "$ambiente" | tr '[:upper:]' '[:lower:]')"
	local host_log="$(echo "$host" | cut -f1 -d '.' | tr '[:upper:]' '[:lower:]')"
    local obs_log="$1"
	local msg_log="$horario_log;$app_log;$rev_log;$ambiente_log;$host_log;$obs_log;"

	##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

    local lock_path
    local history_path
    local app_history_path

    case $execution_mode in
        "agent")
            lock_path=${remote_lock_dir}
            history_path=${remote_history_dir}
            app_history_path=${remote_app_history_dir}
			;;
		"server")
		    lock_path=$lock_dir
            history_path=$history_dir
            app_history_path=${app_history_dir}
		    ;;
	esac

    while [ -f "${lock_path}/$history_lock_file" ]; do						#nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
	    sleep 1
	done

	edit_log=1
	touch "${lock_path}/$history_lock_file"

	touch ${history_path}/$history_csv_file
	touch ${app_history_path}/$history_csv_file

	tail --lines=$global_history_size ${history_path}/$history_csv_file > $tmp_dir/deploy_log_new
	tail --lines=$app_history_size ${app_history_path}/$history_csv_file > $tmp_dir/app_log_new

	echo -e "$msg_log" >> $tmp_dir/deploy_log_new
	echo -e "$msg_log" >> $tmp_dir/app_log_new

	cp -f $tmp_dir/deploy_log_new ${history_path}/$history_csv_file
	cp -f $tmp_dir/app_log_new ${app_history_path}/$history_csv_file

	rm -f ${lock_path}/$history_lock_file    							#remove a trava sobre o arquivo de log tão logo seja possível.
	edit_log=0

	return 0

}
