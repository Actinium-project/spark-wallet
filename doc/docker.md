## Setting up Spark with Docker

You can use Docker to setup Spark, an Actinium node and an `acm-lightning` node all in one go with the following commands:

First you'll have to build a Docker image on your machine. This is done only once.

```bash
docker build -t my-acm-lightning-node .
```

After the build has completed (which can take some time) start your container with:

```bash
$ docker run -v ~/.spark-docker:/data -p 9737:9737 \
             my-acm-lightning-node --login bob:superSecretPass456

docker run -p 9737:9737 -it -e "RPCUSER=myusername" -e "RPCPASSWORD=mypassword" -e "RPCALLOWIP=127.0.0.1" -e "TORENABLED=0" my-acm-lightning-node --login mylnuser:mylnpassword


```

You will then be able to access the Spark wallet at `https://localhost:9737`.

Runs in `mainnet` mode by default.

Data files will be stored in `~/.spark-docker/{actinium,lightning,spark}`.
You can set Spark's configuration options in `~/.spark-docker/spark/config`.

When starting for the first time, you'll have to wait for the Actinium node to sync up.
You can check the progress by tailing `~/.spark-docker/actinium/debug.log`.

You can set custom command line options for `Actiniumd` with `BITCOIND_OPT`
and for `lightningd` with `LIGHTNINGD_OPT`.

Note that TLS will be enabled by default (even without changing `--host`).
You can use `--no-tls` to turn it off.

#### With existing `lightningd`

To connect to an existing `lightningd` instance running on the same machine,
mount the lightning data directory to `/etc/lightning`:

```bash
$ docker run -v ~/.spark-docker:/data -p 9737:9737 \
             -v ~/.lightning:/etc/lightning \
             my-acm-lightning-node
```

Connecting to remote lightningd instances is currently not supported.

#### With existing `Actiniumd`, but with bundled `lightningd`

To connect to an existing `Actiniumd` instance running on the same machine,
mount the Actinium data directory to `/etc/actinium` (e.g. `-v ~/.actinium:/etc/actinium`),
and either use host networking (`--network host`) or specify the IP where bitcoind is reachable via `BITCOIND_RPCCONNECT`.
The RPC credentials and port will be read from Actiniumd's config file.

To connect to a remote Actiniumd instance, set `BITCOIND_URI=http://[user]:[pass]@[host]:[port]`
(or use `__cookie__:...` as the login for cookie-based authentication).
