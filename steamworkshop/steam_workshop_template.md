[img]https://i.imgur.com/yKFYcYd.png[/img]
[b][i]A DFHack Dwarf Fortress lua mod[/i][/b]

[b]Dwarf Fortress Herald[/b]
is a first of it's kind mod (at least as far as I'm aware) that allows you to explore the history of your world's inhabitants WHILST playing the game! No more mucking about with saves

[b]Requires DFHack![/b]



[img]https://i.imgur.com/rJxuHOh.png[/img]
[list]
[*] An in-built graphical user interface for you to explore historical figures, civilisations and artifacts
[*] Event history view to see the entire history of a given historical figure, civilisation or artifact
[*] Quick access to DFHack's inbuilt journal, so you never have to leave Dwarf Fortress to take notes
[*] Pin individuals or civilisations to be notified of in-game events in near real-time, including:
-------------------------
[b]Individuals:[/b]
- Death
- Combat kills
- Position appointments & vacations
- Relationship changes (marriage, divorce, apprenticeship, worship, intrigue)
- Legendary skill achievements
- Artifact creation & written works
- Migrations & relocations

[b]Civilisations:[/b]
- Leadership changes
- Diplomacy (peace, agreements, tribute, wars)
- Battles & raids
- Beast rampages
- Espionage (theft & abduction)
[b]All these options are toggleable via the UI![/b]
-------------------------
[/list]


[b]Compatible with:[/b]
[list]
[*] Fort Mode: [b]Yes[/b]
[*] Adventurer Mode: [b]Yes[/b]
[/list]

[b]Controls:[/b]
[list]
[*] [b]Alt+H[/b] or click the Herald button - Open the Herald GUI
[*] [b]Ctrl+T[/b] - Cycle through tabs (Recent, Pinned, Historical Figures, Civilisations, Artifacts)
[*] [b]Ctrl+E[/b] - Open Event History for the selected entry
[*] [b]Ctrl+P[/b] - Toggle "Pinned only" filter
[*] [b]Ctrl+D[/b] - Toggle "Show dead" filter (Historical Figures tab)
[*] [b]Ctrl+I[/b] - Switch between Individuals and Civilisations (Pinned tab)
[*] [b]Ctrl+J[/b] - Open DFHack Journal
[*] [b]Ctrl+C[/b] - Refresh cache
[*] [b]Ctrl+Z[/b] - Clear all recent announcements
[*] [b]Enter[/b] - Pin/Unpin the selected entry
[*] Type to search and filter lists in real-time
[/list]



[img]https://i.imgur.com/YrFazkE.png[/img]
[b]Q: Will this impact performance?[/b]
A: The mod should not significantly impact performance unless you pin a significant number of civilisations and historical figures to track. I've been able to pin 40+ civilisations/individuals with no problems, though, the game can micro freeze when an announcement fires as the mod tries to gather the details of what happened

Worst case, you can try edit the tick rate of Herald by running [i]'herald interval'[/i] in the DFHack console, which will allow you to adjust how often Herald fires (can lead to worse freezes if it tries to process more events in one go - particularly happens in adventurer mode)

[b]Q: How are pins saved?[/b]
A: Pins are split by save. Your pins can diverge depending on what save they're associated to, even if it's the same fort

[b]Q: I can't use the search feature![/b]
A: Sometimes the search box bugs out, and you can't type anything to filter records. To fix this, try closing the Herald GUI and ALT+TAB to minimise Dwarf Fortress, and then ALT+TAB back into the game. If that doesn't work, press '~' to open DFHack's window and try typing in the console there

If it works in DFHack, it should work in the Herald window

[b]Q: Some information is missing compared to Legends viewing tools![/b]
A: Some information is, unfortunately, unavailable due to the fact that Herald attempts to access it's records via the in-game memory

Tools such as [url=https://github.com/Kromtec/LegendsViewer-Next]Kromtec's LegendViewerNext[/url] still have value as they use DFHack's detailed Legends view exports, which can shed more light on your world!

[b]Q: I found a bug. What do I do?[/b]
A: Please post in the [url=https://steamcommunity.com/workshop/filedetails/discussion/3682900869/798964126635297633/]discussions tab[/url] with a description of the issue

[hr][/hr]
[b]Changelog:[/b]
[i]Check your DF mods, and unsub resub if the mod isn't updating to latest[/i]
v1.1
- Fixed issue with adventurer mode where it would not retain last-scanned event everytime you changed map, making it scan every event since the beginning of time

[hr][/hr]

[i]If you enjoy this mod, please rate it up - it helps others find it![/i]

[i]Please ask for permission before modifying or distributing the mod![/i]