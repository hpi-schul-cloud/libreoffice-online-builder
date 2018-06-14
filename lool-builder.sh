#! /bin/bash
# ---------------------------------------------------------------------------------------
# Preparations

# Dieses Skript ist angedacht, in einem LXContainer ausgeführt zu werden
# Die Erstellung des Docker Images muss daher auf dem Host ausgeführt werden.

echo "deb https://collaboraoffice.com/repos/Poco/ /" >> /etc/apt/sources.list.d/poco.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0C54D189F4BA284D
apt-get update

if ! grep lool /etc/passwd
then
    useradd -U -m -s /bin/bash lool
    echo 'lool ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
fi

if id | grep -v lool
then
    echo "Als lool user ausfuehren"
    exit 1
fi

sudo apt-get update
sudo apt-get install -y     \
    apt-transport-https     \
    zip                     \
    git                     \
    wget                    \
    findutils               \
    build-essential         \
    locales-all             \
    openssl                 \
    g++                     \
    libssl-dev              \
    libkrb5-dev             \
    libpng12-dev            \
    libcap-dev              \
    libpcap-dev             \
    libpam0g-dev            \
    libcunit1-dev           \
    libtool                 \
    libxinerama1            \
    libgl1-mesa-glx         \
    libfontconfig1          \
    libfreetype6            \
    libxrender1             \
    libxcb-shm0             \
    libxcb-render0          \
    libpoco*60              \
    libpoco-dev             \
    m4                      \
    automake                \
    autoconf                \
    cpio                    \
    fontconfig              \
    translate-toolkit       \
    python-polib            \
    fonts-wqy-zenhei        \
    fonts-wqy-microhei      \
    fonts-droid-fallback    \
    fonts-noto-cjk          \
    || exit 1

# use ccache binaries
if [ -d /usr/lib/ccache ]
then
    echo "Install ccache"
    sudo apt-get install -y ccache
    # Update symlinks
    sudo /usr/sbin/update-ccache-symlinks
    # Prepend ccache into the PATH
    echo 'export PATH="/usr/lib/ccache:$PATH"' | tee -a ~/.bashrc
    # Source bashrc to test the new PATH
    source ~/.bashrc
fi

if ! npm list -g | grep jake
then
    echo "Install nodejs and jake"
    wget -qO- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | bash

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

    nvm install node
    npm install -g jake
fi

# install libreoffice dependencies
sudo apt-get build-dep -y libreoffice || exit 1

git clone https://github.com/LibreOffice/online.git

echo 'Im Verzeichnis $HOME/online/docker liegt die nightly-build Datei "l10n-docker-nightly.sh".'
echo 'Die folgende Datei $HOME/online/docker/lool-build.sh basiert auf der nightly-build Datei.'
echo 'Also diese Datei vorher mit der nightly-build Datei manuell abgleichen!'
echo
echo 'Im Wesentlichen wird die nightly-build Datei um die compile Optionen:'
echo '--with-max-connections=100000 --with-max-documents=100000 erweitert'
echo 'Auch wird auf das Erstellen des docker images verzichtet'

cat <<'MYEOF' > $HOME/online/docker/lool-build.sh
#! /bin/bash
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# check we can sudo without asking a pwd
echo "Trying if sudo works without a password"
echo
echo "If you get a password prompt now, break, and fix your setup using 'sudo visudo'; add something like:"
echo "yourusername ALL=(ALL) NOPASSWD: ALL"
echo
sudo echo "works"

# check if we have jake
which jake || { cat << EOF
jake is not installed, get it like:
  npm install -g jake
EOF
exit 1 ; }

# do everything in the builddir
SRCDIR=$(realpath `dirname $0`)
INSTDIR="$SRCDIR/instdir"
BUILDDIR="$SRCDIR/builddir"

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

rm -rf "$INSTDIR"
mkdir -p "$INSTDIR"

##### cloning & updating #####

# libreoffice repo
if test ! -d libreoffice ; then
    git clone git://anongit.freedesktop.org/libreoffice/core libreoffice || exit 1
fi

( cd libreoffice && git checkout master && ./g pull -r ) || exit 1

# online repo
if test ! -d online ; then
    git clone git://anongit.freedesktop.org/libreoffice/online online || exit 1
    ( cd online && ./autogen.sh ) || exit 1
fi

( cd online && git checkout -f master && git pull -r ) || exit 1

##### LibreOffice #####

# build LibreOffice
cat > libreoffice/autogen.input << EOF
--disable-cups
--disable-dbus
--disable-dconf
--disable-epm
--disable-evolution2
--disable-ext-nlpsolver
--disable-ext-wiki-publisher
--disable-firebird-sdbc
--disable-gio
--disable-gstreamer-0-10
--disable-gstreamer-1-0
--disable-gtk
--disable-gtk3
--disable-kde4
--disable-odk
--disable-online-update
--disable-pdfimport
--disable-postgresql-sdbc
--disable-report-builder
--disable-scripting-beanshell
--disable-scripting-javascript
--disable-sdremote
--disable-sdremote-bluetooth
--enable-extension-integration
--enable-mergelibs
--enable-python=internal
--enable-release-build
--with-external-dict-dir=/usr/share/hunspell
--with-external-hyph-dir=/usr/share/hyphen
--with-external-thes-dir=/usr/share/mythes
--with-fonts
--with-galleries=no
--with-lang=ALL
--with-linker-hash-style=both
--with-system-dicts
--with-system-zlib
--with-theme=colibre
--without-branding
--without-help
--without-java
--without-junit
--with-myspell-dicts
--without-package-format
--without-system-cairo
--without-system-jars
--without-system-jpeg
--without-system-libpng
--without-system-libxml
--without-system-openssl
--without-system-poppler
--without-system-postgresql
EOF

( cd libreoffice && ./autogen.sh ) || exit 1
( cd libreoffice && make ) || exit 1

# copy stuff
mkdir -p "$INSTDIR"/opt/
cp -a libreoffice/instdir "$INSTDIR"/opt/libreoffice

##### loolwsd & loleaflet #####

# build
( cd online && ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-silent-rules --with-lokit-path="$BUILDDIR"/libreoffice/include --with-lo-path="$INSTDIR"/opt/libreoffice --with-max-connections=100000 --with-max-documents=100000 ) || exit 1
( cd online/loleaflet/po && ../../scripts/downloadpootle.sh )
( cd online/loleaflet && make l10n) || exit 1
( cd online && scripts/locorestrings.py "$BUILDDIR"/online "$BUILDDIR"/libreoffice/translations )
( cd online && scripts/unocommands.py --update "$BUILDDIR"/online "$BUILDDIR"/libreoffice )
( cd online && scripts/unocommands.py --translate "$BUILDDIR"/online "$BUILDDIR"/libreoffice/translations )
( cd online && make -j 8) || exit 1

# copy stuff
( cd online && DESTDIR="$INSTDIR" make install ) || exit 1

echo
echo 'OK'
echo

# Create new docker image

echo '# Wenn Docker auf dem Server laeuft'
echo 'cd /var/lib/lxd/containers/loolbuilder/rootfs/home/lool/online/docker'
echo
echo '# Wenn Docker im LXC lauffaehig ist'
echo 'cd /home/lool/online/docker'
echo
echo 'export SRCDIR=$(pwd)'
echo 'export INSTDIR="$SRCDIR/instdir"'
echo 'export BUILDDIR="$SRCDIR/builddir"'

echo 'cd "$SRCDIR"'
echo 'TAGSHORT="schulcloud/libreoffice"'
echo 'TAG="$TAGSHORT:latest"'
echo 'dockerid="$(docker build -q --no-cache -t "$TAG" . )" || exit 1'
echo 'echo $dockerid'
echo 'docker save "${TAGSHORT}" |xz > "${BUILDDIR}/docker-image-libreoffice-online.tar.xz"'
echo 'echo "${dockerid}" > "${BUILDDIR}/docker-image-libreoffice-online.id"'
echo 'docker login'
echo 'docker push $TAG'
MYEOF

bash $HOME/online/docker/lool-build.sh