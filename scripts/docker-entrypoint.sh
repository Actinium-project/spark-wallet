#!/bin/bash
set -eo pipefail
trap 'jobs -p | xargs -r kill' SIGTERM

export PATH=$PATH:/opt/bin/

gen_banner.sh

: ${NETWORK:=mainnet}
: ${LIGHTNINGD_OPT:=--log-level=debug}
: ${BITCOIND_OPT:=-debug=rpc --printtoconsole=0}

[[ "$NETWORK" == "mainnet" ]] && NETWORK=actinium

if [ -d /etc/lightning ]; then
  echo -n "Using lightningd directory mounted in /etc/lightning... "
  LN_PATH=/etc/lightning

else

  # Setup Actinium (only needed when we're starting our own lightningd instance)
  if [ -d /etc/actinium ]; then
    echo -n "Connecting to Actiniumd configured in /etc/actinium... "

    RPC_OPT="-datadir=/etc/actinium $([[ -z "$BITCOIND_RPCCONNECT" ]] || echo "-rpcconnect=$BITCOIND_RPCCONNECT")"

  elif [ -n "$BITCOIND_URI" ]; then
    [[ "$BITCOIND_URI" =~ ^[a-z]+:\/+(([^:/]+):([^@/]+))@([^:/]+:[0-9]+)/?$ ]] || \
      { echo >&2 "ERROR: invalid Actiniumd URI: $BITCOIND_URI"; exit 1; }

    echo -n "Connecting to Actiniumd at ${BASH_REMATCH[4]}... "

    RPC_OPT="-rpcconnect=${BASH_REMATCH[4]}"

    if [ "${BASH_REMATCH[2]}" != "__cookie__" ]; then
      RPC_OPT="$RPC_OPT -rpcuser=${BASH_REMATCH[2]} -rpcpassword=${BASH_REMATCH[3]}"
    else
      RPC_OPT="$RPC_OPT -datadir=/tmp/actinium"
      [[ "$NETWORK" == "actinium" ]] && NET_PATH=/tmp/actinium || NET_PATH=/tmp/actinium/$NETWORK
      mkdir -p $NET_PATH
      echo "${BASH_REMATCH[1]}" > $NET_PATH/.cookie
    fi

  else
    echo -n "Starting Actiniumd... "

    mkdir -p /data/actinium
    touch /data/actinium/Actinium.conf
    gen_wallet_conf.sh > /data/actinium/Actinium.conf
    RPC_OPT="-datadir=/data/actinium"

    Actiniumd $RPC_OPT &
    echo -n "waiting for cookie... "
    # sed --quiet '/^\.cookie$/ q' <(inotifywait -e create,moved_to --format '%f' -qmr /data/actinium)
  fi

  echo -n "waiting for RPC... "
  Actinium-cli $RPC_OPT -rpcwait getblockchaininfo > /dev/null
  echo "ready."

  # Setup lightning
  echo -n "Starting lightningd... "

  LN_PATH=/data/lightning
  mkdir -p $LN_PATH
  touch $LN_PATH/conf
  gen_ln_conf.sh > $LN_PATH/conf

  lnopt=(--conf=$LN_PATH/conf)
  [[ -z "$LN_ALIAS" ]] || lnopt+=(--alias="$LN_ALIAS")

  #lightningd "${lnopt[@]}" $(echo "$RPC_OPT" | sed -r 's/(^| )-/\1--actinium-/g') > /dev/null &
  lightningd --conf=$LN_PATH/conf
fi

if [ ! -S $LN_PATH/lightning-rpc ]; then
  echo -n "waiting for RPC unix socket... "
  sed --quiet '/^lightning-rpc$/ q' <(inotifywait -e create,moved_to --format '%f' -qm $LN_PATH)
fi

# lightning-cli is unavailable in standalone mode, so we can't check the rpc connection.
# Spark itself also checks the connection when starting up, so this is not too bad.
if command -v lightning-cli > /dev/null; then
  lightning-cli --lightning-dir=$LN_PATH getinfo > /dev/null
  echo -n "c-lightning RPC ready."
fi

mkdir -p $TOR_PATH/tor-installation/node_modules

if [ -z "$STANDALONE" ]; then
  # when not in standalone mode, run spark-wallet as an additional background job
  echo -e "\nStarting spark wallet..."
  spark-wallet -l $LN_PATH "$@" $SPARK_OPT &

  # shutdown the entire process when any of the background jobs exits (even if successfully)
  wait -n
  kill -TERM $$
else
  # in standalone mode, replace the process with spark-wallet
  echo -e "\nStarting spark wallet (standalone mode)..."
  exec spark-wallet -l $LN_PATH "$@" $SPARK_OPT
fi

