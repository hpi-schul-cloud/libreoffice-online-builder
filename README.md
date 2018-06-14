# Libreoffice Online Docker Image Builder

hier wird beschrieben wie man sich aus dem offiziel verfügbaren aber limitierten Libreoffice Online eine Version bauen kann, die unbegrenzt Dokumente und Verbindungen zulässt.

## Wie das Ganze so funktioniert

Ziel des Ganzen ist es, von Libreoffice-Online ein Docker Image zu bauen. Dazu wird der Libreoffice Source-Code ausgecheckt, konfiguriert, kompiliert und daraus schliesslich ein Docker Image erstellt.

Das Ganze kann in einer virtuellen Machine passieren oder in einem Linux Container (von letzterem wird hier ausgegangen). In dem LXC müssen alle nötigen Pakete zum Kompilieren des Source-Codes installiert werden. Das Kompilieren darf jedoch nicht von `root` ausgeführt werden, sondern von einem User mit `sudo` Rechten - aber auch nicht _irgendeinem_ User, sondern dem `lool` User (zum Teil geht das `Makefile` von einem solchen User aus).

Das `lool-builder.sh` Skript besteht aus zwei Teilen. Im ersten Schritt wird der User angelegt und die nötigen Pakete istalliert. Im zweiten Schritt wird in einem bestimmten Pfad im (frisch geklonten) Libreoffice-Online Repository das _eigentliche Buildskript_ ausgeführt.

Da im LXC kein Docker ausgeführt werden kann - _wenn auf dem Server selbst schon ein Docker Daemon läuft_ (was bei mir der Fall ist) - muss das eigentliche Erstellen des Docker Image auf dem Server passieren.

## Anpassungen
Vorab: Einfach das `lool-builder.sh` Skript so durchlaufen zu lassen __funktioniert NICHT__.

Weil: Im Verlauf des Image bauen wird das tageasaktuelle libreoffice-core und libreoffice-online git-Repository geklont und der _master_ ausgecheckt. Der Source-Code beider Repositories wird im Laufe dessen konfiguriert und kompiliert. Das bedeutet aber eben auch, dass sich die Konfigurations- und Kompililierungs-Optionen ändern können.

Ergo, es __muss__ vor dem Image bauen das `lool-builder.sh` Skript angepasst werden. Aber auch die Wahl des Betriebssystem ist nicht willkürlich.

Und wie? na man schaut sich das [Nightly Build Skript] von libreoffice-online an.

Im Grossen und Ganzen kann man dieses [Nightly Build Skript] kopieren und im `lool-builder.sh` Skript verwenden. Und zwar ab der Stelle im Code: 
```
#!/bin/bash
# This file is part of the LibreOffice project.
```
Bis zur Stelle:
```
# Create new docker image
```
Natürlich müssen noch zwei Konfigurations-Optionen hinzugefügt werden (was ja der Grund für den ganzen Spass ist). An der Stelle (im Original):
```
( cd online && ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-silent-rules --with-lokit-path="$BUILDDIR"/libreoffice/include --with-lo-path="$INSTDIR"/opt/libreoffice ) || exit 1
```
müssen noch die Optionen `--with-max-connections=100000 --with-max-documents=100000` hinzugefügt werden.

Ach, und es macht durchaus Sinn auch das [Dockerfile] sich anzuschauen (auf diese Weise konnte ich erfahren, wie libreoffice mit den `libpoco` Libraries umgeht - die entsprechenden `libpoco-dev` Pakete müssen natürlich im LXC auch installiert werden).

## Betriebssystem

Das Bauen des Images erfolgt mit dem [Dockerfile] des Libreoffice-Online Repository. 
Da eben Libreoffice-Online in dem Docker Container laufen wird, sollte der Libreoffice Source-Code auf demselben Betriebssystem und mit denselben Libraries kompiliert werden.

Im Dockerfile steht an erster Stelle, welches Betriebssystem genutzt werden sollte (aktuell Ubuntu:16.04)

## Ablauf

- Der Linux Container wird gestartet mit `lxc launch ubuntu:16.04 loolbuilder -c security.privileged=true`

- Kopiere das `lool-builder.sh` Skript in den LXC `sudo cp lool-builder.sh /var/lib/lxd/containers/loolbuilder/rootfs/root`

- Wechsle in den LXC `lxc exec loolbuilder /bin/bash`

- Führe, zunächst als `root`, das Skript aus: `bash lool-builder.sh`.
  Das erstellt den `lool` User und verschiebt das `lool-builder.sh` Skript.

- Werde zu `lool` User: `su - lool` und führe das Skript aus: `bash lool-builder.sh`
  Ab nun kann es etwas dauern. Aktuell läuft das Skript bis zum Ende ohne Probleme durch. __Aber!__ Es hat noch während der Entwicklung des Skripts des Öfteren Laufabbrüche gegeben, wenn z.B. benötigte Libraries fehlten. Auch konnte beobachtet werden, dass beim Kompilieren des Libreoffice-Online (loleaflet), es zu Fehlern im Zusammenhang mit `sudo /sbin/setcap cap_sys_admin=ep loolmount;` bzw. `sudo /sbin/setcap cap_fowner,cap_mknod,cap_sys_chroot=ep loolforkit;` kommt. Das konnte ich nie richtig nachvollziehen, da beim _erneuten_ Aufruf des Skriptes diese Schritte erfolreich waren.

- Wenn alles soweit durchläuft und das letzte 'OK' erscheint, ist die Arbeit im LXC getan.

- Erstelle das Docker Image. Am Ende des Skripts erscheinen die Anweisungen, wie das ablaufen kann. 
  Das kann auf dem Server oder im LXC passieren, je nach dem wo der Docker Daemon läuft. Schliesslich muss das Docker Image nach `schulcloud/libreoffice:latest` gepusht werden. Dazu braucht man natürlich einen Docker Account und die entsprechenden Berechtigungen (Ist das nicht gegeben, dann wird zumindest das Docker Image als `docker-image-libreoffice-online.tar.xz` im `builddir` gespeichert).

## Docker Container

Um den Docker Container zum Laufen zu bekommen, muss zunächst das Docker Image gepullt werden `docker pull schulcloud/libreoffice:latest`

Die Doku von [collaboraoffice.com] ist recht hilfreich zum Starten des Docker Containers, insbesondere für die vielen Optionen, die dabei gesetzt werden können. Es heisst dort u.a.:

> If you need to tweak other parameters of CODE, you can edit the configuration file /etc/loolwsd/loolwsd.xml in the Docker image

Na Klasse, __im__ Container! Aber da gibt es einen recht einfachen Workaround. Starte den Container mit: 
```
docker run -it -v $(pwd)/data:/data \
    -p 127.0.0.1:9980:9980 \
    -e "domain=<your-dot-escaped-domain>" \
    -e "username=admin" \
    -e "password=S3cRet" \
    --restart always --cap-add MKNOD --rm schulcloud/libreoffice:latest
```
Wechle in den Docker Container mit `docker exec -it <container-id> /bin/bash`
Kopiere das gesamte `/etc/loolwsd` Verzeichnis nach `/data`. Gehe raus aus dem Container und stoppe ihn.

Nun kann die `/etc/loolwsd/loolwsd.xml` Datei in aller Seelnruhe bearbeitet werden, inbesondere
die SSL settings dürften interessant sein.

Jetzt kann der Docker Container mit den neuen Optionen gestartet werden.
```
docker run -t -d -v $(pwd)/data:/etc/loolwsd \
    -p 127.0.0.1:9980:9980 \
    -e "domain=<your-dot-escaped-domain>" \
    -e "username=admin" \
    -e "password=S3cRet" \
    --restart always --cap-add MKNOD schulcloud/libreoffice:latest
```
In diesem Repo habe ich zwar schon dieses Prozedere vorbereitet und einige Anpassungen an die `/etc/loolwsd/loolwsd.xml` Datei gemacht, __aber__ das ist ja nichts unbedingt für die Zukunft (wer weiss, was sich noch ändern wird)

---
[Nightly Build Skript]: https://github.com/LibreOffice/online/blob/master/docker/l10n-docker-nightly.sh

[Dockerfile]: https://github.com/LibreOffice/online/blob/master/docker/Dockerfile

[collaboraoffice.com]: https://www.collaboraoffice.com/code/
