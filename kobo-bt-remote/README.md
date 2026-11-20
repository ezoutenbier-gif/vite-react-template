# 8BitDo-afstandsbediening op Kobo + KOReader (automatisch verbinden)

Dit pakket zet een 8BitDo-controller (Micro, Zero 2 of vergelijkbaar) als
bladerknop op je Kobo met KOReader. Het verbindt vanzelf opnieuw en werkt
ook samen met BookOrbit.

## Welke aanpak en waarom

Er zijn twee KOReader-plugins voor Bluetooth op Kobo:

| | **kobo.koplugin** (OGKevin), gekozen | bluetooth.koplugin (onatbas) |
|---|---|---|
| Automatisch verbinden | Ja: Bluetooth gaat aan bij het starten en na het wakker worden, maakt zelf verbinding met gekoppelde remotes en herkent remotes die zelf terugverbinden | Nee: elke sessie handmatig "Bluetooth On" en dan "Connect to saved device" |
| Knoppen | Per apparaat, via "Register button" en een eigen invoerlezer | Eén globale `event_map.lua` die je met de hand bijwerkt |
| Onderhoud | Actief; Bluetooth-fixes tot november 2026 | Minder actief |
| Modellen | Libra 2, Libra Colour, Clara BW, Clara Colour, Elipsa 2E | Ook Clara 2E (andere modellen experimenteel) |

De plugin die je nu gebruikt is waarschijnlijk bluetooth.koplugin. Die
verbindt per definitie niet vanzelf: de maker schrijft zelf dat
8BitDo-controllers niet terugverbinden bij het opstarten. kobo.koplugin
lost dat op met "Enable on startup", "Auto-resume after wake" en
"Auto-connect".

**Gebruikte versie:** kobo.koplugin vanaf `main`, commit `607691b`
(18 nov 2026), zie `PLUGIN_COMMIT`. De laatste officiële release (v0.4.1,
februari 2026) mist "Enable on startup", sneller terugverbinden en een
reeks stabiliteitsfixes voor Bluetooth (vastlopende UI, lekkende
poll-taken, MTK-radio en de koude start op de Libra 2). Wil je toch de
release, draai dan `tools/update-plugin.sh v0.4.1`. Je raakt dan wel de
automatische start van Bluetooth kwijt.

### En BookOrbit?

BookOrbit synchroniseert je bibliotheek en leesvoortgang al, via de
BookOrbit-plugin in KOReader en via Kobo-sync in Nickel. Daarom zet dit
pakket bij een nieuwe installatie de **virtuele bibliotheek** en de
**Kobo-voortgangssync** van kobo.koplugin uit. Zo synchroniseren er geen
twee systemen door elkaar heen. kobo.koplugin doet hier dus alleen
Bluetooth. Je BookOrbit-plugin blijft onaangeroerd.

## Wat er geïnstalleerd wordt

```
.adds/koreader/plugins/kobo.koplugin/        de Bluetooth-plugin
.adds/koreader/patches/2-bt-remote-setup.lua kleine patch die alles klaarzet
```

De patch doet drie dingen:

1. **Eenmalig de instellingen goed zetten:** Bluetooth aan bij het starten,
   weer aan na de slaapstand, automatisch verbinden en automatisch
   detecteren. Wat je later in het menu verandert, blijft staan.
2. **Eenmalig de oude Bluetooth-plugin uitschakelen.** Dat gebeurt alleen
   op modellen die kobo.koplugin ondersteunt. De plugin wordt niet
   verwijderd: je zet hem terug via *Gereedschap → Meer gereedschap →
   Pluginbeheer*. Twee plugins die tegelijk de Bluetooth-stack aansturen is
   de meest voorkomende oorzaak van "werkt soms wel, soms niet".
3. **Standaardknoppen.** Bij de eerste knopdruk krijgt een remote zonder
   knoptoewijzingen automatisch deze indeling:
   - volgende pagina: →, ↓, PageDown, spatie, "volgend nummer", volume +
   - vorige pagina: ←, ↑, PageUp, "vorig nummer", volume −

   Knoppen die je zelf toewijst, overschrijft de patch nooit.

## Installeren (zodra de Kobo verbonden is)

Voorwaarde: KOReader staat al op de Kobo.

**macOS / Linux**
```bash
cd kobo-bt-remote
./install.sh --wait        # wacht op de Kobo en installeert meteen
```

**Windows** (PowerShell)
```powershell
cd kobo-bt-remote
powershell -ExecutionPolicy Bypass -File install.ps1 -Wait
```

Zo verloopt het:

1. Start het script.
2. Sluit de Kobo aan met USB en tik op **Verbinden**.
3. Het script maakt een back-up naar `kobo-bt-remote/backups/<datum>/`:
   `settings.reader.lua`, de bestaande Bluetooth-plugins en `patches/`.
4. Daarna kopieert het de bestanden naar de Kobo.

Met `--dry-run` zie je eerst wat er zou gebeuren. Daarna werp je de Kobo
veilig uit en start je KOReader.

## Eerste keer koppelen (eenmalig)

**8BitDo Micro**
1. Zet de schakelaar op **K** (keyboard-modus).
2. Houd de **pair**-knop 3 seconden ingedrukt tot het lampje snel knippert.

**8BitDo Zero 2**
1. Zet de controller aan in **keyboard-modus** (meestal **R + Start**; controleer de 8BitDo-handleiding).
2. Houd **Select** 3 seconden ingedrukt om te koppelen.

Werkt de keyboard-modus niet, gebruik dan een andere modus en wijs de
knoppen zelf toe met "Register button" (zie onder).

**Op de Kobo, in KOReader**
1. Ga naar *Instellingen → Netwerk → Bluetooth → Scan for devices*.
2. Kies de 8BitDo. Lukt koppelen hier niet, koppel hem dan eenmalig in
   Nickel: *Instellingen → Bluetooth*. Daar gekoppelde apparaten verschijnen
   ook in KOReader.
3. Druk op een pijltjesknop. Je ziet de melding *"Afstandsbediening klaar"*
   en de pagina slaat om.

Vanaf nu gaat het vanzelf. Start je KOReader, of wordt de Kobo wakker, dan
gaat Bluetooth aan. Zet je de 8BitDo aan, of druk je op een knop als hij
sliep, dan verbindt hij binnen een paar seconden opnieuw.

## Knoppen aanpassen

Ga naar *Instellingen → Netwerk → Bluetooth → Paired devices → [8BitDo] →
Configure key bindings*. Kies een actie (bijvoorbeeld *Reader → Next Page*),
dan **Register button**, en druk op de knop. Zo kun je ook bijvoorbeeld de
A/B-knoppen of het licht instellen.

## Problemen oplossen

- **Remote verbindt niet vanzelf.**
  1. Controleer onder *Bluetooth → Settings* of *Enable on startup*,
     *Auto-resume after wake* en *Auto-connect* aan staan.
  2. Zet de 8BitDo uit en weer aan.
- **Pagina slaat dubbel om.** Er draait nog een tweede Bluetooth-plugin.
  Kijk in *Pluginbeheer* of er naast "Kobo" nog een Bluetooth-plugin
  aanstaat.
- **Batterij.** Met Bluetooth aan gaat de Kobo niet in standby. Hij gaat
  wel gewoon in de slaapstand volgens je energie-instellingen. Lees je
  zonder remote, zet dan *Enable on startup* uit.
- **Terug naar Nickel (Kobo-leesprogramma).** Op MTK-modellen (Libra
  Colour, Clara BW/Colour) kan de Bluetooth-driver haperen als je na
  KOReader terugkeert naar Nickel. Gebeurt dat, herstart de Kobo dan één
  keer.
- **Logboek.** In `.adds/koreader/crash.log` staan regels met
  `bt-remote-setup:` en `KoboBluetooth:`.

## Mijn model wordt niet ondersteund (Sage, Clara 2E, Elipsa)

kobo.koplugin heeft alleen Bluetooth voor de Libra 2 en de MTK-modellen.
Op andere modellen laat de patch je huidige plugin aanstaan.
- **Clara 2E:** blijf bluetooth.koplugin gebruiken. Gebruik daarin
  *Diagnostics → Event map → Correct Automatically*.
- **Sage:** KOReader zet bij het starten Bluetooth uit. De bekende
  workaround is:
  1. Koppel in Nickel.
  2. Pas `koreader.sh` aan, zodat de rfkill-blokkade en `bluetoothd` niet
     worden gestopt (zie [KOReader issue #9059](https://github.com/koreader/koreader/issues/9059)).

  Dat is gevoeliger voor fouten, dus vraag het gerust als je dit model hebt.

## Ongedaan maken

1. Verwijder `.adds/koreader/patches/2-bt-remote-setup.lua` en
   `.adds/koreader/plugins/kobo.koplugin`.
2. Zet de oude plugin weer aan in *Pluginbeheer*, of zet de back-up uit
   `backups/` terug.

## Voor ontwikkelaars

- `luajit test/test_patch.lua` test de patch tegen nagebootste
  KOReader-modules (instellingen, oude plugin uitzetten, standaardknoppen,
  Nederlandse menutaal).
- `tools/update-plugin.sh [ref]` ververst de meegeleverde plugin.

Bronnen: [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin) (GPL-3.0, meegeleverd met licentie),
[bluetooth.koplugin](https://github.com/onatbas/bluetooth.koplugin),
[KOReader #9059](https://github.com/koreader/koreader/issues/9059).
