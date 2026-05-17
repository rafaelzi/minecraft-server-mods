# Versão do Java como build arg — permite gerar tags diferentes sem alterar o arquivo
# Uso: docker build --build-arg JAVA_VERSION=21 -t user/minecraft-server:java21 .
ARG JAVA_VERSION=17
FROM itzg/minecraft-server:java${JAVA_VERSION}

# Embute o patch do autopause diretamente na imagem.
# Substitui mc-monitor (que causa Self-DoS via Netty sob lag) por:
#   mc_server_listening()    → /proc/net/tcp (kernel, zero protocolo Minecraft)
#   java_clients_connections() → rcon-cli list (jogadores reais, ignora pings de status)
COPY autopause-fcns.sh /image/scripts/auto/autopause-fcns.sh

# Desativa o healthcheck herdado da imagem base (evita pings paralelos ao Minecraft)
HEALTHCHECK NONE

# ---------------------------------------------------------------------------
# Defaults seguros para qualquer servidor modded sob carga alta.
# Todos sobrescrevíveis via `environment:` no docker-compose.yml.
# ---------------------------------------------------------------------------
ENV EULA=TRUE \
    # Tipo de servidor — sobrescrever para FORGE, QUILT, etc.
    TYPE=FABRIC \
    # Autopause
    ENABLE_AUTOPAUSE=TRUE \
    AUTOPAUSE_TIMEOUT_EST=60 \
    AUTOPAUSE_TIMEOUT_INIT=60 \
    AUTOPAUSE_PERIOD=60 \
    DEBUG_AUTOPAUSE=FALSE \
    # Evita crash do watchdog quando o servidor trava processando chunks
    MAX_TICK_TIME=-1 \
    # Flags de JVM otimizadas para servidores Minecraft (Aikar)
    USE_AIKAR_FLAGS=TRUE \
    # Força IPv4 — necessário para o patch de /proc/net/tcp funcionar corretamente
    JVM_OPTS="-Djava.net.preferIPv4Stack=true" \
    # Permite enviar comandos ao servidor via pipe no host
    CREATE_CONSOLE_IN_PIPE=true \
    TZ=America/Sao_Paulo

# Variáveis que DEVEM ser fornecidas no docker-compose.yml (sem default intencional):
#   VERSION       — versão do Minecraft  ex: "1.20.1"
#   GENERIC_PACK  — caminho do modpack   ex: "/packs/meupack.zip"
#   MEMORY        — RAM para a JVM       ex: "10G"
