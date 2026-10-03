## v0.2.0 (2026-10-03)

### Feat

- permite fixar itens do clipboard, destacados no topo, e aumenta o popup padrão
- aumenta o preview de imagem, expandindo o popup enquanto está aberto
- adiciona ícone na barra para abrir o overlay do clipboard
- estrutura inicial do plugin Clipboard (clonado de omarchy.clipboard)

### Fix

- lista embaralhava (Array.sort do QML não é estável) fazendo cópias novas sumirem da área visível; pins antigos sempre visíveis e não são mais cortados no save
- valida tamanho e dimensão decodificada antes do preview de imagem (mesma classe de bomba de descompressão do media), e limita bytes capturados no capture.sh
- força textFormat: Text.PlainText no conteúdo do clipboard (texto colado é totalmente não confiável)
- itens fixados nunca são removidos pelo limite de histórico ou por limpar tudo
- preview de imagem inline no popup em vez de uma segunda janela
- move a confirmação de limpar histórico para dentro do conteúdo do popup
- importa Quickshell.Io no BarWidget para o IpcHandler resolver

### Refactor

- substitui o overlay em tela cheia por um popup no estilo dos outros plugins, com preview de imagem via botão de olho
