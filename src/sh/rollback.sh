#!/bin/bash

estado="validacao"
pid=$$
data="$(date +%Y%m%d%H%M%S)"

##### Execução somente como usuário root ######

if [ ! "$USER" == 'root' ]; then
	echo "Requer usuário root."
	exit
fi

#### UTILIZAÇÃO: git_deploy.sh <aplicação> <revisão> <chamado> (modo) ############

if [ "$#" -ne 2 ]; then											#o script requer exatamente 3 parâmetros.
	echo "O script requer 2 parâmetros: <aplicação> <chamado>"
	exit
fi

app=$1
chamado=$2

#### Inicialização #####

clear

deploy_dir="/opt/git_deploy"										#diretório de instalação.
source $deploy_dir/constantes.txt || exit								#carrega o arquivo de constantes.

temp_dir="$temp/$pid"

if [ -z $(echo $temp_dir | grep -E "^/opt/[^/]+") ] \
	|| [ -z $(echo $chamados_dir | grep -E "^/opt/[^/]+|^/mnt/[^/]+") ] \
	|| [ -z $(echo $repo_dir | grep -E "^/opt/[^/]+|^/mnt/[^/]+")  ] \
	|| [ -z $(echo $lock_dir | grep -E "^/var/[^/]+") ];
then
    echo 'Favor preencher corretamente o arquivo $deploy_dir/constantes.txt e tentar novamente.'
    exit
fi

if [ ! -d "$deploy_dir" ] \
	|| [ ! -d "$temp" ] \
	|| [ ! -d "$chamados_dir/$app" ] \
	|| [ ! -d "$repo_dir" ] \
	|| [ ! -d "$lock_dir" ] \
	|| [ ! -f "$parametros_git" ] \
	|| [ ! -f "$historico" ] \
	|| [ ! -f "$credenciais" ] ; then									
    echo 'Impossível realizar rollback: não há deploys anteriores.'
    exit

fi

#### Funções ##########

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
		fim
	fi
}

function lock () {											#argumentos: nome_trava, mensagem_erro

	if [ -d $temp_dir ] && [ -d $lock_dir ]; then
	
		if [ ! -f $temp_dir/locks ]; then
			touch $temp_dir/locks
		fi
	
		if [ -f $lock_dir/$1 ]; then
			echo -e "\n$2" && fim
		else
			touch $lock_dir/$1 && echo "$lock_dir/$1" >> $temp_dir/locks
		fi
	else
		fim
	fi

}

function clean_locks () {

	if [ -d $lock_dir ] && [ -f "$temp_dir/locks" ]; then
		cat $temp_dir/locks | xargs --no-run-if-empty rm -f					#remove locks
	fi

}


function fim () {
	
	wait

	clean_locks
	clean_temp

	exit 0

}

trap '' SIGQUIT SIGTERM SIGINT SIGTERM SIGHUP						# o rollback não deve ser interrompido.

clean_temp && mkdir -p $temp_dir

#### Validação do input do usuário ###### 

echo "Iniciando rollback.."

while [ -z $(echo $app | grep -Ex "[A-Za-z]+_?[0-9A-Za-z]+") ]; do
	echo -e "\nErro. Informe o nome do sistema corretamente:"
	read app
done

while [ -z $(echo $chamado | grep -Ex "[0-9]+/[0-9]{4}") ]; do						#chamado: n(nnn ...)/aaaa
	echo -e "\nErro. Informe o chamado corretamente:"
	read chamado
done

app=$(echo $app | sed -r 's/(^.*$)/\L\1/')								#apenas letras minúsculas.
chamado="$(echo $chamado | sed -r 's|/|\.|')"								#chamados no formato código.ano						

find "$chamados_dir/$app" -type f -iname "rollback_*.txt" > $temp_dir/nomescript

if [ $(cat "$temp_dir/nomescript" | wc -l) -eq "1" ]; then
	rollback=$(cat "$temp_dir/nomescript")
 	nomerollback=$(echo $dir_destino | sed -r "s|/|_|g")
else
	echo -e "\nO backup não está disponível. Rollback abortado."
	fim
fi

#### Verifica deploys simultâneos e cria lockfiles, conforme necessário ########

lock $nomerollback "O rollback já foi iniciado por outro usuário."
lock $chamado "Rollback abortado: há um deploy do chamado $chamado em curso."
lock $app "Rollback abortado: há um deploy da aplicação $app em curso." 

if [ $(grep -Ei "^$app " $parametros_git | wc -l) -ne "1" ]; then					#caso não haja registro referente ao sistema ou haja entradas duplicadas.
	echo -e "\nNão foram encontrados os parâmetros da aplicação $app."
	fim
else													#caso a entrada correspondente ao sistema já esteja preenchida, os parâmetros são obtidos do arquivo $deploy_dir/parametros.txt
	dir_destino=$(grep -Ei "^$app " $parametros_git | cut -d ' ' -f4)
	nomedestino=$(echo $dir_destino | sed -r "s|/|_|g")
fi

lock $nomedestino "Rollback abortado: há um deploy utilizando o diretório $dir_destino."

atividade_dir="$chamados_dir/$app/$chamado"								#Diretório onde serão armazenados os logs do atendimento.

if [ -d "${atividade_dir}_PENDENTE" ]; then
	rm -f ${atividade_dir}_PENDENTE/*
	rmdir ${atividade_dir}_PENDENTE
fi

mkdir -p $atividade_dir

echo -e "\nSistema:\t$app"
echo -e "Destino:\t$dir_destino"

echo $estado > $atividade_dir/progresso.txt							

estado="fim_$estado" && echo $estado >> $atividade_dir/progresso.txt

### ROLBACK ###

estado="rollback" && echo $estado >> $atividade_dir/progresso.txt

datarollback=$(echo $rollback | sed -r "s|/rollback_(.*)\.txt|\1|")
destino="/mnt/${app}_${datarollback}"

echo -e "\nAcessando o diretório de deploy..."

mkdir $destino || fim

mount.cifs $dir_destino $destino -o credentials=$credenciais || fim 				#montagem do compartilhamento de destino (requer pacote cifs-utils)

cat $rollback | xargs --no-run-if-empty -d "\n" -L 1 sh -c
		
wait

rm -Rf $chamados_dir/$app/ROLLBACK_*
rm -f $chamados_dir/$app/rollback_*

echo "fim_$estado" >> $atividade_dir/progresso.txt
echo -e "Rollback finalizado."	
		
##### LOG #####
	
horario_log=$(echo $data | sed -r "s|^(....)(..)(..)(..)(..)(..)$|\3/\2/\1      \4h\5m\6s       |")
		
tamanho_app=$(echo -n $app | wc -m)
app_log=$(echo '                ' | sed -r "s|^ {$tamanho_app}|$app|")

rev_log='NA              '

tamanho_chamado=$(echo -n $chamado | wc -m) 
chamado_log=$(echo '                ' | sed -r "s|^ {$tamanho_chamado}|$chamado|")

obs_log=$(echo $datarollback | sed -r "s|^(....)(..)(..)(..)(..)(..)$|Rollback correspondente a \3/\2/\1, \4h\5m\6s|")

echo -e "$horario_log$app_log$rev_log$chamado_log$obs_log" >> $historico

cp $historico $chamados_dir

tamanho_horario=$(echo -n "$horario_log" | wc -m) 
grep -Ei "^(.){$tamanho_horario}$app" $historico > $atividade_dir/historico_deploy_$app.txt

cp $atividade_dir/historico_deploy_$app.txt $chamados_dir/$app

echo "rollback_concluido" >> $atividade_dir/progresso.txt
echo -e "\nRollback concluído."

fim
