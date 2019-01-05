#!/bin/bash

cat  << EOF
daemon=0
server=1
listen=1
rpcworkqueue=32
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=$RPCALLOWIP
rpcport=2300
port=4334
rest=1
debug=rpc
printtoconsole=0
txindex=1
shrinkdebugfile=1
torenabled=$TORENABLED
addnode=goldmine.actinium.org
addnode=explorer.actinium.org
addnode=seed1.actinium.org
addnode=seed2.actinium.org
addnode=seed3.actinium.org
addnode=seed4.actinium.org
addnode=seed5.actinium.org
EOF