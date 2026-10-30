# Значки Roblox — что создать в Creator Dashboard

Картинки лежат рядом (512×512, круглые). Название и описание вставляй как есть — их видят игроки.
После создания у значка будет ID (число в адресе страницы значка). Его нужно вписать в `Config.Badges`
в `src/ReplicatedStorage/Config/GameConfig.luau` (ключ — в последней колонке).

| Файл | Название | Описание | Ключ в Config.Badges |
|---|---|---|---|
| 01_Welcome.png | Welcome to the Archipelago | Joined Island War for the first time. | `Welcome` |
| 02_FirstKill.png | First Blood | Defeated your first enemy. | `FirstKill` |
| 03_FirstPlane.png | Sky Hunter | Shot down your first enemy plane. | `FirstPlane` |
| 04_FirstSink.png | Ship Breaker | Sank your first enemy ship. | `FirstSink` |
| 05_FirstCapture.png | Island Raider | Helped capture an island for your team. | `FirstCapture` |
| 06_RoundWin.png | Victory! | Won a round with your team. | `RoundWin` |
| 07_DailyAll.png | Daily Duty | Completed all three daily quests in one day. | `DailyAll` |
| 08_Streak7.png | On Fire | Logged in 7 days in a row. | `Streak7` |
| 09_InviteFriend.png | Squad Up | A friend joined the game from your invite. | `InviteFriend` |
| 10_Officer.png | Officer | Reached an officer rank. | `Officer` |
| 11_MVP.png | MVP | Became the MVP of a round. | `MVP` |

## Как создать

1. create.roblox.com → Creations → игра «Архипелаг: война и торговля».
2. Слева: **Engagement → Badges** (в некоторых версиях — **Associated Items → Badges**) → **Create a Badge**.
3. Загрузи картинку, впиши название и описание из таблицы → **Create Badge**.
4. Открой созданный значок и скопируй число из адреса страницы — это ID.

Бесплатно Roblox даёт создать несколько значков в сутки на игру (обычно 5); сверх лимита значок стоит Robux —
Dashboard покажет цену перед созданием. Если лимит кончился, остальные создай на следующий день:
пока ID = 0, значок просто не выдаётся.
