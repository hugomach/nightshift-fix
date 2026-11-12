# nightshift-fix

Malý helper na pozadí pro macOS, který opravuje chybu, kdy **Night Shift přestane fungovat po odpojení monitoru nebo po vypnutí obrazovky**. Night Shift pak v nastavení vypadá jako zapnutý, ale obrazovka je zase modrá.

🌐 **Stránka projektu:** https://hugomach.github.io/nightshift-fix/

*English summary at the bottom.*

---

## Proč se to děje

Když se změní konfigurace displejů (odpojení nebo připojení monitoru, uspání obrazovky, probuzení Macu), WindowServer resetuje barevné (gamma) tabulky displejů. Systémová služba CoreBrightness, která Night Shift řídí, je po této změně někdy nepoužije znovu. Stav „zapnuto“ tedy zůstane, ale filtr zmizí. Proto chybu obvykle vyřeší ruční vypnutí a zapnutí Night Shiftu.

## Co nsfix dělá

`nsfix` je jeden malý program v Objective‑C (cca 70 řádků), který běží jako LaunchAgent a:

1. poslouchá změny konfigurace displejů (`CGDisplayRegisterReconfigurationCallback`),
2. poslouchá uspání a probuzení obrazovky i Macu (`NSWorkspace` notifikace),
3. si **před** změnou zapamatuje, jestli byl Night Shift zapnutý,
4. **2 sekundy po** změně, pokud byl zapnutý, ho rychle vypne a zapne, aby se filtr znovu použil.

Night Shift nikdy nezapne, když byl předtím vypnutý, a nijak nemění tvůj plán ani intenzitu.

Využívá privátní třídu `CBBlueLightClient` z `CoreBrightness.framework`, stejnou, kterou používá Ovládací centrum.

## Požadavky

- macOS s Night Shiftem (testováno na macOS 27, Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`), kvůli kompilaci

## Instalace

```bash
git clone https://github.com/hugomach/nightshift-fix.git
cd nightshift-fix
./install.sh
```

Skript zkompiluje helper do `~/.local/nightshift-fix/nsfix`, vytvoří `~/Library/LaunchAgents/com.user.nightshift-fix.plist` a helper spustí. Od té chvíle se pouští automaticky po každém přihlášení.

## Ověření, že běží

```bash
launchctl list | grep nightshift-fix          # vypíše PID, pokud běží
log stream --predicate 'process == "nsfix"'   # živý log; odpoj/připoj monitor
```

Po události uvidíš v logu `nsfix: re-applying Night Shift`.

## Odinstalace

Ze složky repozitáře:

```bash
./uninstall.sh
```

Nebo ručně, bez repozitáře:

```bash
launchctl bootout gui/$(id -u)/com.user.nightshift-fix
rm ~/Library/LaunchAgents/com.user.nightshift-fix.plist
rm -rf ~/.local/nightshift-fix
```

Nic dalšího v systému nezůstane. Nastavení Night Shiftu se nemění.

## Soubory

| Cesta | Co to je |
|---|---|
| `src/nsfix.m` | zdrojový kód helperu |
| `install.sh` | kompilace + instalace LaunchAgenta |
| `uninstall.sh` | kompletní odebrání |
| `docs/index.html` | stránka projektu (GitHub Pages) |

## Řešení problémů

- **Filtr se pořád ztrácí:** zkontroluj, že helper běží (`launchctl list | grep nightshift-fix`). Pokud monitor potřebuje na probuzení déle, zvyš v `src/nsfix.m` prodlevu `2 * NSEC_PER_SEC` a spusť znovu `./install.sh`.
- **Krátké problesknutí:** to je záměr. Rychlé vypnutí a zapnutí je právě to, co filtr obnoví.
- **Po aktualizaci macOS přestane fungovat:** `CBBlueLightClient` je privátní API a Apple ho může změnit. Odinstaluj a nahlas issue.

---

## English summary

macOS sometimes drops the Night Shift color filter after a display is disconnected or the screen sleeps, while Night Shift still shows as "on". `nsfix` is a tiny LaunchAgent that watches for display reconfiguration and wake events. If Night Shift was on beforehand, it toggles it off and on to re-apply the filter. Install with `./install.sh`, remove with `./uninstall.sh`.

## Licence

MIT
