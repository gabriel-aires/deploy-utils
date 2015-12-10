#!/bin/bash
#
# Script para automatização dos deploys e disponibilização de logs do ambiente JBOSS / Linux.
#
agent_name=$1

source $(dirname $(dirname $(dirname $(readlink -f $0))))/common/sh/include.sh || exit 1

###### FUNÇÕES ######

function log () {

	##### LOG DE DEPLOY DETALHADO ####

	echo -e "$(date +"%F %Hh%Mm%Ss") : $HOSTNAME : $1 : $2"

}

function end () {

	if [ -d "$tmp_dir" ]; then
		rm -Rf ${tmp_dir}/*
	fi

	if [ "$edit_log" == "1" ]; then
		rm -f ${remote_lock_dir}/$history_lock_file
	fi

	exit "$1"
}

function set_dir () {

	# Encontra os diretórios de origem/destino com base na hierarquia definida em global.conf. IMPORTANTE: TODOS os parâmetros de configuração devem ser validados previamente.

	local raiz="$1"
	local dir_acima="$raiz"
	local set_var="$2"

	unset "$2"

	local fim=0
	local n=1
	local var_n="DIR_$n"

	if [ "$(eval "echo \$$var_n")" == '' ];then
		fim=1
	else
 		local dir_n="$(eval "echo \$$var_n")"
		dir_n="$(eval "echo \$$dir_n")"
		local nivel=1
	fi

	while [ "$fim" -eq '0' ]; do

		dir_acima=$dir_acima/$dir_n

		((n++))
		var_n="DIR_$n"

		if [ "$(eval "echo \$$var_n")" == '' ];then
			fim=1
		else
			dir_n="$(eval "echo \$$var_n")"
			dir_n="$(eval "echo \$$dir_n")"
			((nivel++))
		fi

	done

	if [ "$nivel" == "$qtd_dir" ]; then
		set_var="$set_var=$(find "$raiz" -iwholename "$dir_acima" 2> /dev/null)"
		eval $set_var
	else
		log "ERRO" "Parâmetros incorretos no arquivo '$local_conf'."
		continue
	fi

}

chk_dir () {

	local raiz="$1"

        log "INFO" "Verificando a consistência da estrutura de diretórios em $raiz.."

    	# eliminar da estrutura de diretórios subjacente os arquivos e subpastas cujos nomes contenham espaços.
    	find $raiz/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rfv

    	# garantir integridade da estrutura de diretórios, eliminando subpastas inseridas incorretamente.
    	find $raiz/* -type d | grep -Ei "^$raiz/[^/]+/[^/]+" | grep -Eixv "^$raiz/[^/]+/deploy$|^$raiz/[^/]+/log$" | xargs -r -d "\n" rm -Rfv

    	# eliminar arquivos em local incorreto ou com extensão diferente de .war / .ear / .log
    	find "$raiz" -type f | grep -Eixv "^$raiz/[^/]+/deploy/[^/]+\.[ew]ar$|^$raiz/[^/]+/log/[^/]+\.log$|^$raiz/[^/]+/log/[^/]+\.zip$" | xargs -r -d "\n" rm -fv

}

###### INICIALIZAÇÃO ######

trap "end 1; exit" SIGQUIT SIGINT SIGHUP SIGTERM

find_install_dir

arq_props_global="${install_dir}/conf/global.conf"
dir_props_local="${install_dir}/conf/$agent_name"
arq_props_local=$(find "$dir_props_local" -type f -iname "*.conf" -print)
arq_props_local=$(echo "$arq_props_local" | sed -r "s%(.)$%\1|%g")

# Verifica se o arquivo global.conf atende ao template correspondente e carrega configurações.

test -f "$arq_props_global" || exit 1
dos2unix "$arq_props_global" > /dev/null 2>&1
chk_template "$arq_props_global"
source "$arq_props_global" || exit 1

# Se houver mais de um PID referente ao script, a tarefa já está em andamento.

if [ "$(pgrep -f $0)" != "$$" ]; then
    echo "Tarefa em andamento... Aguarde."
    exit 0
fi

# cria diretório temporário.

if [ ! -z "$tmp_dir" ]; then
	mkdir -p $tmp_dir
else
	exit 0
fi

# cria pasta de logs / expurga logs de deploy do mês anterior.

if [ ! -z "$log_dir" ]; then
	mkdir -p $log_dir
	touch $log
	echo "" >> $log
	find $log_dir -type f | grep -v $(date "+%Y-%m") | xargs rm -f
else
	exit 0
fi

if [ ! -d "$remote_pkg_dir_tree" ] || [ ! -d "$remote_log_dir_tree" ]; then
	log "ERRO" "Parâmetros incorretos no arquivo '${arq_props_global}'."
	end "1"
fi

# Executa deploys e copia logs das instâncias jboss

if [ $(echo "$arq_props_local" | wc -w) -ne 0 ]; then

	echo $arq_props_local | while read -d '|' local_conf; do

		# Valida o arquivo de configurações $local_conf

		cat $arq_props_global | grep -E "DIR_.+='.+'" | sed 's/"//g' | sed "s/'//g" | sed -r "s|^[^ ]+=([^ ]+)$|\^\1=|" > $tmp_dir/parametros_obrigatorios

		dos2unix "$local_conf" &> /dev/null

		## if [ $(cat $local_conf | sed 's|"||g' | grep -Ev "^#|^$" | grep -Ex "^caminho_instancias_jboss='?/.+/server'?$" | wc -l) -ne "1" ] \
		if [ $(cat $local_conf | sed 's|"||g' | grep -Ev "^#|^$" | grep -Evx "^[a-zA-Z0-9_]+='?[a-zA-Z0-9_/\-]+'?$" | wc -l) -ne "0" ] \		#apenas definição de variáveis
			|| [ $(cat $local_conf | sed -r 's|=.*$||' | grep -Ex --file=$tmp_dir/parametros_obrigatorios | wc -l) -ne "$(cat $tmp_dir/parametros_obrigatorios | wc -l)" ];		#verifica parâmetros obrigatórios.
		then
			log "ERRO" "Parâmetros incorretos no arquivo '$local_conf'."
			continue
		else
			source "$local_conf" || continue
			rm -f "$tmp_dir/*"
		fi

		# verificar se o caminho para obtenção dos pacotes / gravação de logs está disponível.

		set_dir "$remote_pkg_dir_tree" 'origem'
		set_dir "$remote_log_dir_tree" 'destino'

		if [ $( echo "$origem" | wc -w ) -ne 1 ] || [ ! -d "$origem" ] || [ $( echo "$destino" | wc -w ) -ne 1 ] || [ ! -d "$destino" ]; then
			log "ERRO" "O caminho para o diretório de pacotes / logs não foi encontrado ou possui espaços."
			continue
		fi

		######## DEPLOY #########

		if [ $(ls "${origem}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then

			chk_dir ${origem}


	    	# Verificar se há arquivos para deploy.

	    	log "INFO" "Procurando novos pacotes..."

	    	find "$origem" -type f -regextype posix-extended -iregex "^.*.war$|^.*.ear$" > $tmp_dir/arq.list

    		if [ $(cat $tmp_dir/arq.list | wc -l) -lt 1 ]; then
	    		log "INFO" "Não foram encontrados novos pacotes para deploy."
	    	else
	    		# Caso haja arquivos, verificar se o nome do pacote corresponde ao diretório da aplicação.

	    		rm -f "$tmp_dir/remove_incorretos.list"
				touch "$tmp_dir/remove_incorretos.list"

	    		while read l; do

	    			war=$( echo $l | sed -r "s|^${origem}/[^/]+/deploy/([^/]+)\.[ew]ar$|\1|i" )
	    			app=$( echo $l | sed -r "s|^${origem}/([^/]+)/deploy/[^/]+\.[ew]ar$|\1|i" )

	    			if [ $(echo $war | grep -Ei "^$app" | wc -l) -ne 1 ]; then
	    				echo $l >> "$tmp_dir/remove_incorretos.list"
	    			fi

	    		done < "$tmp_dir/arq.list"

	    		if [ $(cat $tmp_dir/remove_incorretos.list | wc -l) -gt 0 ]; then
	    			log "WARN" "Removendo pacotes em diretórios incorretos..."
	    			cat "$tmp_dir/remove_incorretos.list" | xargs -r -d "\n" rm -fv
	    		fi

	    		# Caso haja pacotes, deve haver no máximo um pacote por diretório

	    		find "$origem" -type f -regextype posix-extended -iregex "^.*.war$|^.*.ear$" > $tmp_dir/arq.list

				rm -f "$tmp_dir/remove_versoes.list"
				touch "$tmp_dir/remove_versoes.list"

	    		while read l; do

    				war=$( echo $l | sed -r "s|^${origem}/[^/]+/deploy/([^/]+)\.[ew]ar$|\1|i" )
	    			dir=$( echo $l | sed -r "s|^(${origem}/[^/]+/deploy)/[^/]+\.[ew]ar$|\1|i" )

	    			if [ $( find $dir -type f | wc -l ) -ne 1 ]; then
	    				echo $l >> $tmp_dir/remove_versoes.list
	    			fi

	    		done < "$tmp_dir/arq.list"

	    		if [ $(cat $tmp_dir/remove_versoes.list | wc -l) -gt 0 ]; then
	    			log "WARN" "Removendo pacotes com mais de uma versão..."
	    			cat $tmp_dir/remove_versoes.list | xargs -r -d "\n" rm -fv
	    		fi

    			find "$origem" -type f -regextype posix-extended -iregex "^.*.war$|^.*.ear$" > $tmp_dir/war.list

	    		if [ $(cat $tmp_dir/war.list | wc -l) -lt 1 ]; then
    				log "INFO" "Não há novos pacotes para deploy."
	    		else
	    			log "INFO" "Verificação do diretório ${remote_pkg_dir_tree} concluída. Iniciando processo de deploy dos pacotes abaixo."
	    			cat $tmp_dir/war.list

	    			while read pacote; do

		    			war=$(basename $pacote)
						ext=$(echo $war | sed -r "s|^.*\.([^\.]+)$|\1|")
		    			app=$(echo $pacote | sed -r "s|^${origem}/([^/]+)/deploy/[^/]+\.[ew]ar$|\1|i" )
		    			rev=$(unzip -p -a $pacote META-INF/MANIFEST.MF | grep -i implementation-version | sed -r "s|^.+ (([[:graph:]])+).*$|\1|")
						host=$(echo $HOSTNAME | cut -f1 -d '.')

						if [ -z "$rev" ]; then
							rev="N/A"
						fi

						remote_app_history_dir=${remote_app_history_dir_tree}/$(echo ${app} | tr '[:upper:]' '[:lower:]')
	    				data_deploy=$(date +%F_%Hh%Mm%Ss)
						id_deploy=$(echo ${data_deploy}_${rev}_${ambiente} | sed -r "s|/|_|g" | tr '[:upper:]' '[:lower:]')
						deploy_log_dir=${remote_app_history_dir}/${id_deploy}

						mkdir -p $log_APP $deploy_log_dir

						#expurgo de logs
						find "${remote_app_history_dir}/" -maxdepth 1 -type d | grep -vx "${remote_app_history_dir}/" | sort > $tmp_dir/logs_total
						tail $tmp_dir/logs_total --lines=${history_html_size} > $tmp_dir/logs_ultimos
						grep -vxF --file=$tmp_dir/logs_ultimos $tmp_dir/logs_total > $tmp_dir/logs_expurgo
						cat $tmp_dir/logs_expurgo | xargs --no-run-if-empty rm -Rf

						qtd_log_inicio=$(cat $log | wc -l)

						source $agent_name.sh >> $log 2>&1

						qtd_log_fim=$(cat $log | wc -l)
						qtd_info_deploy=$(( $qtd_log_fim - $qtd_log_inicio ))

						tail -n ${qtd_info_deploy} $log > $deploy_log_dir/deploy_${host}.log

					done < "$tmp_dir/war.list"

    			fi

    		fi

		else
    		log "ERRO" "Não foram encontrados os diretórios das aplicações em $origem"
		fi

		#### logs

		if [ $(ls "${destino}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then

			if [ "$origem" != "$destino" ]; then
				chk_dir "$destino"
			fi

		        find $destino/* -type d -iname 'log' | sed -r "s|^${destino}/([^/]+)/log|\1|ig" > "$tmp_dir/app_destino.list"

	    		while read app; do

					destino_log=$(find "$destino/$app/" -type d -iname 'log' 2> /dev/null)
					if [ $(echo ${destino_log} | wc -l) -eq 1 ]; then
							source $agent_name.sh >> $log 2>&1
					else
						log "ERRO" "O diretório para cópia de logs da aplicação $app não foi encontrado".
					fi

				done < "$tmp_dir/app_destino.list"

		else
	        log "ERRO" "Não foram encontrados os diretórios das aplicações em $destino"
		fi

	done

else
	exit 1
fi

end "0"
