# AG Life

App personale SwiftUI per iPhone, iOS 17+. Nessun account, cloud, SDK esterno o dato personale nel repository.

## Pensieri fissati e promemoria · 0.4.0

Pressione prolungata su un pensiero → **Fissa in alto** / **Rimuovi dai fissati**. La scheda Pensieri separa i fissati dagli altri, sempre ordinati per ultima modifica; la Home mostra fino a tre fissati e tre recenti non fissati. Il fissaggio non cambia testo o data e viene conservato anche dopo la modifica del testo. Nessun titolo reintrodotto.

Nel modulo impegni, **Avvisami** abilita la scelta: all’ora dell’impegno, 5 minuti, 15 minuti, 1 ora o 1 giorno prima (24 ore di anticipo). Il primo utilizzo spiega la finalità e richiede il permesso iOS. Si può salvare un impegno anche negandolo: il calendario segnala che il promemoria non è programmato. Le date degli avvisi trascorse o troppo vicine non producono avvisi immediati.

`NotificationService` usa solo UserNotifications: richieste non ripetute, ID stabili per impegno, sostituzione su modifica, annullamento su disattivazione/eliminazione, verifica delle richieste in attesa dopo l’aggiunta. Un solo worker seriale riconcilia l’ultimo stato salvato, anche al rientro in primo piano, senza chiedere automaticamente permessi all’avvio. Rimuove solo le richieste con il prefisso AG Life. Sono gestiti fino a 60 promemoria futuri più vicini (meno se ci sono altre richieste dell’host); quelli esclusi sono segnalati e vengono rivalutati alla prossima apertura/modifica. Non esiste un servizio che estende questa finestra mentre l’app è chiusa.

L’archivio JSON passa a versione 3: `isPinned` mancante diventa `false`, `reminder` mancante resta disattivato. Nessuna notifica viene generata per i vecchi impegni senza esplicita attivazione. Lettura senza riscrittura e copia byte per byte dell’originale in `life.json.pre-v3-backup` prima del primo salvataggio di un archivio v1/v2. Se la copia fallisce, il salvataggio si ferma. Copie già presenti non vengono sovrascritte. UUID, date e contenuti restano invariati; il Bundle Identifier resta **`com.aglife.personal`**, confermato dall’utente. Aggiornare nello stesso contenitore LiveContainer, senza tornare alle versioni precedenti sull’archivio v3.

### Prova notifiche su iPhone / LiveContainer

Home → ingranaggio → **Impostazioni → Invia notifica di prova**. La richiesta è per circa 10 secondi; invii ripetuti sostituiscono il test precedente. Ripetere il test in tre condizioni: AG Life aperta, LiveContainer in background, iPhone bloccato. Il delegate richiede la presentazione anche in primo piano. “Richiesta accettata da iOS” conferma l’accodamento, non la ricezione. Verificare permessi iOS/host, Full immersion e riepilogo programmato; un permesso autorizzato può comunque avere banner o suoni disabilitati.

LiveContainer documenta **Fix Local Notification** nelle impostazioni specifiche dell’app ospite: abilitarlo se necessario, riaprire AG Life e ripetere il test. L’opzione può avere un nome diverso nelle varie versioni. Non vengono aggiunti entitlement push, modifiche all’host, tweak o workaround. Se il test non arriva, considerare i promemoria non affidabili in quella configurazione. La prova reale in primo piano/background/blocco resta necessaria anche dopo una build riuscita. Fonti: [LiveContainer](https://github.com/LiveContainer/LiveContainer#fix-file-picker--local-notification), [permessi Apple](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)), [richieste in attesa](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/pendingnotificationrequests()).

Verificare inoltre: fissare/sfissare e riaprire l’app; modificare un pensiero fissato; salvare un impegno senza permesso; programmare un avviso futuro, spostarlo, disattivarlo ed eliminare l’impegno controllando che il vecchio avviso non arrivi; provare anticipi già trascorsi. I test automatici coprono retrocompatibilità v1/v2, backup non sovrascritti, nuovi campi, round trip e calcolo date/ID. La consegna delle notifiche va verificata sul dispositivo.

## Restyling Fresh Life · 0.3.0

Design system SwiftUI condiviso in `Views/DesignSystem.swift`: palette adattiva chiara/scura (turchese, indaco, corallo), superfici, campi, intestazioni, pulsanti e stati vuoti. Home ridisegnata con header editoriale, saldo a gradiente, riepiloghi mensili, azioni rapide e card agenda/pensieri. Le altre schede mantengono ricerca, selezione mese/giorno e swipe per eliminare con conferma.

Gli editor usano superfici personalizzate in ScrollView, etichette permanenti, selettori iOS e pulsante Salva in basso, disponibile anche con tastiera aperta. Nessuna modifica al formato dati o alla persistenza; conservati pensieri senza titolo, migrazione dei titoli precedenti, feedback tattili e Riduci movimento. Bundle identifier e requisiti LiveContainer invariati. Nessun asset remoto o dipendenza aggiunta.

Verificare su iPhone: temi chiaro/scuro, contrasto e VoiceOver, testo ingrandito, inserimento con tastiera, picker data/categoria e conferme di eliminazione. La build macOS verifica compilazione e test del nucleo; non sostituisce il controllo visivo e tattile sul dispositivo.

## Aggiornamento interfaccia e pensieri

La Home offre due grandi pulsanti affiancati per spese e impegni e un pulsante a tutta larghezza per i pensieri. Con le dimensioni di testo di accessibilità i pulsanti si dispongono verticalmente. Feedback di pressione discreto e animazioni disabilitate con Riduci movimento; feedback tattile di sistema all’inserimento rapido e dopo salvataggi/eliminazioni riusciti, dove supportato dal dispositivo.

I pensieri contengono solo testo, con anteprima e data/ora dell’ultima modifica automatiche. La creazione apre la tastiera nel testo; la modifica non forza la tastiera. I titoli precedenti vengono incorporati integralmente nel corpo, separati da una riga vuota, conservando UUID e data originali. L’archivio v1 viene letto senza riscriverlo e salvato atomicamente come v2 alla prima modifica riuscita. Non usare la vecchia versione dell’app sull’archivio v2.

La Home mostra fino a tre impegni di oggi (prima quelli ancora da iniziare, poi i più recenti già iniziati) e due dei prossimi sette giorni, con accesso al calendario completo. Il riepilogo si aggiorna ogni minuto mentre la Home è visibile.

I test del workflow coprono migrazione, ripetibilità dopo salvataggio/riavvio, titoli senza corpo, Unicode, identità e date, conservazione degli altri dati e limiti del riepilogo impegni. Su iPhone verificare tastiera, VoiceOver, testo ingrandito, Riduci movimento e feedback tattili. Per aggiornare in LiveContainer mantenere lo stesso contenitore dell’app e bundle identifier.

## Funzionalità

- **Home:** entrate, uscite e saldo del mese, impegni di oggi e imminenti, ultimi tre pensieri e inserimento rapido.
- **Spese:** creazione, modifica ed eliminazione dei movimenti, selezione mese, categorie, descrizione e data. Importi EUR in `Decimal`, massimo due decimali.
- **Calendario:** selezione giorno, creazione, modifica ed eliminazione degli impegni. Calendario interno, senza notifiche o sincronizzazione Apple.
- **Pensieri:** creazione, modifica, ricerca ed eliminazione con conferma, ordinati per ultima modifica.
- Interfaccia nativa con schede inferiori, colori di sistema, modalità chiara/scura automatica e pulsanti di inserimento in basso.

## Architettura

`AGLife/App` contiene l’avvio; `Models` i modelli Codable e il calcolo dei totali; `Persistence` l’archivio e lo stato osservabile; `Views` le schermate e gli editor. `AGLife.xcodeproj` include lo schema condiviso. Nessun generatore o pacchetto esterno.

Le viste condividono `LifeStore` sul main actor. Ogni modifica viene salvata prima di aggiornare lo stato visibile. Archivio JSON versionato in `Application Support/AGLife/life.json`, con scrittura atomica. Se il caricamento fallisce, il file viene conservato e le modifiche bloccate; se il salvataggio fallisce, lo stato precedente resta valido e l’editor rimane aperto. I/O sincrono adeguato al piccolo archivio iniziale; per grandi volumi servirà spostarlo in background.

I dati restano nel contenitore dell’app, gestito da LiveContainer quando eseguita al suo interno. Non esiste ancora esportazione/backup dall’interfaccia: cancellare app o contenitore può cancellare i dati. Per gli aggiornamenti mantenere lo stesso bundle identifier e contenitore. Il JSON non aggiunge cifratura applicativa.

## Windows e compilazione

Su Windows si modificano sorgenti e configurazione. Xcode e SDK iOS richiedono macOS: compilazione SwiftUI, simulatore e generazione IPA devono essere eseguiti sul runner o su Mac.

Il workflow **Build AG Life IPA** usa `macos-15` e Xcode preinstallato (serve Xcode 16+ per i gruppi sincronizzati). Si avvia manualmente o su modifiche a `main`/pull request. Non richiede Apple ID, certificati o secret e non modifica il repository.

1. Dopo commit e push autorizzati, aprire **Actions → Build AG Life IPA → Run workflow**. Per l’avvio manuale il workflow deve essere nel branch predefinito.
2. Il runner valida il progetto, esegue i test di `Tests/CoreTests.swift`, compila Release per iPhone arm64 con firma disabilitata e impacchetta `Payload/AGLife.app`.
3. Scaricare l’artefatto **AGLife-unsigned-IPA**, conservato per 7 giorni, dalla pagina della run.
4. Estrarre lo ZIP esterno: contiene `AGLife-unsigned.ipa` e il checksum SHA-256. Non rinominare lo ZIP esterno in IPA.

Non si usa `xcodebuild -exportArchive`: il pacchetto è intenzionalmente privo di firma e non si installa direttamente da iOS. Il workflow controlla struttura ZIP e architettura arm64.

GitHub Actions ha quote e condizioni legate all’account, specialmente per repository privati e runner macOS. Non viene attivato un servizio a pagamento: controllare le quote e tenere disabilitata la spesa aggiuntiva nelle impostazioni GitHub.

## LiveContainer e SideStore

Installare/configurare LiveContainer secondo le istruzioni ufficiali, usando SideStore dove previsto. Importare quindi `AGLife-unsigned.ipa` in LiveContainer. SideStore gestisce firma e rinnovo dell’host; LiveContainer gestisce caricamento ed eventuale firma dell’app ospite. In alternativa SideStore può firmare l’IPA per installazione diretta, con i propri limiti.

Non vengono richiesti App Groups, iCloud, push, estensioni o altre capacità con entitlement dedicati. Questo riduce i vincoli, ma la compatibilità effettiva va verificata sulla combinazione iOS/LiveContainer utilizzata. AG Life non richiede JIT per il proprio codice; il metodo di caricamento dell’host dipende dalla sua configurazione JIT/JIT-less. Non aggiungere certificati, credenziali o pairing file al repository.

Riferimenti: [LiveContainer e limitazioni](https://github.com/LiveContainer/LiveContainer), [installazione](https://livecontainer.github.io/docs/installation), [problemi di firma](https://livecontainer.github.io/docs/faq/installing-livecontainer), [download artefatti GitHub](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts).

## Verifiche macOS e iPhone

Test del nucleo su macOS, eseguiti anche nel workflow:

```sh
mkdir -p build
xcrun swiftc AGLife/Models/LifeData.swift AGLife/Persistence/LocalArchive.swift Tests/CoreTests.swift -o build/CoreTests
build/CoreTests
```

Coprono importi non validi, precisione decimale, totali mensili, salvataggio/lettura di tutti i modelli, modifiche, eliminazione, archivio corrotto, versione sconosciuta e scrittura fallita.

Aprire `AGLife.xcodeproj` con Xcode 16+ per il simulatore. Su iPhone verificare:

- Creare e modificare entrata/uscita, cambiare mese e controllare i totali.
- Creare un impegno, selezionare il giorno e controllare il riepilogo Home.
- Creare una nota con accenti e più righe, cercarla, modificarla e confermare l’eliminazione.
- Chiudere completamente e riaprire app/LiveContainer per verificare la persistenza.
- Provare tema chiaro/scuro, testo ingrandito, tastiera e VoiceOver.
- Aggiornare l’IPA nello stesso contenitore e verificare la conservazione dei dati.

La prima compilazione macOS, l’aspetto effettivo e l’importazione in LiveContainer richiedono ancora l’esecuzione del workflow e test su iPhone; i controlli Windows non li sostituiscono.
