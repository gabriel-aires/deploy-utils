#!/bin/bash
#
# Script para automatização dos deploys e disponibilização de logs do ambiente JBOSS / Linux.
#

###### FUNÇÕES ######

function log () {

	echo -e "$(date +"%F %Hh%Mm%Ss") : $HOSTNAME : $1 : $2" 

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

ARQ_PROPS_GLOBAL='/opt/autodeploy-jboss/conf/global.conf'
ARQ_PROPS_LOCAL='/opt/autodeploy-jboss/conf/local.conf'
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
		cat $TEMP/remove_incorretos.list | xargs -r -d "\n" rm -fv
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
						rm -f $OLD 
						mv $PACOTE $DIR_DEPLOY 
						chown jboss:jboss $DIR_DEPLOY/$WAR 
				
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

find $DESTINO/* -type d | sed -r 's|$DESTINO/||g' > $TEMP/app.list

cat $TEMP/app.list | while read APP; do

	LOG_APP=$(find "${CAMINHO_INSTANCIAS_JBOSS}/${APP}" -iwholename "${CAMINHO_INSTANCIAS_JBOSS}/${APP}/log/server.log") 2> /dev/null
	CAMINHO_APP=$(find $CAMINHO_INSTANCIAS_JBOSS -type f -regextype posix-extended -iregex "$CAMINHO_INSTANCIAS_JBOSS/[^/]+/deploy/$APP[_\-\.0-9]*\.war") 2> /dev/null

	if [ $(echo $LOG_APP | wc -l) -eq 1 ]; then

		cp -f $LOG_APP "$DESTINO/$APP/server.log"
		cp -f $LOG "$DESTINO/$APP/deploy.log"

	elif [ $( echo $CAMINHO_APP | wc -l ) -eq 1 ]; then

		INSTANCIA_JBOSS=$(echo $CAMINHO_APP | sed -r "s|^${CAMINHO_INSTANCIAS_JBOSS}/([^/]+)/[Dd][Ee][Pp][Ll][Oo][Yy]/[^/]+\.[Ww][Aa][Rr]$|\1|")
		LOG_APP=$(find "${CAMINHO_INSTANCIAS_JBOSS}/${INSTANCIA_JBOSS}" -iwholename "${CAMINHO_INSTANCIAS_JBOSS}/${INSTANCIA_JBOSS}/log/server.log") 2> /dev/null
	
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