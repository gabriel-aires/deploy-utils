#!/bin/bash

temp_dir=$1

mkdir -p $temp_dir;

grep -E "/mnt/destino_.*" /proc/mounts > $temp_dir/pontos_de_montagem.txt			#os pontos de montagem são obtidos do arquivo /proc/mounts
sed -i -r 's|^.*(/mnt/[^ ]+).*$|\1|' $temp_dir/pontos_de_montagem.txt

desmontar="$(cat $temp_dir/pontos_de_montagem.txt | wc -l)"					#Se > 0, há necessidade de desmontar pontos de montagem.

if [ $desmontar -gt "0" ]; then
	cat $temp_dir/pontos_de_montagem.txt | xargs sudo umount				#desmonta cada um dos pontos de montagem identificados em $temp_dir/pontos_de_montagem.txt.
fi

rm -Rf /mnt/destino_*										#já desmontados, os pontos de montagem temporários podem ser apagados.
rm -f $temp_dir/destino_*									#remoção de link simbólico (a opção -R não foi utilizada para que o link simbólico não seja seguido).
rm -Rf $temp_dir/*;										#apaga outros arquivos e subdiretórios em $temp_dir, caso existam.
	

