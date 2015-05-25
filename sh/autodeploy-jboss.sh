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
	
	horario_log=$(echo "$(date +%Y%m%d%H%M%S)" | sed -r "s|^(....)(..)(..)(..)(..)(..)$|\3/\2/\1          \4h\5m\6s           |")
		
	tamanho_app=$(echo -n $APP | wc -m)
	app_log=$(echo '                    ' | sed -r "s|^ {$tamanho_app}|$APP|")

	rev_log=$(echo $REV | sed -r "s|^(.........).*$|\1|")
	tamanho_rev=$(echo -n $rev_log | wc -m)
 	rev_log=$(echo '                    ' | sed -r "s|^ {$tamanho_rev}|$rev_log|")

	tamanho_ambiente=$(echo -n $AMBIENTE | wc -m) 
	ambiente_log=$(echo '                    ' | sed -r "s|^ {$tamanho_ambiente}|$AMBIENTE|")

	host_log=$(echo $HOSTNAME | sed -r "s/^([^\.]+)\..*$/\1/")
	tamanho_host=$(echo -n $host_log | wc -m) 
	host_log=$(echo '                    ' | sed -r "s|^ {$tamanho_host}|$host_log|")
	
	mensagem_log="$horario_log$app_log$rev_log$ambiente_log$host_log$obs_log"

	##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

	while [ -f "$GLOBAL_LOCK" ]; do						#nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
		sleep 1	
	done

	EDIT_LOG=1
	touch "$GLOBAL_LOCK"

	touch $GLOBAL_LOG

	echo -e "$mensagem_log" >> $GLOBAL_LOG
	unix2dos $GLOBAL_LOG > /dev/null 2>&1
	
	rm -f $GLOBAL_LOCK 							#remove a trava sobre o arquivo de log tão logo seja possível.
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
		
				#retorna a primeira linha do tipo $JBOSS_HOME/server/$JBOSS_CONF
				local linha_script=$(grep -Ex "^[^#]+[\=].*[/\$].+/server/[^/]+/.*$" "$script_jboss" | head -1 )
	
				if [ -n "$linha_script" ]; then
				
					local jboss_conf=$(echo "$linha_script" | sed -r "s|^.*/server/([^/]+).*$|\1|")
		
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
		rm -f $GLOBAL_LOCK
	fi
	
	exit "$1"
}

function jboss_instances () {

	if [ ! -d "$CAMINHO_PACOTES_REMOTO" ] || [ ! -d "$CAMINHO_LOGS_REMOTO" ]; then
		log "ERRO" "Parâmetros incorretos no arquivo '${ARQ_PROPS_GLOBAL}'."
		end "1"
	fi
		
	echo $ARQ_PROPS_LOCAL | while read LOCAL_CONF; do
	
		# Verifica se o arquivo atende ao template correspondente.
	
		if [ "$(grep -v --file=${diretorio_instalacao}/template/local.template $LOCAL_CONF | wc -l)" -ne "0" ]; then
			continue
		fi
	
		# Carrega parâmetros referentes os ambiente JBOSS.
	
		source "$LOCAL_CONF" || continue	
		rm -f "$TMP_DIR/*"
		
		######## VALIDAÇÃO #########
		
		if [ -z $(echo "$CAMINHO_INSTANCIAS_JBOSS" | grep -Ex "^/.+/server$") ] \
			|| [ ! -d "$CAMINHO_INSTANCIAS_JBOSS" ] \
			|| [ -z $(echo "$VERSAO_JBOSS" | grep -Ex "^[1-9]$") ] \
			|| [ -z $(echo "$IDENTIFICACAO" | grep -Ex "^[a-zA-Z0-9_]+$") ] \
			|| [ -z $(echo "$AMBIENTE" | grep -Ex "^[a-zA-Z]+$") ];
		then
			log "ERRO" "Parâmetros incorretos no arquivo '${ARQ_PROPS_LOCAL}'."
			continue
		fi

		# verificar se o caminho para obtenção dos pacotes / gravação de logs está disponível.
		
		ORIGEM="${CAMINHO_PACOTES_REMOTO}/${AMBIENTE}/${IDENTIFICACAO}/JBOSS_${VERSAO_JBOSS}"
		DESTINO="${CAMINHO_LOGS_REMOTO}/${AMBIENTE}/${IDENTIFICACAO}/JBOSS_${VERSAO_JBOSS}"
		
		ORIGEM=$(find "$CAMINHO_PACOTES_REMOTO" -iwholename "$ORIGEM" 2> /dev/null)
		DESTINO=$(find "$CAMINHO_LOGS_REMOTO" -iwholename "$DESTINO" 2> /dev/null)
		
		if [ $( echo "$ORIGEM" | wc -w ) -ne 1 ] || [ ! -d "$ORIGEM" ] || [ $( echo "$DESTINO" | wc -w ) -ne 1 ] || [ ! -d "$DESTINO" ]; then
			log "ERRO" "O caminho para o diretório de pacotes / logs não foi encontrado ou possui espaços."
			continue
		fi
		
		if [ $(ls "${ORIGEM}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then
	
		        log "INFO" "Verificando a consistência da estrutura de diretórios em ${CAMINHO_PACOTES_REMOTO}..."
		
		    	# eliminar da estrutura de diretórios subjacente os arquivos e subpastas cujos nomes contenham espaços.
		    	find ${ORIGEM}/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rfv
		
		    	# garantir integridade da estrutura de diretórios, eliminando subpastas inseridas incorretamente.
		    	find ${ORIGEM}/* -type d | grep -Ei "^${ORIGEM}/[^/]+/[^/]+" | xargs -r -d "\n" rm -Rfv
		
		    	# eliminar arquivos em local incorreto ou com extensão diferente de .war / .log
		    	find "$ORIGEM" -type f | grep -Eixv "^${ORIGEM}/[^/]+/[^/]+\.war$" | xargs -r -d "\n" rm -fv
		
		    	######## DEPLOY #########
		    	
		    	# Verificar se há arquivos para deploy.
		    	
		    	log "INFO" "Procurando novos pacotes..."
		    	
		    	find "$ORIGEM" -type f > $TMP_DIR/arq.list
		    	
	    		if [ $(cat $TMP_DIR/arq.list | wc -l) -lt 1 ]; then
		    		log "INFO" "Não foram encontrados novos pacotes para deploy."
		    	else
		    		# Caso haja arquivos, verificar se o nome do pacote corresponde ao diretório da aplicação.
		    	
		    		echo '' > "$TMP_DIR/remove_incorretos.list"
		    	
		    		while read l; do
		    	
		    			WAR=$( echo $l | sed -r "s|^${ORIGEM}/[^/]+/([^/]+)\.[Ww][Aa][Rr]$|\1|" )
		    			APP=$( echo $l | sed -r "s|^${ORIGEM}/([^/]+)/[^/]+\.[Ww][Aa][Rr]$|\1|" )
		    		
		    			if [ $(echo $WAR | grep -Ei "^$APP" | wc -l) -ne 1 ]; then
		    				echo $l >> "$TMP_DIR/remove_incorretos.list"
		    			fi
		    			
		    		done < "$TMP_DIR/arq.list"
		    		
		    		if [ $(cat $TMP_DIR/remove_incorretos.list | wc -l) -gt 0 ]; then
		    			log "WARN" "Removendo pacotes em diretórios incorretos..."
		    			cat "$TMP_DIR/remove_incorretos.list" | xargs -r -d "\n" rm -fv
		    		fi
		    	
		    		# Caso haja pacotes, deve haver no máximo um pacote por diretório
		    	
		    		find "$ORIGEM" -type f > $TMP_DIR/arq.list
		    	
		    		echo '' > $TMP_DIR/remove_versoes.list
		    	
		    		while read l; do
		    	
	    				WAR=$( echo $l | sed -r "s|^${ORIGEM}/[^/]+/([^/]+)\.[Ww][Aa][Rr]$|\1|" )
		    			DIR=$( echo $l | sed -r "s|^(${ORIGEM}/[^/]+)/[^/]+\.[Ww][Aa][Rr]$|\1|" )
		    		
		    			if [ $( find $DIR -type f | wc -l ) -ne 1 ]; then
		    				echo $l >> $TMP_DIR/remove_versoes.list
		    			fi
		    			
		    		done < "$TMP_DIR/arq.list"
		    	
		    		if [ $(cat $TMP_DIR/remove_versoes.list | wc -l) -gt 0 ]; then
		    			log "WARN" "Removendo pacotes com mais de uma versão..."
		    			cat $TMP_DIR/remove_versoes.list | xargs -r -d "\n" rm -fv
		    		fi
		    	
	    			find "$ORIGEM" -type f > $TMP_DIR/war.list
			    	
		    		if [ $(cat $TMP_DIR/war.list | wc -l) -lt 1 ]; then
	    				log "INFO" "Não há novos pacotes para deploy."
		    		else
		    			log "INFO" "Verificação do diretório ${CAMINHO_PACOTES_REMOTO} concluída. Iniciando processo de deploy dos pacotes abaixo."
		    			cat $TMP_DIR/war.list 
		    		
		    			while read PACOTE; do
		    	
		    				WAR=$(basename $PACOTE)
		    				REV=$(unzip -p -a $PACOTE META-INF/MANIFEST.MF | grep -i implementation-version | sed -r "s|^.+ (([[:graph:]])+).*$|\1|")
		    				APP=$(echo $PACOTE | sed -r "s|^${ORIGEM}/([^/]+)/[^/]+\.[Ww][Aa][Rr]$|\1|" )
	    					
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
		    								cp $PACOTE $DIR_DEPLOY/$APP.war 
		    								chown jboss:jboss $DIR_DEPLOY/$APP.war 
		    						
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
		    									global_log "Deploy concluído. Erro ao iniciar a instância $INSTANCIA_JBOSS."
		    								else
		    									log "INFO" "Deploy do arquivo $WAR concluído com sucesso!"
		    									global_log "Deploy do pacote $WAR concluído com sucesso na instância $INSTANCIA_JBOSS."
		    								fi
		    							
	    								fi
		    							
		    						fi
		    						
	    						done < "$TMP_DIR/old.list"
		    					
		    					rm -f $PACOTE
		    					
		    				fi
		    				
		    			done < "$TMP_DIR/war.list"
		    			
		    		fi
		    		
		    	fi
    	
		else
	        	log "ERRO" "Não foram encontrados os diretórios das aplicações em $ORIGEM"
		fi
		
		######## LOGS #########
		
		if [ $(ls "${DESTINO}/" -l | grep -E "^d" | wc -l) -ne 0 ]; then
		
			log "INFO" "Verificando a consistência da estrutura de diretórios em ${CAMINHO_LOGS_REMOTO}..."
		
	    		# eliminar da estrutura de diretórios subjacente os arquivos e subpastas cujos nomes contenham espaços.
		    	find ${DESTINO}/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rfv
		    	
		    	# garantir integridade da estrutura de diretórios, eliminando subpastas inseridas incorretamente.
		    	find ${DESTINO}/* -type d | grep -Ei "^${DESTINO}/[^/]+/[^/]+" | xargs -r -d "\n" rm -Rfv
		    	
		    	# eliminar arquivos em local incorreto ou com extensão diferente de .war / .log
		    	find "$DESTINO" -type f | grep -Eixv "^${DESTINO}/[^/]+/[^/]+\.log$" | xargs -r -d "\n" rm -fv
			
		    	log "INFO" "Copiando logs da rotina e das instâncias JBOSS em ${CAMINHO_INSTANCIAS_JBOSS}..."
		    
		        find $DESTINO/* -type d | sed -r "s|^${DESTINO}/||g" > "$TMP_DIR/app_destino.list"
		
	    		while read APP; do
		    	
				rm -f "$TMP_DIR/app_origem.list"
		    		touch "$TMP_DIR/app_origem.list"
		    		find $CAMINHO_INSTANCIAS_JBOSS -type f -regextype posix-extended -iregex "$CAMINHO_INSTANCIAS_JBOSS/[^/]+/deploy/$APP\.war" > "$TMP_DIR/app_origem.list" 2> /dev/null
    		
		    		if [ $(cat "$TMP_DIR/app_origem.list" | wc -l) -ne 0 ]; then
		    		
		    			while read "CAMINHO_APP"; do
		    				
		    				INSTANCIA_JBOSS=$(echo $CAMINHO_APP | sed -r "s|^${CAMINHO_INSTANCIAS_JBOSS}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[Ww][Aa][Rr]$|\1|")
		    				LOG_APP=$(find "${CAMINHO_INSTANCIAS_JBOSS}/${INSTANCIA_JBOSS}" -iwholename "${CAMINHO_INSTANCIAS_JBOSS}/${INSTANCIA_JBOSS}/log/server.log" 2> /dev/null)
		    				
		    				if [ $(echo $LOG_APP | wc -l) -eq 1 ]; then
		    					cp -f $LOG_APP "$DESTINO/$APP/server_${INSTANCIA_JBOSS}.log"
		    					cp -f $LOG "$DESTINO/$APP/cron.log"
							unix2dos "$DESTINO/$APP/server_${INSTANCIA_JBOSS}.log" > /dev/null 2>&1
							unix2dos "$DESTINO/$APP/cron.log" > /dev/null 2>&1
		    				else
		    					log "ERRO" "Não há logs da instância JBOSS correspondente à aplicação $APP."
		    				fi		
		    
		    			done < "$TMP_DIR/app_origem.list"
		    		
		    		else
		    			log "ERRO" "A aplicação $APP não foi encontrada."
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
ARQ_PROPS_LOCAL=$(find "$DIR_PROPS_LOCAL" -type f -iname "*.conf")

# Verifica se o arquivo global.conf atende ao template correspondente.

if [ "$(grep -v --file=${diretorio_instalacao}/template/global.template $ARQ_PROPS_GLOBAL | wc -l)" -ne "0" ]; then
	exit 1
fi

# Carrega constantes.

source "$ARQ_PROPS_GLOBAL" || exit 1

# cria lock.

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

jboss_instances >> $LOG 2>&1
