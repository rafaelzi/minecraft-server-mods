# minecraft-server-mods

Imagem Docker customizada para servidores Minecraft modded, baseada em [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server).

Resolve um bug crítico do autopause em servidores sobrecarregados (muitos mods) e inclui boas práticas de segurança para servidores expostos na internet.

## O problema que esta imagem resolve

O mecanismo padrão de autopause usa `mc-monitor` para pingar o servidor via protocolo Minecraft. Em servidores com lag (modpacks pesados), esse ping causa timeouts que levam o Netty a banir `127.0.0.1` internamente — bloqueando o autopause para sempre via fallback `connections=1`.

### Cascata de falhas original

```
Servidor sobrecarregado ("Can't keep up!")
  → mc-monitor pinga 127.0.0.1:25565
  → timeout → conexão fechada abruptamente
  → Netty: "Ignoring further traffic from 127.0.0.1 for repeated malformed traffic"
  → todos os pings seguintes: i/o timeout
  → fallback: connections=1 (assume jogador conectado)
  → servidor NUNCA pausa
```

## O que foi alterado

O arquivo `autopause-fcns.sh` é substituído via `COPY` no Dockerfile com duas funções corrigidas:

| Função | Antes | Depois |
|---|---|---|
| `mc_server_listening()` | `mc-monitor status` (protocolo Minecraft) | Leitura de `/proc/net/tcp` — zero interação com o Java |
| `java_clients_connections()` | `mc-monitor --show-player-count` | `rcon-cli list` — conta só jogadores logados, ignora pings de status |

**Por que RCON e não `/proc/net/tcp` para contar jogadores:**
Pings de status (tela de lista de servidores do cliente) criam conexões TCP que aparecem como `ESTABLISHED` no kernel antes do login — o que causaria falsos positivos. O RCON retorna apenas quem completou o login de fato.

## Como usar

### Estrutura de diretórios

```
meu-servidor/
├── docker-compose.yml
├── minecraft-data/       ← criado automaticamente (mundo, configs, mods)
└── packs/
    └── meumodpack.zip    ← coloque o server pack aqui
```

### `docker-compose.yml`

Copie `docker-compose.example.yml` como ponto de partida:

```yaml
services:
  mc:
    image: rafaelzii/minecraft-server-mods:java17
    container_name: meu-servidor
    ports:
      - "25585:25565"
    environment:
      VERSION: "1.20.1"
      TYPE: "FABRIC"
      GENERIC_PACK: "/packs/meumodpack.zip"
      MEMORY: "8G"
    volumes:
      - ./minecraft-data:/data
      - ./packs:/packs
    restart: unless-stopped
    healthcheck:
      disable: true
```

### Subir o servidor

```bash
mkdir meu-servidor && cd meu-servidor
mkdir packs
# copie o .zip do modpack para packs/
curl -O https://... # ou scp, wget, etc.
docker compose up -d
docker compose logs -f  # acompanhar inicialização
```

Players conectam com: `seudominio.duckdns.org:25585`

## Boa prática: porta não-padrão

A porta `25565` é varrida automaticamente por scanners de Minecraft (Shodan, bots de listas de servidores). Isso acorda o servidor via knockd a cada poucos minutos mesmo sem nenhum jogador.

Usar uma porta não-padrão (ex: `25585`) elimina esse problema sem nenhum custo — players apenas adicionam `:25585` ao endereço.

**Três camadas para liberar a nova porta (OCI):**

```bash
# 1. OCI Console: Networking → VCN → Security Lists → adicionar TCP 25585, remover 25565

# 2. Firewall do Oracle Linux
sudo firewall-cmd --permanent --add-port=25585/tcp
sudo firewall-cmd --permanent --remove-port=25565/tcp
sudo firewall-cmd --permanent --remove-port=25565/udp
sudo firewall-cmd --reload

# 3. docker-compose.yml: ports: "25585:25565"
```

## Tags disponíveis

| Tag | Java | Minecraft |
|---|---|---|
| `java17` | Java 17 | Até 1.20.x |
| `java21` | Java 21 | 1.21+ |

## Como atualizar a imagem

```bash
# 1. Editar autopause-fcns.sh ou Dockerfile
# 2. Rebuild e push
docker build -t rafaelzii/minecraft-server-mods:java17 .
docker push rafaelzii/minecraft-server-mods:java17

# 3. Em cada servidor, atualizar sem perder dados
docker compose pull && docker compose up -d
```

## Estrutura do repositório

```
├── Dockerfile                  # receita da imagem (2 linhas úteis)
├── autopause-fcns.sh           # patch do autopause
├── docker-compose.example.yml  # modelo para novos servidores
└── README.md
```

## Variáveis obrigatórias no compose

| Variável | Exemplo | Descrição |
|---|---|---|
| `VERSION` | `1.20.1` | Versão do Minecraft |
| `TYPE` | `FABRIC` | Tipo do servidor |
| `GENERIC_PACK` | `/packs/pack.zip` | Caminho do modpack no container |
| `MEMORY` | `10G` | RAM para a JVM |

Todas as outras variáveis do `itzg/minecraft-server` funcionam normalmente.
