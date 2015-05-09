#!/bin/bash
#
# Script para automatização dos deploys e disponibilização de logs do ambiente JBOSS / Linux.
#

###### FUNÇÕES ######

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

	tamanho_host=$(echo -n $HOST | wc -m) 
	host_log=$(echo '                    ' | sed -r "s|^ {$tamanho_host}|$HOST|")
	
	mensagem_log="$horario_log$app_log$rev_log$ambiente_log$host_log$obs_log"

	##### ABRE O ARQUIVO DE LOG PARA EDIÇÃO ######

	while [ -f "$GLOBAL_LOCK/deploy_log_edit" ]; do						#nesse caso, o processo de deploy não é interrompido. O script é liberado para escrever no log após a remoção do arquivo de trava.
		sleep 1	
	done

	EDIT_LOG=1
	touch "$GLOBAL_LOCK/deploy_log_edit"

	touch $GLOBAL_LOG

	echo -e "$mensagem_log" >> $GLOBAL_LOG
	
	rm -f $GLOBAL_LOCK/deploy_log_edit 							#remove a trava sobre o arquivo de log tão logo seja possível.
	EDIT_LOG=0
}

function jboss_script_init () {

	##### LOCALIZA SCRIPT DE INICIALIZAÇÃO DA INSTÂNCIA JBOSS #####
	
	local caminho_jboss=$1
	local instancia=$2
	
	if [ -n "$caminho_jboss" ] && [ -n "$instancia" ] && [ -d  "${caminho_jboss}/server/${instancia}" ]; then
	
		unset $SCRIPT_INIT
		find /etc/init.d/ -type f -iname '*jboss*' > "$TEMP/scripts_jboss.list"
		
		#verifica todos os scripts de jboss encontrados em /etc/init.d até localizar o correto.
		while read script_jboss && [ -z "$SCRIPT_INIT" ]; do
		
			#verifica se o script aceita os argumentos 'start' e 'stop'
			if [ -n $(grep -E "^start\)" "$script_jboss") ] && [ -n $(grep -E "^stop" "$script_jboss") ]; then
		
				#retorna a primeira linha do tipo $JBOSS_HOME/server/$JBOSS_CONF
				local linha_script=$(grep -Ex "^[^#]+[\=].*[/\$].+/server/[^/]+/" "$script_jboss" | head -1 )
				
				if [ -n "$linha_script" ]; then
				
					local jboss_conf=$(echo "$linha_script" | sed -r "s|^.*/server/([^/]+).*$|\1|")
		
					#Se a instância estiver definida como uma variável no script, o loop a seguir tenta encontrar o seu valor em até 3 iterações.
					
					local var_jboss_conf=$( echo "$jboss_conf" | grep -Ex "^\\$.*$")
					local i='0'
					
					while [ -n "$var_jboss_conf" ] && [ "$i" -lt '3' ]; do														
					
						#remove o caractere '$', restando somente o nome da variável
						var_jboss_conf=$(echo "$var_jboss_conf" | sed -r "|^.||")
						
						#encontra a linha onde a variável foi setada e retorna a string após o sinal de "="										
						jboss_conf=$(grep -Ex "^$var_jboss_conf=" "$script_jboss" | head -1 | sed -r "s|^$var_jboss_conf=([\'\"])?([^ ]+)([\'\"])?.*$|\2|" )
		
						#verificar se houve substituição de parâmetros
						if [ $(echo "$jboss_conf" | grep -Ex "^\\$\{$var_jboss_conf[:=-]+([\'\"])?[A-Za-z0-9\-\_\.]+([\'\"])?\}.*$") ]; then
							jboss_conf=$(echo "$jboss_conf" | sed -r "s|^\\$\{$var_jboss_conf[\:\=\-\+]+([\'\"])?([\$A-Za-z0-9\-\_\.]+)([\'\"])?\}.*$|\2|")
						fi
						
						#atualiza condições para entrada no loop.
						var_jboss_conf=$( echo "$jboss_conf" | grep -Ex "^\\$.*$")
						i=(($i+1))
						
					done
				
					#verifica se o script encontrado corresponde à instância desejada.
					if [ -d "${caminho_jboss}/server/${jboss_conf}" ] && [ "$jboss_conf" == "$instancia"]; then
						SCRIPT_INIT=$script_jboss
					fi
					
				fi
				
			fi
			
		done < "$TEMP/scripts_jboss.list"
		
	else
		log "ERRO" "Parâmetros incorretos ou instância JBOSS não encontrada."
	fi
	
}

function end () {

	if [ -d "$TEMP" ]; then
		rm -Rf ${TEMP}/*
	fi

	if [ -d "$LOCK" ]; then
		rmdir $LOCK
	fi

	if [ "$EDIT_LOG" == "1" ]; then
		rm -f $GLOBAL_LOCK/deploy_log_edit
	fi
	
	exit "$1"
}

###### INICIALIZAÇÃO ######

ARQ_PROPS_GLOBAL='/opt/autodeploy-jboss/conf/global.conf'
ARQ_PROPS_LOCAL='/opt/autodeploy-jboss/conf/local.conf'
TEMP='/opt/autodeploy-jboss/temp'
LOGS='/opt/autodeploy-jboss/log'
LOG="$LOGS/deploy-$(date +%F).log"
GLOBAL_LOG='/mnt/deploy_log/deploy.log'
LOCK='/var/lock/autodeploy-jboss'
GLOBAL_LOCK='/var/lock/autodeploy'

trap "end 1; exit" SIGQUIT SIGINT SIGHUP SIGTERM

source "$ARQ_PROPS_GLOBAL" || exit 1
source "$ARQ_PROPS_LOCAL" || exit 1

# cria lock.

if [ -d "$LOCK" ]; then
	exit 0
else
	mkdir $LOCK
fi

# limpa diretório temporário.

if [ ! -z "$TEMP" ]; then
	mkdir -p $TEMP
	rm -f "$TEMP/*"
fi

# cria pasta de logs / expurga logs de deploy do mês anterior.

if [ ! -z "$LOGS" ]; then
	mkdir -p $LOGS
	find $LOGS -type f | grep -v $(date "+%Y-%m") | xargs rm -f
fi

######## VALIDAÇÃO #########

if [ -z "$CAMINHO_INSTANCIAS_JBOSS" ] || [ -z "$VERSAO_JBOSS" ] || [ -z "$ACESSO" ] || [ -z "$AMBIENTE" ]; then
	log "ERRO" "Parâmetros incorretos no arquivo '${ARQ_PROPS_LOCAL}'."
	end "1"
elif [ -z "$CAMINHO_PACOTES_REMOTO" ] || [ -z "$CAMINHO_LOGS_REMOTO" ]; then
	log "ERRO" "Parâmetros incorretos no arquivo '${ARQ_PROPS_GLOBAL}'."
	end "1"
fi

# verificar se o caminho para obtenção dos pacotes / gravação de logs está disponível.

ORIGEM_PACOTES=$( mount | grep -i "$CAMINHO_PACOTES_REMOTO" | sed -r "s|^${CAMINHO_PACOTES_REMOTO} on ([^ ]+) .*$|\1|" ) 
DESTINO_LOGS=$( mount | grep -i "$CAMINHO_LOGS_REMOTO" | sed -r "s|^${CAMINHO_LOGS_REMOTO} on ([^ ]+) .*$|\1|" ) 

if [ -z "$ORIGEM_PACOTES" ] || [ -z "$DESTINO_LOGS" ]; then
	log "ERRO" "Endereço para obtenção de pacotes / gravação de logs inacessível. Verificar arquivo $ARQ_PROPS_GLOBAL"
	end "1"
fi

ORIGEM="${ORIGEM_PACOTES}/${AMBIENTE}/${ACESSO}/JBOSS_${VERSAO_JBOSS}"
DESTINO="${DESTINO_LOGS}/${AMBIENTE}/${ACESSO}/JBOSS_${VERSAO_JBOSS}"

ORIGEM=$(find "$ORIGEM_PACOTES" -ipath "$ORIGEM")
DESTINO=$(find "$DESTINO_LOGS" -ipath "$DESTINO")

if [ $( echo "$ORIGEM" | wc -w ) -ne 1 ] || [ $( echo "$DESTINO" | wc -w ) -ne 1 ]; then
	log "ERRO" "O caminho para o diretório de pacotes / logs não foi encontrado ou possui espaços."
	end "1"
fi

log "INFO" "Verificando a consistência da estrutura de diretórios em ${CAMINHO_PACOTES_REMOTO}..."

# eliminar da estrutura de diretórios subjacente os arquivos e subpastas cujos nomes contenham espaços.

find ${ORIGEM}/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rfv
find ${DESTINO}/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rfv

# garantir integridade da estrutura de diretórios, eliminando subpastas inseridas incorretamente.

find ${ORIGEM}/* -type d | grep -Ei "^${ORIGEM}/[^/]+/[^/]+" | xargs -r -d "\n" rm -Rfv
find ${DESTINO}/* -type d | grep -Ei "^${DESTINO}/[^/]+/[^/]+" | xargs -r -d "\n" rm -Rfv

# eliminar arquivos em local incorreto ou com extensão diferente de .war / .log

find "$ORIGEM" -type f | grep -Eixv "^${ORIGEM}/[^/]+/[^/]+\.war$" | xargs -r -d "\n" rm -fv
find "$DESTINO" -type f | grep -Eixv "^${DESTINO}/[^/]+/[^/]+\.log$" | xargs -r -d "\n" rm -fv

######## DEPLOY #########

# Verificar se há arquivos para deploy.

log "INFO" "Procurando novos pacotes..."

find "$ORIGEM" -type f > $TEMP/arq.list

if [ $(cat $TEMP/arq.list | wc -l) -lt 1 ]; then
	log "INFO" "Não foram encontrados novos pacotes para deploy."
else
	# Caso haja arquivos, verificar se o nome do pacote corresponde ao diretório da aplicação.

	echo '' > "$TEMP/remove_incorretos.list"

	cat "$TEMP/arq.list" | while read l; do

		WAR=$( echo $l | sed -r "s|^${ORIGEM}/[^/]+/([^/]+)\.[Ww][Aa][Rr]$|\1|" )
		APP=$( echo $l | sed -r "s|^${ORIGEM}/([^/]+)/[^/]+\.[Ww][Aa][Rr]$|\1|" )
	
		if [ $(echo $WAR | grep -Ei "^$APP" | wc -l) -ne 1 ]; then
			echo $l >> "$TEMP/remove_incorretos.list"
		fi
	done
	
	if [ $(cat $TEMP/remove_incorretos.list | wc -l) -gt 0 ]; then
		log "WARN" "Removendo pacotes em diretórios incorretos..."
		cat "$TEMP/remove_incorretos.list" | xargs -r -d "\n" rm -fv
	fi

	# Caso haja pacotes, deve haver no máximo um pacote por diretório

	find "$ORIGEM" -type f > $TEMP/arq.list

	echo '' > $TEMP/remove_versoes.list

	cat $TEMP/arq.list | while read l; do

		WAR=$( echo $l | sed -r "s|^${ORIGEM}/[^/]+/([^/]+)\.[Ww][Aa][Rr]$|\1|" )
		DIR=$( echo $l | sed -r "s|^(${ORIGEM}/[^/]+)/[^/]+\.[Ww][Aa][Rr]$|\1|" )
	
		if [ $( find $DIR -type f | wc -l ) -ne 1 ]; then
			echo $l >> $TEMP/remove_versoes.list
		fi
	done

	if [ $(cat $TEMP/remove_versoes.list | wc -l) -gt 0 ]; then
		log "WARN" "Removendo pacotes com mais de uma versão..."
		cat $TEMP/remove_versoes.list | xargs -r -d "\n" rm -fv
	fi

	find "$ORIGEM" -type f > $TEMP/war.list

	if [ $(cat $TEMP/war.list | wc -l) -lt 1 ]; then
		log "INFO" "Não há novos pacotes para deploy."
	else
		log "INFO" "Verificação do diretório ${CAMINHO_PACOTES_REMOTO} concluída. Iniciando processo de deploy dos pacotes abaixo."
		cat $TEMP/war.list 
	
		cat $TEMP/war.list | while read PACOTE; do

			WAR=$(basename $PACOTE)
			REV=$(unzip -p $PACOTE META-INF/MANIFEST.MF | grep -i implementation-version | sed -r "s/^[^ ]+ ([^ ]+)$/\1/")
			APP=$(echo $PACOTE | sed -r "s|^${ORIGEM}/([^/]+)/[^/]+\.[Ww][Aa][Rr]$|\1|" )
			OLD=$(find $CAMINHO_INSTANCIAS_JBOSS -type f -regextype posix-extended -iregex "$CAMINHO_INSTANCIAS_JBOSS/[^/]+/deploy/$APP\.war")
	
			if [ $( echo $OLD | wc -l ) -ne 1 ] || [ -z $OLD ]; then
				log "ERRO" "Deploy abortado. Não foi encontrado pacote anterior. O deploy deverá ser feito manualmente."
				global_log "Deploy abortado. Pacote anterior não encontrado."
			else
				log "INFO" "O pacote $OLD será substituído".
		
				DIR_DEPLOY=$(echo $OLD | sed -r "s|^(${CAMINHO_INSTANCIAS_JBOSS}/[^/]+/[Dd][Ee][Pp][Ll][Oo][Yy])/[^/]+\.[Ww][Aa][Rr]$|\1|")
				INSTANCIA_JBOSS=$(echo $OLD | sed -r "s|^${CAMINHO_INSTANCIAS_JBOSS}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[Ww][Aa][Rr]$|\1|")
				DIR_TEMP="$CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS/tmp"
				DIR_TEMP=$(find $CAMINHO_INSTANCIAS_JBOSS -ipath $DIR_TEMP)
				DIR_WORK="$CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS/work"
				DIR_WORK=$(find $CAMINHO_INSTANCIAS_JBOSS -ipath $DIR_WORK)
				DIR_DATA="$CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS/data"
				DIR_DATA=$(find $CAMINHO_INSTANCIAS_JBOSS -ipath $DIR_DATA)
				
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

					if [ $(pgrep -f "jboss.*$INSTANCIA_JBOSS" | wc -l) -ne 0 ]; then
						log "ERRO" "Não foi possível parar a instância $INSTANCIA_JBOSS do JBOSS. Deploy abortado."
						global_log "Deploy abortado. Impossível parar a instância."	
					else
						rm -f $OLD 
						mv $PACOTE $DIR_DEPLOY/$APP.war 
						chown jboss:jboss $DIR_DEPLOY/$APP.war 
				
						if [ -d "$DIR_TEMP" ]; then
							rm -Rf $DIR_TEMP/* 
					        fi
						if [ -d "$DIR_WORK" ]; then
				        	       	rm -Rf $DIR_WORK/* 
					        fi
						if [ -d "$DIR_DATA" ]; then
					                rm -Rf $DIR_TEMP/* 
						fi
		 
						eval $INICIAR_INSTANCIA && wait				

						if [ $(pgrep -f "jboss.*$INSTANCIA_JBOSS" | wc -l) -eq 0 ]; then
					                log "ERRO" "O deploy do arquivo $PACOTE foi concluído, porém não foi possível reiniciar a instância do JBOSS."
							global_log "Deploy concluído. Erro ao iniciar a instância JBOSS."
						else
							log "INFO" "Deploy do arquivo $PACOTE concluído com sucesso!"
							global_log "Deploy do pacote $PACOTE concluído com sucesso."
						fi
					
					fi
				fi
			fi
		done
	fi
fi

######## LOGS #########

log "INFO" "Copiando logs de deploy e das instâncias JBOSS em ${CAMINHO_INSTANCIAS_JBOSS}..."
echo ''

find $DESTINO/* -type d | sed -r "s|^${DESTINO}/||g" > $TEMP/app.list

cat $TEMP/app.list | while read APP; do

	LOG_APP=$(find "${CAMINHO_INSTANCIAS_JBOSS}" -iwholename "${CAMINHO_INSTANCIAS_JBOSS}/${APP}/log/server.log" 2> /dev/null)
	CAMINHO_APP=$(find $CAMINHO_INSTANCIAS_JBOSS -type f -regextype posix-extended -iregex "$CAMINHO_INSTANCIAS_JBOSS/[^/]+/deploy/$APP\.war" 2> /dev/null)

	if [ $(echo $LOG_APP | wc -l) -eq 1 ]; then

		cp -f $LOG_APP "$DESTINO/$APP/server.log"
		cp -f $LOG "$DESTINO/$APP/deploy.log"

	elif [ $( echo $CAMINHO_APP | wc -l ) -eq 1 ]; then

		INSTANCIA_JBOSS=$(echo $CAMINHO_APP | sed -r "s|^${CAMINHO_INSTANCIAS_JBOSS}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[Ww][Aa][Rr]$|\1|")
		LOG_APP=$(find "${CAMINHO_INSTANCIAS_JBOSS}/${INSTANCIA_JBOSS}" -iwholename "${CAMINHO_INSTANCIAS_JBOSS}/${INSTANCIA_JBOSS}/log/server.log" 2> /dev/null)
	
		if [ $(echo $LOG_APP | wc -l) -eq 1 ]; then

			cp -f $LOG_APP "$DESTINO/$APP/server.log"
			cp -f $LOG "$DESTINO/$APP/deploy.log"

		else
			log "ERRO" "Não há logs da instância JBOSS correspondente à aplicação $APP."
		fi		
	else
		log "ERRO" "A aplicação $APP não foi encontrada."
	fi

done

end "0"
