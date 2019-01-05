#!/bin/bash

cat  << EOF
alias=ACM-DOCKER-NODE
rgb=772200
network=actinium
bitcoin-cli=Actinium-cli
bitcoin-rpcuser=$RPCUSER
bitcoin-rpcpassword=$RPCPASSWORD
bitcoin-rpcport=2300
bitcoin-rpcconnect=127.0.0.1
log-prefix=acm-lightning
log-level=debug
log-file=/data/lightning/lightning.log
lightning-dir=/data/lightning
daemon
EOF