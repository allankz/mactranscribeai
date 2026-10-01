# MacTranscribe

App de barra de menus para macOS: atalho global → grava a voz → transcreve com a API da
OpenAI → você revisa → cola no cursor ou copia.

Compila **sem Xcode**, só com as Command Line Tools.

## Build

```bash
./build.sh
open build/MacTranscribe.app
```

Para instalar de vez: `cp -R build/MacTranscribe.app /Applications/`

## Uso

| Tecla | Ação |
|---|---|
| `⌥Space` | começa a gravar (em qualquer app) |
| `⌥Space` | para e transcreve |
| `⎋` | **aborta** — durante a gravação ou o upload, sem transcrever nem gastar API |
| `⏎` | cola no cursor de onde você veio |
| `⌘C` | copia para a área de transferência |
| `⌥⏎` | quebra de linha (ao editar o texto) |
| `⎋` | descarta |

O texto aparece num painel editável — dá pra corrigir antes de colar.

`⎋` existe para disparo acidental: cancela na hora, devolve o foco ao app de onde você
veio e nada é enviado. Ele é registrado como hotkey global **apenas** enquanto há
gravação ou upload em curso — em repouso o Esc nunca é interceptado.

## Permissões

- **Microfone** — obrigatório. O macOS pergunta na primeira gravação.
- **Acessibilidade** — só para colar sozinho no cursor (`⏎`). Sem ela o app continua
  funcionando: o texto vai para a área de transferência e você cola com `⌘V`.

Menu da barra → **Permissões…** mostra o estado das duas e abre os Ajustes.

## Configuração

Tudo pelo ícone 🎤 na barra de menus:

- **Chave da API** — guardada no Keychain do macOS, nunca em arquivo.
- **Atalho** — presets (`⌥Space`, `⌃⌥D`, `⌃⌥⌘Space`, `⌃⌥V`, `F13`) ou **Personalizar…**,
  que grava qualquer combinação e avisa na hora se ela colide com o sistema.
- **Modelo** — `gpt-4o-transcribe` (padrão), `gpt-4o-mini-transcribe`, `whisper-1`.
- **Idioma** — travar em Português melhora precisão e velocidade.
- **Vocabulário / contexto** — nomes e jargão que o modelo costuma errar.
- **Traduzir para inglês** — depois de transcrever, faz **uma** passada de tradução
  (`/v1/chat/completions`, `temperature: 0`) e mostra o texto já em inglês. O prompt é
  estrito: só traduz, não reescreve nem resume, e preserva nomes próprios, números e
  termos técnicos. Se a tradução falhar, o painel abre com o texto original em vez de
  perder o que você falou.
- **Colar sem revisar** — pula o painel e cola direto.

## Custo

Áudio é enviado em AAC 16 kHz mono (~4 KB/s), então o upload é rápido.

| Modelo | Preço |
|---|---|
| `gpt-4o-mini-transcribe` | ~US$ 0,003/min |
| `whisper-1` | US$ 0,006/min |
| `gpt-4o-transcribe` | ~US$ 0,006/min |

A tradução usa `gpt-4o-mini` (~150 tokens por frase curta, custo desprezível). Para
trocar de modelo sem recompilar:

```bash
defaults write com.allan.mactranscribe translationModel gpt-4.1-mini
```

## Estrutura

```
Sources/
  main.swift            entrada (LSUIElement, sem Dock)
  AppDelegate.swift     máquina de estados + menu da barra
  HotKeyManager.swift   atalho global via Carbon (não exige Acessibilidade)
  Recorder.swift        AVAudioRecorder + medidor de nível
  Transcriber.swift     multipart POST para /v1/audio/transcriptions
  ReviewPanel.swift     painel de revisão editável
  RecordingHUD.swift    HUD flutuante durante a gravação
  Paster.swift          clipboard + CGEvent ⌘V no app anterior
  Keychain.swift        chave da API no Keychain
  Config.swift          preferências (UserDefaults)
```

## Atalhos reservados pelo macOS

Cuidado ao escolher um atalho: `RegisterEventHotKey` **retorna `noErr` mesmo para
combinações que o macOS já reservou**. O sistema captura a tecla antes de ela chegar em
qualquer app, então o registro "dá certo" e o atalho simplesmente nunca dispara — sem
nenhum erro.

Por isso `⌃⌥Space` não serve: é *"trocar para a próxima fonte de entrada"*, ligado por
padrão em qualquer Mac com mais de um layout de teclado.

Como não dá para detectar isso pela API, [SystemHotKeys.swift](Sources/SystemHotKeys.swift)
lê `~/Library/Preferences/com.apple.symbolichotkeys.plist` e compara keycode + modificadores
com os atalhos ativos do sistema. O app avisa no boot, marca `⚠︎` no menu e bloqueia o
botão Salvar no gravador de atalhos.

Para inspecionar a lista você mesmo:

```bash
plutil -convert xml1 -o - ~/Library/Preferences/com.apple.symbolichotkeys.plist | grep -A8 "<key>61</key>"
```

## Nota sobre assinatura ad-hoc

O app é assinado com `codesign -s -`. A cada rebuild a assinatura muda, e o macOS pode
pedir as permissões de novo. Se isso incomodar, use uma conta de desenvolvedor Apple e
troque `-` pela sua identidade em `build.sh`.
