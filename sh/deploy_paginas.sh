#!/bin/bash

estado="validacao"
pid=$$
data="$(date +%Y%m%d%H%M%S)"

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
	echo "Requer usuário root."
	exit
fi

#### UTILIZAÇÃO: deloy_paginas.sh <aplicação> <revisão> <chamado> (modo) ############

if [ "$#" -lt 3 ]; then											#o script requer exatamente 3 parâmetros.
	echo "O script requer no mínimo 3 parâmetros: <aplicação> <revisão> <chamado>"
	exit
fi

app=$1
rev=$2
chamado=$3
modo=$4													# p - preservar arquivos no destino | d - deletar arquivos no destino.

#### Inicialização #####

clear

deploy_dir="/opt/autodeploy-paginas"										#diretório de instalação.
source $deploy_dir/conf/global.conf || exit								#carrega o arquivo de constantes.

temp_dir="$temp/$pid"

if [ -z $(echo $temp_dir | grep -E "^/opt/[^/]+") ] \
	|| [ -z $(echo $historico_dir | grep -E "^/opt/[^/]+|^/mnt/[^/]+") ] \
	|| [ -z $(echo $repo_dir | grep -E "^/opt/[^/]+|^/mnt/[^/]+")  ] \
	|| [ -z $(echo $lock_dir | grep -E "^/var/[^/]+") ];
then
    echo 'Favor preencher corretamente o arquivo $deploy_dir/constantes.txt e tentar novamente.'
    exit
fi

mkdir -p $deploy_dir $temp $historico_dir $repo_dir $lock_dir						#cria os diretórios necessários, caso não existam.

if [ ! -e "$parametros_app" ]; then									#cria arquivo de parâmetros, caso não exista.
	touch $parametros_app
fi

if [ ! -e "$historico" ]; then										#cria arquivo de histórico, caso não exista.
	touch $historico	
fi

#### Funções ##########

function checkout () {											# o comando cd precisa estar encapsulado para funcionar adequadamente num script, por isso foi criada a função.

	if [ ! -d "$repo_dir/$nomerepo/.git" ]; then
		echo " "
		git clone --progress "$repo" "$repo_dir/$nomerepo" || etapa				#clona o repositório, caso ainda não tenha sido feito.
	fi

	echo -e "\nObtendo a revisão ${rev}..."

	cd "$repo_dir/$nomerepo"

	( git fetch --all --force --quiet && git checkout --force --quiet $rev ) || etapa

	cd - &> /dev/null 

}

function clean_temp () {										#cria pasta temporária, remove arquivos, pontos de montagem e links simbólicos temporários
	
	if [ ! -z $temp_dir ]; then

		mkdir -p $temp_dir
	
		if [ ! -z "$destino" ]; then
			grep -E "$destino" /proc/mounts > $temp_dir/pontos_de_montagem.txt		#os pontos de montagem são obtidos do arquivo /proc/mounts
			sed -i -r 's|^.*(/mnt/[^ ]+).*$|\1|' $temp_dir/pontos_de_montagem.txt
			cat $temp_dir/pontos_de_montagem.txt | xargs --no-run-if-empty umount		#desmonta cada um dos pontos de montagem identificados em $temp_dir/pontos_de_montagem.txt.
			cat $temp_dir/pontos_de_montagem.txt | xargs --no-run-if-empty rmdir		#já desmontados, os pontos de montagem temporários podem ser apagados.
		fi

		rm -f $temp_dir/*									
		rmdir $temp_dir
	else
		etapa
	fi
}

function lock () {											#argumentos: nome_trava, mensagem_erro

	if [ -d $temp_dir ] && [ -d $lock_dir ]; then
	
		if [ ! -f $temp_dir/locks ]; then
			touch $temp_dir/locks
		fi
	
		if [ -f $lock_dir/$1 ]; then
			echo -e "\n$2" && etapa
		else
			touch $lock_dir/$1 && echo "$lock_dir/$1" >> $temp_dir/locks
		fi
	else
		etapa
	fi

}

function clean_locks () {

	if [ -d $lock_dir ] && [ -f "$temp_dir/locks" ]; then
		cat $temp_dir/locks | xargs --no-run-if-empty rm -f					#remove locks
	fi

}

function etapa () {
	
	wait
	
	if [ "$estado" == 'fim_validacao' ] || [ "$estado" == 'leitura' ] || [ "$estado" == 'fim_leitura' ]; then
	
		echo "deploy_abortado" >> $atividade_dir/progresso.txt
		echo -e "\nDeploy abortado."
		mv "$atividade_dir" "${atividade_dir}_PENDENTE"

	elif [ "$estado" == 'backup' ] || [ "$estado" == 'fim_backup' ]; then

		rm -Rf $historico_dir/$app/ROLLBACK_*
		rm -f $historico_dir/$app/rollback_*
		echo "deploy_abortado" >> $atividade_dir/progresso.txt
		echo -e "\nDeploy abortado."
		mv "$atividade_dir" "${atividade_dir}_PENDENTE"

	elif [ "$estado" == 'escrita' ]; then

		echo -e "\nDeploy interrompido durante a etapa de escrita. Revertendo alterações..."
		echo "rollback" >> $atividade_dir/progresso.txt
		
		rsync -rc --inplace $bak_dir/ $destino/ 
		
		rm -Rf $historico_dir/$app/ROLLBACK_*
		
		echo "fim_rollback" >> $atividade_dir/progresso.txt
		echo "deploy_abortado" >> $atividade_dir/progresso.txt
		echo -e "Rollback finalizado."	
		mv "$atividade_dir" "${atividade_dir}_PENDENTE"

	elif [ "$estado" == 'fim_escrita' ]; then
		
		##### LOG DE DEPLOY #####
	
		horario_log=$(echo $data | sed -r "s|^(....)(..)(..)(..)(..)(..)$|\3/\2/\1      \4h\5m\6s       |")
		
		tamanho_app=$(echo -n $app | wc -m)
		app_log=$(echo '                ' | sed -r "s|^ {$tamanho_app}|$app|")

		rev_log=$(echo $rev | sed -r "s|^(.........).*$|\1|")
		tamanho_rev=$(echo -n $rev_log | wc -m)
	 	rev_log=$(echo '                ' | sed -r "s|^ {$tamanho_rev}|$rev_log|")

		tamanho_chamado=$(echo -n $chamado | wc -m) 
		chamado_log=$(echo '                ' | sed -r "s|^ {$tamanho_chamado}|$chamado|")
		
		if [ "$modo" == 'p' ]; then
			obs_log='Arquivos e diretórios obsoletos preservados.'
		else
			obs_log='Arquivos e diretórios obsoletos deletados.'
		fi
		
		echo -e "$horario_log$app_log$rev_log$chamado_log$obs_log" >> $historico

		cp $historico $historico_dir

		tamanho_horario=$(echo -n "$horario_log" | wc -m) 
		grep -Ei "^(.){$tamanho_horario}$app" $historico > $atividade_dir/historico_deploy_$app.txt
		
		cp $atividade_dir/historico_deploy_$app.txt $historico_dir/$app
		
		echo "deploy_concluido" >> $atividade_dir/progresso.txt
		echo -e "\nDeploy concluído."
	fi

	clean_locks
	clean_temp

	wait &&	exit 0
}

trap "etapa; exit" SIGQUIT SIGTERM SIGINT SIGTERM SIGHUP						#a função será chamada quando o script for finalizado ou interrompido.

clean_temp && mkdir -p $temp_dir

#### Validação do input do usuário ###### 

echo "Iniciando processo de deploy..."

while [ -z $(echo $app | grep -Ex "[A-Za-z]+_?[0-9A-Za-z]+") ]; do
	echo -e "\nErro. Informe o nome do sistema corretamente:"
	read app
done

while [ -z $(echo $rev | grep -Ex "^([0-9a-f]){9}[0-9a-f]*$|^v[0-9]+\.[0-9]+(\.[0-9]+)?$") ]; do	#a revisão é uma string hexadecimal de 9 ou mais caracteres ou uma tag do tipo v1.2.3
	echo -e "\nErro. Informe a revisão corretamente:"
	read rev
done

while [ -z $(echo $chamado | grep -Ex "[0-9]+/[0-9]{4}") ]; do						#chamado: n(nnn ...)/aaaa
	echo -e "\nErro. Informe o chamado corretamente:"
	read chamado
done

while [ -z $(echo $modo | grep -Ex "[pd]") ]; do
	if [ -z "$modo" ]; then
		modo=$modo_padrao
	else
		echo -e "\nErro. Escolha o modo de execução: [p, d]"
		read modo
	fi
done

app=$(echo $app | sed -r 's/(^.*$)/\L\1/')								#apenas letras minúsculas.
chamado="$(echo $chamado | sed -r 's|/|\.|')"								#chamados no formato código.ano						

#### Verifica deploys simultâneos e cria lockfiles, conforme necessário ########

lock $chamado "Deploy abortado: há outro deploy do chamado $chamado em curso."
lock $app "Deploy abortado: há outro deploy da aplicação $app em curso." 
lock $rev "Deploy abortado: há outro deploy da revisão $rev em curso."

if [ $(grep -Ei "^$app " $parametros_app | wc -l) -ne "1" ]; then					#caso não haja registro referente ao sistema ou haja entradas duplicadas.
	
	echo -e "\nFavor informar abaixo os parâmetros da aplicação $app."

	lock "parametros" "Erro: o arquivo $parametros_app está bloqueado para edição. Favor tentar novamente."

	if [ ! -z $(grep -Ei "^$lock_dir/parametros$" $temp_dir/locks) ]; then

		sed -i "/^$app .*$/d" $parametros_app									 

		echo -e "\nInforme o repositorio a ser utilizado:"
		read repo
		
		while [ -z $(echo $repo | grep -Ex "^git@git.anatel.gov.br:.+/.+\.git$|^http://(.+@)?git.anatel.gov.br.*/.+\.git$") ]; do	#Expressão regular para validação do caminho para o repositóio (SSH ou HTTP).
			echo -e "\nErro. Informe um caminho válido para o repositório GIT:"
			read -r repo
		done	
	
		echo -e "\nInforme o caminho para a raiz da aplicação:"
		read -r raiz											#utilizar a opção -r para permitir a leitura de contrabarras.
		raiz="$(echo $raiz | sed -r 's|\\|/|g')"							#troca \ por /, se necessário.
		
		while [ -z $(echo $raiz | grep -Ex "^/?[^/ \\]*(/[^/ \\]+)*/?$") ]; do				#Expressão regular para validação do caminho para a raiz da aplicação. ex: (/)aaa/bbbb/*(/)
			echo -e "\nErro. Informe um caminho válido para a raiz da aplicação:"
			read -r raiz
			raiz="$(echo $raiz | sed -r 's|\\|/|g')"
		done												
	
		echo -e "\nInforme o diretório de destino:"
		read -r dir_destino										#utilizar a opção -r para permitir a leitura de contrabarras.
		dir_destino="$(echo $dir_destino | sed -r 's|\\|/|g')"						#troca \ por /, se necessário.
		
		while [ -z $(echo $dir_destino | grep -Ex "^/(/[^/ \\]+)+/?$") ]; do				#Expressão regular para validação de string de compartilhamento CIFS. ex: \\aaa\bb\*(\)
			echo -e "\nErro. Informe um caminho válido para o diretório de destino:"
			read -r dir_destino
			dir_destino="$(echo $dir_destino | sed -r 's|\\|/|g')"
		done

		echo -e "\nInforme o sistema operacional:"
		read -r os                          										

		while [ -z $(echo $os | grep -Ex "^linux$|^windows$") ]; do				
			echo -e "\nErro. Informe um nome válido para o sistema operacional (windows/linux):"
			read -r os
		done
	
		raiz="$(echo $raiz | sed -r 's|^/||' | sed -r 's|/$||')"					#remove / no início ou fim do caminho.
		dir_destino="$(echo $dir_destino | sed -r 's|/$||')"						#remove / no fim do caminho.
	
		echo "$app $repo $raiz $dir_destino $os" >> $parametros_app
	
		rm -f $lock_dir/parametros
	else
		etapa
	fi  
else													#caso a entrada correspondente ao sistema já esteja preenchida, os parâmetros são obtidos do arquivo $deploy_dir/parametros.txt
	repo=$(grep -Ei "^$app " $parametros_app | cut -d ' ' -f2)
	raiz=$(grep -Ei "^$app " $parametros_app | cut -d ' ' -f3)
	dir_destino=$(grep -Ei "^$app " $parametros_app | cut -d ' ' -f4)
	os=$(grep -Ei "^$app " $parametros_app | cut -d ' ' -f5)	
fi

nomerepo=$(echo $repo | sed -r "s|^.*/([^/]+)\.git$|\1|")
nomedestino=$(echo $dir_destino | sed -r "s|/|_|g")

lock "${nomerepo}.git" "Deploy abortado: há outro deploy utilizando o repositório $repo."
lock $nomedestino "Deploy abortado: há outro deploy utilizando o diretório $dir_destino."

atividade_dir="$historico_dir/$app/$chamado"								#Diretório onde serão armazenados os logs do atendimento.

if [ -d "${atividade_dir}_PENDENTE" ]; then
	rm -f ${atividade_dir}_PENDENTE/*
	rmdir ${atividade_dir}_PENDENTE
fi

mkdir -p $atividade_dir

echo -e "\nSistema:\t$app"
echo -e "Repositório:\t$repo"
echo -e "Caminho:\t$raiz"
echo -e "Destino:\t$dir_destino"

echo $estado > $atividade_dir/progresso.txt							

estado="fim_$estado" && echo $estado >> $atividade_dir/progresso.txt

### início da leitura ###

estado="leitura" && echo $estado >> $atividade_dir/progresso.txt

##### GIT #########	

checkout												#ver checkout(): (git clone), cd <repositorio> , git fetch, git checkout...

origem="$repo_dir/$nomerepo/$raiz"

if [ ! -d "$origem" ]; then										
	origem="$repo_dir/$raiz"									#é comum que o usuário informe a pasta do sistema (nomerepo) como parte da raiz.
fi

if [ ! -d "$origem" ]; then										
	echo -e "\nErro: não foi possível encontrar o caminho $origem.\nVerifique a revisão informada ou corrija o arquivo $parametros_app."
	etapa
fi

##### CRIA PONTO DE MONTAGEM TEMPORÁRIO E DIRETÓRIO DO CHAMADO #####

echo -e "\nAcessando o diretório de deploy..."

destino="/mnt/${app}_${data}"

mkdir $destino || etapa

if [ $os == 'windows' ]; then
    mount.cifs $dir_destino $destino -o credentials=$credenciais || etapa 				#montagem do compartilhamento de destino (requer pacote cifs-utils)
else
    mount.cifs $dir_destino $destino -o credentials=$credenciais,sec=krb5 || etapa 		#montagem do compartilhamento de destino (requer módulo anatel_ad, provisionado pelo puppet)
fi

##### DIFF ARQUIVOS #####

if [ $modo = 'p' ]; then
	rsync -rnic --inplace $origem/ $destino/ > $atividade_dir/modificacoes.txt || etapa
else
	rsync -rnic --delete --inplace $origem/ $destino/ > $atividade_dir/modificacoes.txt || etapa
fi

##### RESUMO DAS MUDANÇAS ######

adicionados="$(grep -E "^>f\+" $atividade_dir/modificacoes.txt | wc -l)"
excluidos="$(grep -E "^\*deleting .*[^/]$" $atividade_dir/modificacoes.txt | wc -l)"
modificados="$(grep -E "^>f[^\+]" $atividade_dir/modificacoes.txt | wc -l)"
dir_criado="$(grep -E "^cd\+" $atividade_dir/modificacoes.txt | wc -l)"
dir_removido="$(grep -E "^\*deleting .*/$" $atividade_dir/modificacoes.txt | wc -l)"

echo -e "\nLog das modificacoes gravado no arquivo modificacoes.txt\n" > $atividade_dir/resumo.txt
echo -e "Arquivos adicionados:\t$adicionados " >> $atividade_dir/resumo.txt
echo -e "Arquivos excluidos:\t$excluidos" >> $atividade_dir/resumo.txt
echo -e "Arquivos modificados:\t$modificados" >> $atividade_dir/resumo.txt
echo -e "Diretórios criados:\t$dir_criado" >> $atividade_dir/resumo.txt
echo -e "Diretórios removidos:\t$dir_removido" >> $atividade_dir/resumo.txt

cat $atividade_dir/resumo.txt

estado="fim_$estado" && echo $estado >> $atividade_dir/progresso.txt

###### ESCRITA DAS MUDANÇAS EM DISCO ######

echo -e "\nGravar mudanças em disco? (s/n)"
read ans

if [ "$ans" == 's' ] || [ "$ans" == 'S' ]; then

	#### preparação do script de rollback ####

	estado="backup" && echo $estado >> $atividade_dir/progresso.txt
	echo -e "\nCriando backup"
		
	rm -Rf $historico_dir/$app/ROLLBACK_*

	bak_dir="$historico_dir/$app/ROLLBACK_$data"

	mkdir -p $bak_dir

	rsync -rc --inplace $destino/ $bak_dir/ || etapa

	estado="fim_$estado" && echo $estado >> $atividade_dir/progresso.txt

	#### gravação das alterações em disco ####
		
	estado="escrita" && echo $estado >> $atividade_dir/progresso.txt
	echo -e "\nEscrevendo alterações no diretório de destino..."	

	if [ $modo = 'p' ]; then
		rsync -rc --inplace $origem/ $destino/ || etapa
	else
		rsync -rc --delete --inplace $origem/ $destino/ || etapa
	fi

	estado="fim_$estado" && echo $estado >> $atividade_dir/progresso.txt
	
fi

etapa
