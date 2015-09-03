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
	
	diretorio_instalacao=$(dirname $caminho_script)

}

function log () {

	##### LOG DE DEPLOY DETALHADO ####

	echo -e "$(date +"%F %Hh%Mm%Ss") : $HOSTNAME : $1 : $2" 

}

function global_log () {
		
	##### LOG DE DEPLOYS GLOBAL #####

	obs_log="$1"
	
	horario_log=$(echo "$(date +%F_%Hh%Mm%Ss)" | sed -r "s|^(....)-(..)-(..)_(.........)$|\3/\2/\1;\4|")
	app_log="$(echo "$APP" | tr '[:upper:]' '[:lower:]')"
	ambiente_log="$(echo "$AMBIENTE" | tr '[:upper:]' '[:lower:]')"
	host_log="$(echo "$HOSTNAME" | sed -r "s/^([^\.]+)\..*$/\1/" | tr '[:upper:]' '[:lower:]')"
	
	mensagem_log="$horario_log;$app_log;$REV;$ambiente_log;$host_log;$obs_log;"

	##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

	while [ -f "${CAMINHO_LOCK_REMOTO}/$ARQ_LOCK_HISTORICO" ]; do						#nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
		sleep 1	
	done

	EDIT_LOG=1
	touch "${CAMINHO_LOCK_REMOTO}/$ARQ_LOCK_HISTORICO"

	touch ${CAMINHO_HISTORICO_REMOTO}/$ARQ_HISTORICO
	touch ${LOG_APP}/$ARQ_HISTORICO

	tail --lines=$QTD_LOG_DEPLOY ${CAMINHO_HISTORICO_REMOTO}/$ARQ_HISTORICO > $TMP_DIR/deploy_log_novo
	tail --lines=$QTD_LOG_APP ${LOG_APP}/$ARQ_HISTORICO > $TMP_DIR/app_log_novo

	echo -e "$mensagem_log" >> $TMP_DIR/deploy_log_novo
	echo -e "$mensagem_log" >> $TMP_DIR/app_log_novo
	
	cp -f $TMP_DIR/deploy_log_novo ${CAMINHO_HISTORICO_REMOTO}/$ARQ_HISTORICO
	cp -f $TMP_DIR/app_log_novo ${LOG_APP}/$ARQ_HISTORICO

	rm -f ${CAMINHO_LOCK_REMOTO}/$ARQ_LOCK_HISTORICO 							#remove a trava sobre o arquivo de log tão logo seja possível.
	EDIT_LOG=0
}

function jboss_script_init () {

	##### LOCALIZA SCRIPT DE INICIALIZAÇÃO DA INSTÂNCIA JBOSS #####
	
	local caminho_jboss=$1
	local instancia=$2
	
	if [ -n "$caminho_jboss" ] && [ -n "$instancia" ] && [ -d  "${caminho_jboss}/server/${instancia}" ]; then
	
		unset SCRIPT_INIT
		find /etc/init.d/ -type f -iname '*jboss*' > "$TMP_DIR/scripts_jboss.list"
		
		#verifica todos os scripts de jboss encontrados em /etc/init.d até localizar o correto.
		while read script_jboss && [ -z "$SCRIPT_INIT" ]; do
		
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
						SCRIPT_INIT=$script_jboss
					fi
					
				fi
				
			fi
			
		done < "$TMP_DIR/scripts_jboss.list"
		
	else
		log "ERRO" "Parâmetros incorretos ou instância JBOSS não encontrada."
	fi
	
}

function end () {

	if [ -d "$TMP_DIR" ]; then
		rm -Rf ${TMP_DIR}/*
	fi

	if [ -f "$LOCK" ]; then
		rm -f $LOCK
	fi

	if [ "$EDIT_LOG" == "1" ]; then
		rm -f ${CAMINHO_LOCK_REMOTO}/$ARQ_LOCK_HISTORICO
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

	if [ "$nivel" == "$QTD_DIR" ]; then
		set_var="$set_var=$(find "$raiz" -iwholename "$dir_acima" 2> /dev/null)"
		eval $set_var
	else
		log "ERRO" "Parâmetros incorretos no arquivo '$LOCAL_CONF'."
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
		
    	# eliminar arquivos em local incorreto ou com extensão diferente de .war / .log
    	find "$raiz" -type f | grep -Eixv "^$raiz/[^/]+/deploy/[^/]+\.war$|^$raiz/[^/]+/log/[^/]+\.log$|^$raiz/[^/]+/log/[^/]+\.zip$" | xargs -r -d "\n" rm -fv

}

function jboss_instances () {

	if [ ! -d "$CAMINHO_PACOTES_REMOTO" ] || [ ! -d "$CAMINHO_LOGS_REMOTO" ]; then
		log "ERRO" "Parâmetros incorretos no arquivo '${ARQ_PROPS_GLOBAL}'."
		end "1"
	fi

	echo $ARQ_PROPS_LOCAL | while read -d '|' LOCAL_CONF; do
	
		# Valida e carrega parâmetros referentes ao ambiente JBOSS.
		
		cat $ARQ_PROPS_GLOBAL | grep -E "DIR_.+='.+'" | sed 's/"//g' | sed "s/'//g" | sed -r "s|^[^ ]+=([^ ]+)$|\^\1=|" > $TMP_DIR/parametros_obrigatorios
	
		dos2unix "$LOCAL_CONF" > /dev/null 2>&1

		if [ $(cat $LOCAL_CONF | sed 's|"||g' | grep -Ev "^#|^$" | grep -Ex "^CAMINHO_INSTANCIAS_JBOSS='?/.+/server'?$" | wc -l) -ne "1" ] \
			|| [ $(cat $LOCAL_CONF | sed 's|"||g' | grep -Ev "^CAMINHO_INSTANCIAS_JBOSS=|^#|^$" | grep -Evx "^[a-zA-Z0-9_]+='?[a-zA-Z0-9_]+'?$" | wc -l) -ne "0" ] \
			|| [ $(cat $LOCAL_CONF | sed 's|"||g' | grep -Ev "^CAMINHO_INSTANCIAS_JBOSS=|^#|^$" | grep -Ev --file=$TMP_DIR/parametros_obrigatorios | wc -l) -ne "0" ];
		then
			log "ERRO" "Parâmetros incorretos no arquivo '$LOCAL_CONF'."
			continue
		else
			source "$LOCAL_CONF" || continue	
			rm -f "$TMP_DIR/*"
		fi

		# verificar se o caminho para obtenção dos pacotes / gravação de logs está disponível.
		
		set_dir "$CAMINHO_PACOTES_REMOTO" 'ORIGEM'
		set_dir "$CAMINHO_LOGS_REMOTO" 'DESTINO'
		
		if [ $( echo "$ORIGEM" | wc -w ) -ne 1 ] || [ ! -d "$ORIGEM" ] || [ $( echo "$DESTINO" | wc -w ) -ne 1 ] || [ ! -d "$DESTINO" ]; then
			log "ERRO" "O caminho para o diretório de pacotes / logs não foi encontrado ou possui espaços."
			continue
		fi
		
		if [ $(ls "${ORIGEM}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then
	
			chk_dir ${ORIGEM}		

		    	######## DEPLOY #########
		    	
		    	# Verificar se há arquivos para deploy.
		    	
		    	log "INFO" "Procurando novos pacotes..."
		    	
		    	find "$ORIGEM" -type f -iname "*.war" > $TMP_DIR/arq.list
		    	
	    		if [ $(cat $TMP_DIR/arq.list | wc -l) -lt 1 ]; then
		    		log "INFO" "Não foram encontrados novos pacotes para deploy."
		    	else
		    		# Caso haja arquivos, verificar se o nome do pacote corresponde ao diretório da aplicação.
		    	
		    		rm -f "$TMP_DIR/remove_incorretos.list"
				touch "$TMP_DIR/remove_incorretos.list"
		    	
		    		while read l; do
		    	
		    			WAR=$( echo $l | sed -r "s|^${ORIGEM}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy]/([^/]+)\.[Ww][Aa][Rr]$|\1|" )
		    			APP=$( echo $l | sed -r "s|^${ORIGEM}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[Ww][Aa][Rr]$|\1|" )
		    		
		    			if [ $(echo $WAR | grep -Ei "^$APP" | wc -l) -ne 1 ]; then
		    				echo $l >> "$TMP_DIR/remove_incorretos.list"
		    			fi
		    			
		    		done < "$TMP_DIR/arq.list"
		    		
		    		if [ $(cat $TMP_DIR/remove_incorretos.list | wc -l) -gt 0 ]; then
		    			log "WARN" "Removendo pacotes em diretórios incorretos..."
		    			cat "$TMP_DIR/remove_incorretos.list" | xargs -r -d "\n" rm -fv
		    		fi
		    	
		    		# Caso haja pacotes, deve haver no máximo um pacote por diretório
		    	
		    		find "$ORIGEM" -type f -iname "*.war" > $TMP_DIR/arq.list
		    	
				rm -f "$TMP_DIR/remove_versoes.list"
				touch "$TMP_DIR/remove_versoes.list"
		    	
		    		while read l; do
		    	
	    				WAR=$( echo $l | sed -r "s|^${ORIGEM}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy]/([^/]+)\.[Ww][Aa][Rr]$|\1|" )
		    			DIR=$( echo $l | sed -r "s|^(${ORIGEM}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy])/[^/]+\.[Ww][Aa][Rr]$|\1|" )
		    		
		    			if [ $( find $DIR -type f | wc -l ) -ne 1 ]; then
		    				echo $l >> $TMP_DIR/remove_versoes.list
		    			fi
		    			
		    		done < "$TMP_DIR/arq.list"
		    	
		    		if [ $(cat $TMP_DIR/remove_versoes.list | wc -l) -gt 0 ]; then
		    			log "WARN" "Removendo pacotes com mais de uma versão..."
		    			cat $TMP_DIR/remove_versoes.list | xargs -r -d "\n" rm -fv
		    		fi
		    	
	    			find "$ORIGEM" -type f -iname "*.war" > $TMP_DIR/war.list
			    	
		    		if [ $(cat $TMP_DIR/war.list | wc -l) -lt 1 ]; then
	    				log "INFO" "Não há novos pacotes para deploy."
		    		else
		    			log "INFO" "Verificação do diretório ${CAMINHO_PACOTES_REMOTO} concluída. Iniciando processo de deploy dos pacotes abaixo."
		    			cat $TMP_DIR/war.list 
		    		
		    			while read PACOTE; do
		    	
		    				WAR=$(basename $PACOTE)
		    				APP=$(echo $PACOTE | sed -r "s|^${ORIGEM}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[Ww][Aa][Rr]$|\1|" )
		    				REV=$(unzip -p -a $PACOTE META-INF/MANIFEST.MF | grep -i implementation-version | sed -r "s|^.+ (([[:graph:]])+).*$|\1|")
						HOST=$(echo $HOSTNAME | cut -f1 -d '.')
						
						if [ -z "$REV" ]; then
							REV="N/A"
						fi
						
						LOG_APP=${CAMINHO_HISTORICO_SISTEMAS_REMOTO}/$(echo ${APP} | tr '[:upper:]' '[:lower:]')					
	    					DATA_DEPLOY=$(date +%F_%Hh%Mm%Ss)
						ID_DEPLOY=$(echo ${DATA_DEPLOY}_${REV}_${AMBIENTE} | sed -r "s|/|_|g" | tr '[:upper:]' '[:lower:]')
						INFO_DIR=${LOG_APP}/${ID_DEPLOY}

						mkdir -p $LOG_APP $INFO_DIR
						
						#expurgo de logs
						find "${LOG_APP}/" -maxdepth 1 -type d | grep -vx "${LOG_APP}/" | sort > $TMP_DIR/logs_total
						tail $TMP_DIR/logs_total --lines=${QTD_LOG_HTML} > $TMP_DIR/logs_ultimos
						grep -vxF --file=$TMP_DIR/logs_ultimos $TMP_DIR/logs_total > $TMP_DIR/logs_expurgo
						cat $TMP_DIR/logs_expurgo | xargs --no-run-if-empty rm -Rf

						QTD_LOG_INICIO=$(cat $LOG | wc -l)	

		    				find $CAMINHO_INSTANCIAS_JBOSS -type f -regextype posix-extended -iregex "$CAMINHO_INSTANCIAS_JBOSS/[^/]+/deploy/$APP\.war" > "$TMP_DIR/old.list"
		    		
		    				if [ $( cat "$TMP_DIR/old.list" | wc -l ) -eq 0 ]; then
		    				
		    					log "ERRO" "Deploy abortado. Não foi encontrado pacote anterior. O deploy deverá ser feito manualmente."
		    					global_log "Deploy abortado. Pacote anterior não encontrado."
		    				
	    					else
		    				
	    						while read OLD; do
		    					
		    						log "INFO" "O pacote $OLD será substituído".
	    					
		    						DIR_DEPLOY=$(echo $OLD | sed -r "s|^(${CAMINHO_INSTANCIAS_JBOSS}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy])/[^/]+\.[Ww][Aa][Rr]$|\1|")
		    						INSTANCIA_JBOSS=$(echo $OLD | sed -r "s|^${CAMINHO_INSTANCIAS_JBOSS}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[Ww][Aa][Rr]$|\1|")
		    						JBOSS_TEMP="$CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS/tmp"
		    						JBOSS_TEMP=$(find $CAMINHO_INSTANCIAS_JBOSS -iwholename $JBOSS_TEMP)
		    						JBOSS_WORK="$CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS/work"
		    						JBOSS_WORK=$(find $CAMINHO_INSTANCIAS_JBOSS -iwholename $JBOSS_WORK)
		    						JBOSS_DATA="$CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS/data"
		    						JBOSS_DATA=$(find $CAMINHO_INSTANCIAS_JBOSS -iwholename $JBOSS_DATA)
		    						
		    						#tenta localizar o script de inicialização da instância e seta a variável $SCRIPT_INIT, caso tenha sucesso
		    						jboss_script_init "$(dirname $CAMINHO_INSTANCIAS_JBOSS)" "$INSTANCIA_JBOSS"
		    						
		    						if [ -z "$SCRIPT_INIT" ]; then
		    							log "ERRO" "Não foi encontrado o script de inicialização da instância JBoss. O deploy deverá ser feito manualmente."
		    							global_log "Deploy abortado. Script de inicialização não encontrado."
		    						else
		    							log "INFO" "Instância do JBOSS:     \t$INSTANCIA_JBOSS"
		    							log "INFO" "Diretório de deploy:    \t$DIR_DEPLOY"
		    							log "INFO" "Script de inicialização:\t$SCRIPT_INIT"
		    					
		    							PARAR_INSTANCIA="$SCRIPT_INIT stop"
		    							INICIAR_INSTANCIA="$SCRIPT_INIT start"
		    					
		    							eval $PARAR_INSTANCIA && wait
		    		
		    							if [ $(pgrep -f "$(dirname $CAMINHO_INSTANCIAS_JBOSS).*-c $INSTANCIA_JBOSS" | wc -l) -ne 0 ]; then
		    								log "ERRO" "Não foi possível parar a instância $INSTANCIA_JBOSS do JBOSS. Deploy abortado."
		    								global_log "Deploy abortado. Impossível parar a instância $INSTANCIA_JBOSS."	
		    							else
		    								rm -f $OLD 
		    								cp $PACOTE $DIR_DEPLOY/$(echo $APP | tr '[:upper:]' '[:lower:]').war 
		    								chown -R jboss:jboss $DIR_DEPLOY/ 
		    						
		    								if [ -d "$JBOSS_TEMP" ]; then
		    									rm -Rf $JBOSS_TEMP/* 
		    								fi
		    								if [ -d "$JBOSS_WORK" ]; then
		    									rm -Rf $JBOSS_WORK/* 
		    								fi
		    								if [ -d "$JBOSS_DATA" ]; then
		    									rm -Rf $JBOSS_DATA/* 
		    								fi
		    				 
		    								eval $INICIAR_INSTANCIA && wait				
		    		
		    								if [ $(pgrep -f "$(dirname $CAMINHO_INSTANCIAS_JBOSS).*-c $INSTANCIA_JBOSS" | wc -l) -eq 0 ]; then
		    									log "ERRO" "O deploy do arquivo $WAR foi concluído, porém não foi possível reiniciar a instância do JBOSS."
		    									global_log "Deploy não concluído. Erro ao reiniciar a instância $INSTANCIA_JBOSS."
		    								else
		    									log "INFO" "Deploy do arquivo $WAR concluído com sucesso!"
		    									global_log "Deploy concluído com sucesso na instância $INSTANCIA_JBOSS."
		    								fi
		    							
	    								fi
		    							
		    						fi
		    						
	    						done < "$TMP_DIR/old.list"
		    					
		    					rm -f $PACOTE
		    					
		    				fi

						QTD_LOG_FIM=$(cat $LOG | wc -l)
						QTD_INFO_DEPLOY=$(( $QTD_LOG_FIM - $QTD_LOG_INICIO ))
													
						tail -n ${QTD_INFO_DEPLOY} $LOG > $INFO_DIR/deploy_${HOST}.log
					
		    			done < "$TMP_DIR/war.list"
		    			
		    		fi
		    		
		    	fi
    	
		else
	        	log "ERRO" "Não foram encontrados os diretórios das aplicações em $ORIGEM"
		fi
		
		######## LOGS #########
		
		if [ $(ls "${DESTINO}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then
		
			if [ "$ORIGEM" != "$DESTINO" ]; then
				chk_dir "$DESTINO"
			fi		

		    	log "INFO" "Copiando logs da rotina e das instâncias JBOSS em ${CAMINHO_INSTANCIAS_JBOSS}..."
		    
		        find $DESTINO/* -type d -iname 'log' | sed -r "s|^${DESTINO}/([^/]+)/[Ll][Oo][Gg]|\1|g" > "$TMP_DIR/app_destino.list"
			
	    		while read APP; do
		    	
				DESTINO_LOG=$(find "$DESTINO/$APP/" -type d -iname 'log' 2> /dev/null)
				
				if [ $(echo $DESTINO_LOG | wc -l) -eq 1 ]; then
	
					rm -f "$TMP_DIR/app_origem.list"
			    		find $CAMINHO_INSTANCIAS_JBOSS -type f -regextype posix-extended -iregex "$CAMINHO_INSTANCIAS_JBOSS/[^/]+/deploy/$APP\.war" > "$TMP_DIR/app_origem.list" 2> /dev/null
	    		
			    		if [ $(cat "$TMP_DIR/app_origem.list" | wc -l) -ne 0 ]; then
			    		
			    			while read "CAMINHO_APP"; do
			    				
			    				INSTANCIA_JBOSS=$(echo $CAMINHO_APP | sed -r "s|^${CAMINHO_INSTANCIAS_JBOSS}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[Ww][Aa][Rr]$|\1|")
			    				LOG_APP=$(find "${CAMINHO_INSTANCIAS_JBOSS}/${INSTANCIA_JBOSS}" -iwholename "${CAMINHO_INSTANCIAS_JBOSS}/${INSTANCIA_JBOSS}/log/server.log" 2> /dev/null)
			    				
			    				if [ $(echo $LOG_APP | wc -l) -eq 1 ]; then
								cd $(dirname $LOG_APP); zip -rql1 ${DESTINO_LOG}/${INSTANCIA_JBOSS}.zip *; cd - > /dev/null
			    					cp -f $LOG_APP "$DESTINO_LOG/server_${INSTANCIA_JBOSS}.log"
			    					cp -f $LOG "$DESTINO_LOG/cron.log"
								unix2dos "$DESTINO_LOG/server_${INSTANCIA_JBOSS}.log" > /dev/null 2>&1
								unix2dos "$DESTINO_LOG/cron.log" > /dev/null 2>&1
			    				else
			    					log "ERRO" "Não há logs da instância JBOSS correspondente à aplicação $APP."
			    				fi		
			    
			    			done < "$TMP_DIR/app_origem.list"
			    		
			    		else
			    			log "ERRO" "A aplicação $APP não foi encontrada."
			    		fi
				else
					log "ERRO" "O diretório para cópia de logs da aplicação $APP não foi encontrado".
				fi
	    	
    			done < "$TMP_DIR/app_destino.list"
		
		else
	        	log "ERRO" "Não foram encontrados os diretórios das aplicações em $DESTINO"
		fi
		
	done
	
	end "0"

}

###### INICIALIZAÇÃO ######

trap "end 1; exit" SIGQUIT SIGINT SIGHUP SIGTERM

install_dir

ARQ_PROPS_GLOBAL="${diretorio_instalacao}/conf/global.conf"
DIR_PROPS_LOCAL="${diretorio_instalacao}/conf/local.d"
ARQ_PROPS_LOCAL=$(find "$DIR_PROPS_LOCAL" -type f -iname "*.conf" -print)
ARQ_PROPS_LOCAL=$(echo "$ARQ_PROPS_LOCAL" | sed -r "s%(.)$%\1|%g")

# Verifica se o arquivo global.conf atende ao template correspondente.

if [ -f "$ARQ_PROPS_GLOBAL" ]; then
	dos2unix "$ARQ_PROPS_GLOBAL" > /dev/null 2>&1
else
	exit 1
fi

if [ "$(grep -v --file=${diretorio_instalacao}/template/global.template $ARQ_PROPS_GLOBAL | wc -l)" -ne "0" ] \
	|| [ $(cat $ARQ_PROPS_GLOBAL | sed 's|"||g' | grep -Ev "^#|^$" | grep -Ex "^DIR_.+='?AMBIENTE'?$" | wc -l) -ne "1" ];
then
	exit 1
fi

# Carrega constantes.

source "$ARQ_PROPS_GLOBAL" || exit 1

# cria lock.

mkdir -p $(dirname "$LOCK")

if [ -f "$LOCK" ]; then
	exit 0
else
	touch $LOCK
fi

# cria diretório temporário.

if [ ! -z "$TMP_DIR" ]; then
	mkdir -p $TMP_DIR
else
	exit 0
fi

# cria pasta de logs / expurga logs de deploy do mês anterior.

if [ ! -z "$LOG_DIR" ]; then
	mkdir -p $LOG_DIR
	touch $LOG
	echo "" >> $LOG
	find $LOG_DIR -type f | grep -v $(date "+%Y-%m") | xargs rm -f
else
	exit 0
fi

# Executa deploys e copia logs das instâncias jboss

if [ $(echo "$ARQ_PROPS_LOCAL" | wc -w) -ne 0 ]; then
	jboss_instances >> $LOG 2>&1
else
	exit 1
fi
