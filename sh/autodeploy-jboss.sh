#!/bin/bash
#
# Script para automatização dos deploys e disponibilização de logs do ambiente JBOSS / Linux.
#

###### FUNÇÕES ######

function log () {

	touch $LOG
	echo -e "$(date +"%F %Hh%Mm%Ss") : $HOSTNAME : $1 : $2" >> $LOG

}

function end () {

	if [ -d "$TEMP" ]; then
		rm -Rf ${TEMP}/*
	fi

	if [ -d "$LOCK" ]; then
		rmdir $LOCK
	fi

	exit "$1"
}

###### INICIALIZAÇÃO ######

ARQ_PROPS_GLOBAL='/opt/autodeploy-jboss/global.conf'
ARQ_PROPS_LOCAL='/opt/autodeploy-jboss/local.conf'
TEMP='/opt/autodeploy-jboss/temp'
LOGS='/opt/autodeploy-jboss/log'
LOG="$LOGS/deploy-$(date +%F).log"
LOCK='/var/lock/autodeploy-jboss'

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

# cria diretório de logs / expurga logs de deploy do mês anterior.

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

find ${ORIGEM}/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rf >> $LOG
find ${DESTINO}/* | sed -r "s| |\\ |g" | grep ' ' | xargs -r -d "\n" rm -Rf >> $LOG

# garantir integridade da estrutura de diretórios, eliminando subpastas inseridas incorretamente.

find ${ORIGEM}/* -type d | grep -Ei "^${ORIGEM}/[^/]+/[^/]+" | xargs -r -d "\n" rm -Rf >> $LOG
find ${DESTINO}/* -type d | grep -Ei "^${DESTINO}/[^/]+/[^/]+" | xargs -r -d "\n" rm -Rf >> $LOG

# eliminar arquivos em local incorreto ou com extensão diferente de .war / .log

find "$ORIGEM" -type f | grep -Eixv "^${ORIGEM}/[^/]+/[^/]+\.war$" | xargs -r -d "\n" rm -f >> $LOG
find "$DESTINO" -type f | grep -Eixv "^${DESTINO}/[^/]+/[^/]+\.log$" | xargs -r -d "\n" rm -f >> $LOG

######## DEPLOY #########

# Verificar se há arquivos para deploy.

log "INFO" "Procurando novos pacotes..."

find "$ORIGEM" -type f > $TEMP/arq.list

if [ $(cat $TEMP/arq.list | wc -l) -lt 1 ]; then
	log "INFO" "Não foram encontrados novos pacotes para deploy."
else
	# Caso haja arquivos, verificar se o nome do pacote corresponde ao diretório da aplicação.

	echo '' > $TEMP/remove_incorretos.list

	cat $TEMP/arq.list | while read l; do

		WAR=$( echo $l | sed -r "s|^${ORIGEM}/[^/]+/([^/]+)\.[Ww][Aa][Rr]$|\1|" )
		APP=$( echo $l | sed -r "s|^${ORIGEM}/([^/]+)/[^/]+\.[Ww][Aa][Rr]$|\1|" )
	
		if [ $(echo $WAR | grep -Ei "^$APP" | wc -l) -ne 1 ]; then
			echo $l >> $TEMP/remove_incorretos.list
		fi
	done
	
	if [ $(cat $TEMP/remove_incorretos.list | wc -l) -gt 0 ]; then
		log "WARN" "Removendo pacotes em diretórios incorretos..."
		cat $TEMP/remove_incorretos.list | xargs -r -d "\n" rm -f >> $LOG
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
		cat $TEMP/remove_versoes.list | xargs -r -d "\n" rm -f >> $LOG
	fi

	find "$ORIGEM" -type f > $TEMP/war.list

	if [ $(cat $TEMP/war.list | wc -l) -lt 1 ]; then
		log "INFO" "Não há novos pacotes para deploy."
	else
		log "INFO" "Verificação do diretório ${CAMINHO_PACOTES_REMOTO} concluída. Iniciando processo de deploy dos pacotes abaixo."
		cat $TEMP/war.list >> $LOG
	
		cat $TEMP/war.list | while read PACOTE; do

			WAR=$( echo $PACOTE | sed -r "s|^${ORIGEM}/[^/]+/([^/]+\.[Ww][Aa][Rr])$|\1|" )
			APP=$( echo $PACOTE | sed -r "s|^${ORIGEM}/([^/]+)/[^/]+\.[Ww][Aa][Rr]$|\1|" )
			OLD=$(find $CAMINHO_INSTANCIAS_JBOSS -type f -regextype posix-extended -iregex "$CAMINHO_INSTANCIAS_JBOSS/[^/]+/deploy/$APP[_\-\.0-9]*\.war")
	
			if [ $( echo $OLD | wc -l ) -ne 1 ]; then
				log "ERRO" "Deploy abortado. Não foi encontrado pacote anterior. O deploy deverá ser feito manualmente."
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
				SCRIPT_INIT=$(grep -REil "[^#]*JBOSS[^#\=]*\=[^#]*$INSTANCIA_JBOSS.*$" /etc/init.d)

				if [ $(echo $SCRIPT_INIT | wc -l) -ne 1 ] || \
					[ $(grep -Ei "[^#a-z0-9]*start *\(\)" $SCRIPT_INIT | wc -l ) -ne 1 ] || \
					[ $(grep -Ei "[^#a-z0-9]*stop *\(\)" $SCRIPT_INIT | wc -l ) -ne 1 ]; then
						log "ERRO" "Não foi encontrado o script de inicialização da instância JBoss. O deploy deverá ser feito manualmente."
				else
					log "INFO" "Instância do JBOSS:     \t$INSTANCIA_JBOSS"
					log "INFO" "Diretório de deploy:    \t$DIR_DEPLOY"
					log "INFO" "Script de inicialização:\t$SCRIPT_INIT"
			
					PARAR_INSTANCIA="$SCRIPT_INIT stop"
					INICIAR_INSTANCIA="$SCRIPT_INIT start"
			
					eval $PARAR_INSTANCIA && wait

					if [ $(pgrep -f "jboss.*$INSTANCIA_JBOSS" | wc -l) -ne 0 ]; then
						log "ERRO" "Não foi possível parar a instância $INSTANCIA_JBOSS do JBOSS. Deploy abortado."
					else
						rm -f $OLD 2>> $LOG
						mv $PACOTE $DIR_DEPLOY 2>> $LOG
						chown jboss:jboss $DIR_DEPLOY/$WAR 2>> $LOG
				
						if [ -d "$DIR_TEMP" ]; then
							rm -Rf $DIR_TEMP/* 2>> $LOG
					        fi
						if [ -d "$DIR_WORK" ]; then
				        	       	rm -Rf $DIR_WORK/* 2>> $LOG
					        fi
						if [ -d "$DIR_DATA" ]; then
					                rm -Rf $DIR_TEMP/* 2>> $LOG
						fi
		 
						eval $INICIAR_INSTANCIA && wait				

						if [ $(pgrep -f "jboss.*$INSTANCIA_JBOSS" | wc -l) -eq 0 ]; then
					                log "ERRO" "O deploy do arquivo $PACOTE foi concluído, porém não foi possível reiniciar a instância do JBOSS."
						else
							log "INFO" "Deploy do arquivo $PACOTE concluído com sucesso!"
						fi
					
					fi
				fi
			fi
		done
	fi
fi

######## LOGS #########

log "INFO" "Copiando logs de deploy e das instâncias JBOSS em ${CAMINHO_INSTANCIAS_JBOSS}..."

find $CAMINHO_INSTANCIAS_JBOSS -type f -iname 'server.log' > $TEMP/log_aplicacoes.list
find $DESTINO/* -type d | sed -r 's|$DESTINO/||g' >> $TEMP/destinos.list

cat $TEMP/log_aplicacoes.list | while read LOG_APP; do
	INSTANCIA_JBOSS=$( echo $LOG_APP | sed -r "s|^${$CAMINHO_INSTANCIAS_JBOSS}/([^/]+)/[Ll][Oo][Gg]/[Ss][Ee][Rr][Vv][Ee][Rr]\.[Ll][Oo][Gg]$|\1|" )
	find $CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS -type f -regextype posix-extended -iregex "$CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS/deploy/[a-z]+[\_\-]?[a-z]+[_\-\.0-9]*\.war" > $TEMP/aplicacoes.list

	cat $TEMP/aplicacoes.list | while read APLICACAO; do
		APP=$( echo $APLICACAO | sed -r "s|^$CAMINHO_INSTANCIAS_JBOSS/$INSTANCIA_JBOSS/[Dd][Ed][Pp][Ll][Oo][Yy]/([a-z]+[\_\-]?[a-z]+)[_\-\.0-9]*\.[Ww][Aa][Rr]$|\1|" )
		
		cat $TEMP/destinos.list | while read DIR_APP; do
			
			if [ "$APP" == "$DIR_APP" ]; then
				cp -f $LOG_APP $DESTINO/$DIR_APP
				cp -f $LOG $DESTINO/$DIR_APP
			fi			

		done
	done
done

log "INFO" "FIM."

end "0"
