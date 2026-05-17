#!/bin/bash
# Patched autopause-fcns.sh
#
# Problema original (corrigido na v1):
#   mc-monitor usava o protocolo Minecraft para pingar 127.0.0.1:25565. Sob lag,
#   o timeout causava RST/FIN abrupto. O Netty interpretava como tráfego malformado
#   e banava 127.0.0.1, bloqueando o autopause permanentemente via fallback connections=1.
#
# Problema secundário (corrigido na v2):
#   A checagem via /proc/net/tcp contava conexões TCP de pings de status (lista de
#   servidores do cliente) como jogadores reais. O kernel aceita o TCP handshake mesmo
#   com Java pausado (SIGSTOP), então a conexão aparecia como ESTABLISHED antes de
#   qualquer login. RCON retorna apenas jogadores que completaram o login de fato.

# shellcheck source=../scripts/start-utils
. "$(dirname "$0")/../start-utils"

_MC_PORT="${SERVER_PORT:-25565}"

current_uptime() {
  awk '{print $1}' /proc/uptime | cut -d . -f 1
}

java_running() {
  [[ $( ps -ax -o stat,comm | grep 'java' | awk '{ print $1 }') =~ ^S.*$ ]]
}

java_process_exists() {
  [[ -n "$(ps -ax -o comm | grep 'java')" ]]
}

rcon_client_exists() {
  [[ -n "$(ps -ax -o comm | grep 'rcon-cli')" ]]
}

use_proxy() {
  if isTrue "$USES_PROXY_PROTOCOL"; then
    echo "--use-proxy"
  fi
}

use_server_list_ping() {
  if [[ "${VERSION^^}" == "LATEST" || "${VERSION^^}" == "SNAPSHOT" ]]; then
    return 1
  fi
  if versionLessThan 1.7; then
    echo "--use-server-list-ping"
  fi
}

# Verifica se o servidor tem socket em LISTEN via /proc/net/tcp.
# Não envolve nenhum protocolo Minecraft — leitura direta do kernel.
# State 0A = TCP_LISTEN. Porta em big-endian (network byte order).
mc_server_listening() {
  local port_hex
  port_hex=$(printf "%04X" "${_MC_PORT}")
  awk -v port="${port_hex}" '
    NR > 1 && $4 == "0A" {
      split($2, local, ":")
      if (toupper(local[2]) == port) { found = 1; exit }
    }
    END { exit (found ? 0 : 1) }
  ' /proc/net/tcp 2>/dev/null
}

# Retorna o número real de jogadores logados via RCON (rcon-cli list).
#
# Por que RCON e não /proc/net/tcp:
#   Pings de status do cliente Minecraft (tela de lista de servidores) estabelecem
#   uma conexão TCP que aparece como ESTABLISHED em /proc/net/tcp antes mesmo de
#   o Java processar — o kernel faz o handshake mesmo com o processo SIGSTOP'd.
#   O RCON consulta o servidor diretamente e conta apenas jogadores que completaram
#   o login, ignorando pings de status.
#
# RCON usa um pipeline Netty separado e não está sujeito ao rate limiter do
# game port que causava o ban de 127.0.0.1.
#
# Fallback: connections=1 (conservador) se RCON não responder.
java_clients_connections() {
  local connections=0
  if java_running; then
    local rcon_output
    if rcon_output=$(rcon-cli list 2>/dev/null); then
      connections=$(echo "$rcon_output" | grep -oE '[0-9]+' | head -1)
      connections=${connections:-0}
    else
      connections=1
    fi
  fi
  echo "$connections"
}

java_clients_connected() {
  (( $(java_clients_connections) > 0 ))
}
