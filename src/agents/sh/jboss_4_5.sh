#!/bin/bash
#
# Script para automatização dos deploys e disponibilização de logs do ambiente JBOSS / Linux.
#

###### FUNÇÕES ######

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

function log () {

	##### LOG DE DEPLOY DETALHADO ####

	echo -e "$(date +"%F %Hh%Mm%Ss") : $HOSTNAME : $1 : $2"

}

function global_log () {

	##### LOG DE DEPLOYS GLOBAL #####

	obs_log="$1"

	horario_log=$(echo "$(date +%F_%Hh%Mm%Ss)" | sed -r "s|^(....)-(..)-(..)_(.........)$|\3/\2/\1;\4|")
	app_log="$(echo "$app" | tr '[:upper:]' '[:lower:]')"
	ambiente_log="$(echo "$ambiente" | tr '[:upper:]' '[:lower:]')"
	host_log="$(echo "$HOSTNAME" | sed -r "s/^([^\.]+)\..*$/\1/" | tr '[:upper:]' '[:lower:]')"

	mensagem_log="$horario_log;$app_log;$rev;$ambiente_log;$host_log;$obs_log;"

	##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

	while [ -f "${remote_lock_dir}/$history_lock_file" ]; do						#nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
		sleep 1
	done

	edit_log=1
	touch "${remote_lock_dir}/$history_lock_file"

	touch ${remote_history_dir}/$history_csv_file
	touch ${remote_history_app_dir}/$history_csv_file

	tail --lines=$history_global_size ${remote_history_dir}/$history_csv_file > $tmp_dir/deploy_log_new
	tail --lines=$history_app_size ${remote_history_app_dir}/$history_csv_file > $tmp_dir/app_log_new

	echo -e "$mensagem_log" >> $tmp_dir/deploy_log_new
	echo -e "$mensagem_log" >> $tmp_dir/app_log_new

	cp -f $tmp_dir/deploy_log_new ${remote_history_dir}/$history_csv_file
	cp -f $tmp_dir/app_log_new ${remote_history_app_dir}/$history_csv_file

	rm -f ${remote_lock_dir}/$history_lock_file 							#remove a trava sobre o arquivo de log tão logo seja possível.
	edit_log=0
}

function jboss_script_init () {

	##### LOCALIZA SCRIPT DE INICIALIZAÇÃO DA INSTÂNCIA JBOSS #####

	local caminho_jboss=$1
	local instancia=$2

	if [ -n "$caminho_jboss" ] && [ -n "$instancia" ] && [ -d  "${caminho_jboss}/server/${instancia}" ]; then

		unset SCRIPT_INIT
		find /etc/init.d/ -type f -iname '*jboss*' > "$tmp_dir/scripts_jboss.list"

		#verifica todos os scripts de jboss encontrados em /etc/init.d até localizar o correto.
		while read script_jboss && [ -z "$script_init" ]; do

			#verifica se o script corresponde à instalação correta do JBOSS e se aceita os argumentos 'start' e 'stop'
			if [ -n "$(grep -E '^([^[:graph:]])+?start[^A-Za-z0-9_\-]?' "$script_jboss" | head -1)" ] \
				&& [ -n "$(grep -E '^([^[:graph:]])+?stop[^A-Za-z0-9_\-]?' "$script_jboss" | head -1)" ] \
				&& [ -n "$(grep -F "$caminho_jboss" "$script_jboss" | head -1)" ];
			then

				#teste 1: retorna a primeira linha do tipo .../server/...

				local linha_script=$(grep -Ex "^[^#]+[\=].*[/\$].+/server/[^/]+/.*$" "$script_jboss" | head -1 )
				local teste_script=1

				#teste 2: retorna a primeira linha onde foi utilizada a variável $JBOSS_CONF

				if [ -z "$linha_script" ]; then
					linha_script=$(grep -Ex '^.*\$JBOSS_CONF.*$' "$script_jboss" | head -1 )
					teste_script=2
				fi

				if [ -n "$linha_script" ]; then

					case $teste_script in
						1) local jboss_conf=$(echo "$linha_script" | sed -r "s|^.*/server/([^/]+).*$|\1|");;
						2) local jboss_conf='$JBOSS_CONF';;
					esac

					#Se a instância estiver definida como uma variável no script, o loop a seguir tenta encontrar o seu valor em até 3 iterações.

					local var_jboss_conf=$( echo "$jboss_conf" | grep -Ex "^\\$.*$")
					local i='0'

					while [ -n "$var_jboss_conf" ] && [ "$i" -lt '3' ]; do

						#remove o caractere '$', restando somente o nome da variável
						var_jboss_conf=$(echo "$var_jboss_conf" | sed -r "s|^.||")

						#encontra a linha onde a variável foi setada e retorna a string após o caractere =, sem aspas
						jboss_conf=$(grep -Ex "^$var_jboss_conf=.*$" "$script_jboss" | head -1 | sed 's|"||g' | sed "s|'||g" | sed -r "s|^$var_jboss_conf=([[:graph:]]+).*$|\1|" )

						#verificar se houve substituição de parâmetros
						if [ $(echo "$jboss_conf" | sed 's|}|¨|' | sed 's|{|¨|' | grep -Ex "^\\$¨$var_jboss_conf[:=\-]+(\\$)?[A-Za-z0-9_]+¨.*$" | wc -l) -ne 0 ]; then
							jboss_conf=$(echo "$jboss_conf" | sed 's|^..||' | sed 's|}.*$||' | sed -r "s|$var_jboss_conf[:=\-]+||")
						fi

						#atualiza condições para entrada no loop.
						var_jboss_conf=$( echo "$jboss_conf" | grep -Ex "^\\$.*$")
						((i++))

					done

					#verifica se o script encontrado corresponde à instância desejada.
					if [ -d "${caminho_jboss}/server/${jboss_conf}" ] && [ "$jboss_conf" == "$instancia" ]; then
						script_init=$script_jboss
					fi

				fi

			fi

		done < "$tmp_dir/scripts_jboss.list"

	else
		log "ERRO" "Parâmetros incorretos ou instância JBOSS não encontrada."
	fi

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

function jboss_instances () {

	if [ ! -d "$remote_pkg_dir_tree" ] || [ ! -d "$remote_log_dir_tree" ]; then
		log "ERRO" "Parâmetros incorretos no arquivo '${arq_props_global}'."
		end "1"
	fi

	echo $arq_props_local | while read -d '|' local_conf; do

		# Valida e carrega parâmetros referentes ao ambiente JBOSS.

		cat $arq_props_global | grep -E "DIR_.+='.+'" | sed 's/"//g' | sed "s/'//g" | sed -r "s|^[^ ]+=([^ ]+)$|\^\1=|" > $tmp_dir/parametros_obrigatorios

		dos2unix "$local_conf" > /dev/null 2>&1

		if [ $(cat $local_conf | sed 's|"||g' | grep -Ev "^#|^$" | grep -Ex "^caminho_instancias_jboss='?/.+/server'?$" | wc -l) -ne "1" ] \
			|| [ $(cat $local_conf | sed 's|"||g' | grep -Ev "^caminho_instancias_jboss=|^#|^$" | grep -Evx "^[a-zA-Z0-9_]+='?[a-zA-Z0-9_]+'?$" | wc -l) -ne "0" ] \
			|| [ $(cat $local_conf | sed 's|"||g' | grep -Ev "^caminho_instancias_jboss=|^#|^$" | grep -Ev --file=$tmp_dir/parametros_obrigatorios | wc -l) -ne "0" ];
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

		if [ $(ls "${origem}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then

			chk_dir ${origem}

		    	######## DEPLOY #########

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

		    			war=$( echo $l | sed -r "s|^${origem}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy]/([^/]+)\.[EeWw][Aa][Rr]$|\1|" )
		    			app=$( echo $l | sed -r "s|^${origem}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[EeWw][Aa][Rr]$|\1|" )

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

	    				war=$( echo $l | sed -r "s|^${origem}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy]/([^/]+)\.[EeWw][Aa][Rr]$|\1|" )
		    			dir=$( echo $l | sed -r "s|^(${origem}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy])/[^/]+\.[EeWw][Aa][Rr]$|\1|" )

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
		    				app=$(echo $pacote | sed -r "s|^${origem}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[EeWw][Aa][Rr]$|\1|" )
		    				rev=$(unzip -p -a $pacote META-INF/MANIFEST.MF | grep -i implementation-version | sed -r "s|^.+ (([[:graph:]])+).*$|\1|")
						host=$(echo $HOSTNAME | cut -f1 -d '.')

						if [ -z "$rev" ]; then
							rev="N/A"
						fi

						remote_history_app_dir=${remote_history_app_parent_dir}/$(echo ${app} | tr '[:upper:]' '[:lower:]')
	    					data_deploy=$(date +%F_%Hh%Mm%Ss)
						id_deploy=$(echo ${data_deploy}_${rev}_${ambiente} | sed -r "s|/|_|g" | tr '[:upper:]' '[:lower:]')
						deploy_log_dir=${remote_history_app_dir}/${id_deploy}

						mkdir -p $log_APP $deploy_log_dir

						#expurgo de logs
						find "${remote_history_app_dir}/" -maxdepth 1 -type d | grep -vx "${remote_history_app_dir}/" | sort > $tmp_dir/logs_total
						tail $tmp_dir/logs_total --lines=${history_html_size} > $tmp_dir/logs_ultimos
						grep -vxF --file=$tmp_dir/logs_ultimos $tmp_dir/logs_total > $tmp_dir/logs_expurgo
						cat $tmp_dir/logs_expurgo | xargs --no-run-if-empty rm -Rf

						qtd_log_inicio=$(cat $log | wc -l)

		    				find $caminho_instancias_jboss -type f -regextype posix-extended -iregex "$caminho_instancias_jboss/[^/]+/deploy/$app\.[ew]ar" > "$tmp_dir/old.list"

		    				if [ $( cat "$tmp_dir/old.list" | wc -l ) -eq 0 ]; then

		    					log "ERRO" "Deploy abortado. Não foi encontrado pacote anterior. O deploy deverá ser feito manualmente."
		    					global_log "Deploy abortado. Pacote anterior não encontrado."

	    					else

	    						while read old; do

		    						log "INFO" "O pacote $old será substituído".

		    						dir_deploy=$(echo $old | sed -r "s|^(${caminho_instancias_jboss}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy])/[^/]+\.[EeWw][Aa][Rr]$|\1|")
		    						instancia_jboss=$(echo $old | sed -r "s|^${caminho_instancias_jboss}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[EeWw][Aa][Rr]$|\1|")
		    						jboss_temp="$caminho_instancias_jboss/$instancia_jboss/tmp"
		    						jboss_temp=$(find $caminho_instancias_jboss -iwholename $jboss_temp)
		    						jboss_work="$caminho_instancias_jboss/$instancia_jboss/work"
		    						jboss_work=$(find $caminho_instancias_jboss -iwholename $jboss_work)
		    						jboss_data="$caminho_instancias_jboss/$instancia_jboss/data"
		    						jboss_data=$(find $caminho_instancias_jboss -iwholename $jboss_data)

		    						#tenta localizar o script de inicialização da instância e seta a variável $script_init, caso tenha sucesso
		    						jboss_script_init "$(dirname $caminho_instancias_jboss)" "$instancia_jboss"

		    						if [ -z "$script_init" ]; then
		    							log "ERRO" "Não foi encontrado o script de inicialização da instância JBoss. O deploy deverá ser feito manualmente."
		    							global_log "Deploy abortado. Script de inicialização não encontrado."
		    						else
		    							log "INFO" "Instância do JBOSS:     \t$instancia_jboss"
		    							log "INFO" "Diretório de deploy:    \t$dir_deploy"
		    							log "INFO" "Script de inicialização:\t$script_init"

		    							parar_instancia="$script_init stop"
		    							iniciar_instancia="$script_init start"

		    							eval $parar_instancia && wait

		    							if [ $(pgrep -f "$(dirname $caminho_instancias_jboss).*-c $instancia_jboss" | wc -l) -ne 0 ]; then
		    								log "ERRO" "Não foi possível parar a instância $instancia_jboss do JBOSS. Deploy abortado."
		    								global_log "Deploy abortado. Impossível parar a instância $instancia_jboss."
		    							else
		    								rm -f $old
		    								cp $pacote $dir_deploy/$(echo $app | tr '[:upper:]' '[:lower:]').$ext
		    								chown -R jboss:jboss $dir_deploy/

		    								if [ -d "$jboss_temp" ]; then
		    									rm -Rf $jboss_temp/*
		    								fi
		    								if [ -d "$jboss_work" ]; then
		    									rm -Rf $jboss_work/*
		    								fi
		    								if [ -d "$jboss_data" ]; then
		    									rm -Rf $jboss_data/*
		    								fi

		    								eval $iniciar_instancia && wait

		    								if [ $(pgrep -f "$(dirname $caminho_instancias_jboss).*-c $instancia_jboss" | wc -l) -eq 0 ]; then
		    									log "ERRO" "O deploy do arquivo $war foi concluído, porém não foi possível reiniciar a instância do JBOSS."
		    									global_log "Deploy não concluído. Erro ao reiniciar a instância $instancia_jboss."
		    								else
		    									log "INFO" "Deploy do arquivo $war concluído com sucesso!"
		    									global_log "Deploy concluído com sucesso na instância $instancia_jboss."
		    								fi

	    								fi

		    						fi

	    						done < "$tmp_dir/old.list"

		    					rm -f $pacote

		    				fi

						qtd_log_fim=$(cat $log | wc -l)
						qtd_info_deploy=$(( $qtd_log_fim - $qtd_log_inicio ))

						tail -n ${qtd_info_deploy} $log > $deploy_log_dir/deploy_${host}.log

		    			done < "$tmp_dir/war.list"

		    		fi

		    	fi

		else
	    	log "ERRO" "Não foram encontrados os diretórios das aplicações em $origem"
		fi

		######## LOGS #########

		if [ $(ls "${destino}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then

			if [ "$origem" != "$destino" ]; then
				chk_dir "$destino"
			fi

		    	log "INFO" "Copiando logs da rotina e das instâncias JBOSS em ${caminho_instancias_jboss}..."

		        find $destino/* -type d -iname 'log' | sed -r "s|^${destino}/([^/]+)/[Ll][Oo][Gg]|\1|g" > "$tmp_dir/app_destino.list"

	    		while read app; do

				destino_log=$(find "$destino/$app/" -type d -iname 'log' 2> /dev/null)

				if [ $(echo ${destino_log} | wc -l) -eq 1 ]; then

					rm -f "$tmp_dir/app_origem.list"
			    		find $caminho_instancias_jboss -type f -regextype posix-extended -iregex "$caminho_instancias_jboss/[^/]+/deploy/$app\.[ew]ar" > "$tmp_dir/app_origem.list" 2> /dev/null

			    		if [ $(cat "$tmp_dir/app_origem.list" | wc -l) -ne 0 ]; then

			    			while read caminho_app; do

			    				instancia_jboss=$(echo $caminho_app | sed -r "s|^${caminho_instancias_jboss}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[EeWw][Aa][Rr]$|\1|")
			    				server_log=$(find "${caminho_instancias_jboss}/${instancia_jboss}" -iwholename "${caminho_instancias_jboss}/${instancia_jboss}/log/server.log" 2> /dev/null)

			    				if [ $(echo $server_log | wc -l) -eq 1 ]; then
									cd $(dirname $server_log); zip -rql1 ${destino_log}/${instancia_jboss}.zip *; cd - > /dev/null
			    					cp -f $server_log "$destino_log/server_${instancia_jboss}.log"
			    					cp -f $log "$destino_log/cron.log"
									unix2dos "$destino_log/server_${instancia_jboss}.log" > /dev/null 2>&1
									unix2dos "$destino_log/cron.log" > /dev/null 2>&1
			    				else
			    					log "ERRO" "Não há logs da instância JBOSS correspondente à aplicação $app."
			    				fi

			    			done < "$tmp_dir/app_origem.list"

			    		else
			    			log "ERRO" "A aplicação $app não foi encontrada."
			    		fi
				else
					log "ERRO" "O diretório para cópia de logs da aplicação $app não foi encontrado".
				fi

    			done < "$tmp_dir/app_destino.list"

		else
	        log "ERRO" "Não foram encontrados os diretórios das aplicações em $destino"
		fi

	done

	end "0"

}

###### INICIALIZAÇÃO ######

trap "end 1; exit" SIGQUIT SIGINT SIGHUP SIGTERM

find_install_dir

arq_props_global="${install_dir}/conf/global.conf"
dir_props_local="${install_dir}/conf/local.d"
arq_props_local=$(find "$dir_props_local" -type f -iname "*.conf" -print)
arq_props_local=$(echo "$arq_props_local" | sed -r "s%(.)$%\1|%g")

# Verifica se o arquivo global.conf atende ao template correspondente.

if [ -f "$arq_props_global" ]; then
	dos2unix "$arq_props_global" > /dev/null 2>&1
else
	exit 1
fi

if [ "$(grep -v --file=${install_dir}/template/global.template $arq_props_global | wc -l)" -ne "0" ] \
	|| [ $(cat $arq_props_global | sed 's|"||g' | grep -Ev "^#|^$" | grep -Ex "^DIR_.+='?AMBIENTE'?$" | wc -l) -ne "1" ];
then
	exit 1
fi

# Carrega constantes.

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

# Executa deploys e copia logs das instâncias jboss

if [ $(echo "$arq_props_local" | wc -w) -ne 0 ]; then
	jboss_instances >> $log 2>&1
else
	exit 1
fi
