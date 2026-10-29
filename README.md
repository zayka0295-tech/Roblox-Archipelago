# Архипелаг: война и торговля

Код Roblox-игры (placeId 133999112849220).

## Что где лежит

- `src/` — весь рабочий код игры, разложенный так же, как в Studio:
  - `ServerScriptService/Main.server.luau` — точка входа сервера, `Services/` — серверные сервисы;
  - `StarterPlayer/StarterPlayerScripts/ClientMain/` — клиент и его модули;
  - `ReplicatedStorage/Config/GameConfig.luau` — все настройки и баланс;
  - `ServerStorage/Tools/` — генераторы мира и построек;
  - `ServerStorage/Weapons/Rifle/RifleClient.client.luau` — скрипт внутри модели винтовки (Rojo его не синхронизирует, правится в Studio);
  - `_manifest.txt` — список выгруженных файлов с числом строк.
- `archive/` — старые бэкапы, которые раньше лежали в ServerStorage (`...Backup_дата`). Каждый — файл `.rbxm`;
  вернуть в Studio: ПКМ по ServerStorage → Insert from File.
- `default.project.json` — проект Rojo.

## Как работать дальше

Вместо копирования скриптов в папки-бэкапы — git: перед изменением делается коммит, откатиться можно на любой.

С Rojo код правится в редакторе (VS Code), а Studio подхватывает изменения сама:

1. Установить Rojo (https://rojo.space) и плагин Rojo в Studio.
2. В этой папке: `rojo serve`.
3. В Studio: плагин Rojo → Connect.

Rojo управляет только папками из `default.project.json` (скрипты). Модели, карта, Remotes и прочее
остаются в Studio и не трогаются (`$ignoreUnknownInstances`).
