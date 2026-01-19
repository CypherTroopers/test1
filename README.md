# 1. 
 ```
cat <<'EOF' > setup_cypherium.sh
#!/bin/bash

set -e

sudo apt update
sudo apt install ufw git nano -y
command -v rsync >/dev/null 2>&1 || sudo apt install -y rsync

sudo ufw allow 22/tcp
sudo ufw allow 22/udp
sudo ufw allow 8000/tcp
sudo ufw allow 8000/udp
sudo ufw allow 6000/tcp
sudo ufw allow 6000/udp
sudo ufw allow 9090/tcp
sudo ufw allow 9090/udp
sudo ufw allow 7100/tcp
sudo ufw allow 7100/udp
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp
sudo ufw allow 30301/tcp
sudo ufw allow 30301/udp
sudo ufw allow 9600/tcp
sudo ufw allow 9600/udp
sudo ufw allow 8546/tcp
sudo ufw allow 8546/udp

yes | sudo ufw enable
sudo ufw status numbered

echo "🧩 Step 1: Update and clean packages"
sudo apt update
sudo apt upgrade -y
sudo apt full-upgrade -y
sudo apt autoremove -y
sudo apt autoclean -y

echo "🧩 Step 2: Install Go 1.25.6"
wget -4 https://go.dev/dl/go1.25.6.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.25.6.linux-amd64.tar.gz
rm -f go1.25.6.linux-amd64.tar.gz

echo "🧩 Step 3: Configure Go environment variables"
export PATH=/usr/local/go/bin:$PATH
export GOPATH=$HOME/go
export GO111MODULE=off
go env -w GO111MODULE=off

grep -q '/usr/local/go/bin' ~/.bashrc || echo 'export PATH=/usr/local/go/bin:$PATH' >> ~/.bashrc
grep -q 'GOPATH' ~/.bashrc || echo 'export GOPATH=$HOME/go' >> ~/.bashrc

echo "🧩 Step 4: Install required development packages"
sudo apt-get update
sudo apt-get install -y gcc cmake libssl-dev openssl libgmp-dev \
bzip2 m4 build-essential git curl libc-dev \
wget texinfo nodejs npm pcscd

echo "🧩 Step 5: Build and install GMP 6.1.2"
wget -4 https://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.bz2
tar -xjf gmp-6.1.2.tar.bz2
cd gmp-6.1.2
./configure --prefix=/usr --enable-cxx --disable-static --docdir=/usr/share/doc/gmp-6.1.2
make
make check || echo "※ Some tests may fail and can be ignored."
make html
sudo make install
sudo make install-html
cd ..
sudo cp -rf /usr/lib/libgmp* /usr/local/lib/

echo "🧩 Step 6: Clone Cypherium source code and copy BLS libraries"
mkdir -p $GOPATH/src/github.com/cypherium
cd $GOPATH/src/github.com/cypherium
git clone https://github.com/cypherium/cypher.git
cd cypher
git fetch --all
git checkout ecdsa_1.1
cp ./crypto/bls/lib/linux/* ./crypto/bls/lib/

echo "🧩 Step 7: Clone external Go packages"
mkdir -p $GOPATH/src/github.com/VictoriaMetrics
cd $GOPATH/src/github.com/VictoriaMetrics
git clone https://github.com/VictoriaMetrics/fastcache.git

mkdir -p $GOPATH/src/github.com/shirou
cd $GOPATH/src/github.com/shirou
git clone https://github.com/shirou/gopsutil.git

mkdir -p $GOPATH/src/github.com/dlclark
cd $GOPATH/src/github.com/dlclark
git clone https://github.com/dlclark/regexp2.git

mkdir -p $GOPATH/src/github.com/go-sourcemap
cd $GOPATH/src/github.com/go-sourcemap
git clone https://github.com/go-sourcemap/sourcemap.git

mkdir -p $GOPATH/src/github.com/tklauser
cd $GOPATH/src/github.com/tklauser
git clone https://github.com/tklauser/go-sysconf.git
git clone https://github.com/tklauser/numcpus.git

mkdir -p $GOPATH/src/golang.org/x
cd $GOPATH/src/golang.org/x
git clone https://go.googlesource.com/sys

echo "🧩 Step 8: Patch duk_logging.c"
DUK_LOGGING_PATH="$GOPATH/src/github.com/cypherium/cypher/vendor/gopkg.in/olebedev/go-duktape.v3/duk_logging.c"
sed -i 's/duk_uint8_t date_buf\[32\]/duk_uint8_t date_buf[64]/' "$DUK_LOGGING_PATH"
sed -i 's/sprintf((char *) date_buf/snprintf((char *) date_buf, sizeof(date_buf),/' "$DUK_LOGGING_PATH"

echo "🧩 Step 9: Build Cypher"
cd $GOPATH/src/github.com/cypherium/cypher
source ~/.bashrc
sed -i 's/stopTheWorld(/\/\/stopTheWorld(/g' vendor/github.com/fjl/memsize/memsize.go
sed -i 's/startTheWorld(/\/\/startTheWorld(/g' vendor/github.com/fjl/memsize/memsize.go
sed -i '21d;22d' vendor/github.com/fjl/memsize/memsize.go
sudo sed -i 's/^#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf
make clean
make cypher

echo "🧩 Step 10: Initialize Genesis and load chaindata"
cd $GOPATH/src/github.com/cypherium/cypher
if [ ! -f ./genesis.json ]; then
 echo "ERROR: genesis.json が $GOPATH/src/github.com/cypherium/cypher/ wher is genesis.json"
 exit 1
fi
./build/bin/cypher --datadir chaindbname init ./genesis.json

cd $GOPATH/src/github.com/cypherium/
git clone https://github.com/cypherium/cypher-bin.git
rm -rf /root/go/src/github.com/cypherium/cypher/chaindbname/cypher/chaindata/
rsync -a /root/go/src/github.com/cypherium/cypher-bin/database/chaindb/cypher/chaindata/ /root/go/src/github.com/cypherium/cypher/chaindbname/cypher/chaindata/

echo "🧩 Step 11: Setup stable Node.js and PM2"
sudo npm install -g n
sudo n stable
sudo apt purge -y nodejs npm
sudo apt autoremove -y
export PATH="/usr/local/bin:$PATH"
sudo npm install -g pm2

echo "🧩 Step 12: Create start-cypher.sh script"
cd $GOPATH/src/github.com/cypherium/cypher
cat <<'EOT' > start-cypher.sh
#!/bin/bash
./build/bin/cypher \
--verbosity 4 \
--rnetport 7100 \
--syncmode full \
--nat extip:$(curl -4 -s ifconfig.io) \
--ws \
--ws.addr 0.0.0.0 \
--ws.port 8546 \
--ws.origins "*" \
--rpc.gascap 10000000 \
--rpc.txfeecap 1000 \
--metrics \
--http \
--http.addr 0.0.0.0 \
--http.port 8000 \
--http.api eth,web3,net,txpool \
--http.corsdomain "*" \
--port 6000 \
--datadir chaindbname \
--networkid 16166 \
--gcmode archive \
--bootnodes enode://a1e825dcb84155d5ec651a0cf98e22ac5d4dc34733d22eb6d031216ac2988646f0f85035118ec8e2369dace00221ed3a06a6aeacda520414e71f3b56662d7055@34.106.3.238:30301 \
console
EOT

chmod +x start-cypher.sh

echo "🧩 Step 13: Launch with PM2"
pm2 start ./start-cypher.sh --name cypher-node
pm2 startup
pm2 save

echo "🧩 Step 14: Setup CypherNode-chat (Python + Ollama)" && \
cd ~/go/src/github.com/cypherium/cypher && \
git clone https://github.com/CypherTroopers/CypherNode-chat.git && \
cd CypherNode-chat && \
sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip && \
python3 -m venv .venv && \
. .venv/bin/activate && \
pip install --upgrade pip && \
pip install -r requirements.txt && \
curl -fsSL https://ollama.com/install.sh | sh && \
sudo systemctl enable --now ollama && \
ollama pull qwen2.5:3b && \
pm2 start ./.venv/bin/uvicorn \
  --name CypherNode-chat \
  --cwd "$PWD" \
  --interpreter none \
  -- app:app --host 0.0.0.0 --port 9600 && \
pm2 save

EOF

chmod +x setup_cypherium.sh
./setup_cypherium.sh
```
