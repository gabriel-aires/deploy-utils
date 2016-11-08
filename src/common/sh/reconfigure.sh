#!/bin/bash
# Executar este arquivo para reconfigurar agentes/servidor

src_dir="$(dirname $(dirname $(dirname $(readlink -f $0))))"

#backup conf
test -f $src_dir/common/conf/include.conf && cp -f $src_dir/common/conf/include.conf $src_dir/common/conf/include.bak
test -f $src_dir/agents/conf/global.conf && cp -f $src_dir/agents/conf/global.conf $src_dir/agents/conf/global.bak
test -f $src_dir/server/conf/global.conf && cp -f $src_dir/server/conf/global.conf $src_dir/server/conf/global.bak
test -f $src_dir/server/conf/user.conf && cp -f $src_dir/server/conf/user.conf $src_dir/server/conf/user.bak

#reset conf
cp -f $src_dir/common/conf/default_include.conf $src_dir/common/conf/include.conf
cp -f $src_dir/agents/conf/default_global.conf $src_dir/agents/conf/global.conf
cp -f $src_dir/server/conf/default_global.conf $src_dir/server/conf/global.conf
cp -f $src_dir/server/conf/default_user.conf $src_dir/server/conf/user.conf
