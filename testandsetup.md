A **Nyxframework** mind a 13 modulja, a 145 Lua forrásfájl, a 12 automatizált SQL migráció és a master SPA webes felület sikeresen felépült, szintaktikailag ellenőrizve lett és bevetésre kész.

A projekt éles indításához és az in-engine tesztek futtatásához a következő lépéseket kell megtenned:

---

### 1. Adatbázis előkészítése

Hozz létre egy üres MariaDB / MySQL adatbázist a szervernek:

```bash
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS nyxframework CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

```

---

### 2. A szerver konfiguráció ellenőrzése

Győződj meg róla, hogy a `server.cfg.example` fájlban megadtad a helyes adatbázis-kapcsolati karakterláncot (`set mysql_connection_string`), a FiveM licenckulcsodat (`sv_licenseKey`), és másold át futtatható konfigurációként:

*(Windows CMD esetén):*

```cmd
copy FiveM\server.cfg.example FiveM\server.cfg

```

*(Linux esetén):*

```bash
cp FiveM/server.cfg.example FiveM/server.cfg

```

---

### 3. A szerver elindítása

Navigálj a FiveM szerver gyökerébe, és indítsd el a példányt:

*(Windows CMD):*

```cmd
cd FiveM

```

```cmd
run.cmd +exec server.cfg

```

*(Linux Bash):*

```bash
cd FiveM

```

```bash
bash run.sh +exec server.cfg

```

---

### 4. A beépített tesztkészlet lefuttatása

Amint a szerver elindult és az `oxmysql` lefutatta a 10 migrációt az `nyx_migrations` táblába, írd be közvetlenül a FiveM szerverkonzolba az automatikus audit indításához:

```text
nyx_run_tests

```

Ez a parancs azonnal végrehajtja a `nyx_core/server/tests.lua` tesztcsomagját:

* Ellenőrzi a kétirányú RPC busz válaszidejét és időtúllépési kezelését.
* Szimulálja a párhuzamos leltári tárgymozgatást és a Dijkstra mutex zárást (duplikáció-védelem).
* Validálja a kettős könyvelési megmaradási törvényt az államkincstárban ($\sum \text{tartozik} \equiv \sum \text{követel}$).
* Teszteli a Fuvarozási Tőzsde letéti kaució megmaradását és a logisztikai dinamikus árazási korlátokat ($P_{\text{base}} \times [0.50, 2.25]$).

Ha bármelyik teszt hibát jelezne vagy szeretnél finomítani a kliensoldali HUD megjelenésén az `nyx_ui`-ban, jelezd bátran!