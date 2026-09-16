#!/usr/bin/env sh
set -eu

apk add --no-cache \
  build-base \
  gmp-dev \
  libcap-dev \
  linux-headers \
  openssl-dev \
  wget

archive="strongswan.tar.bz2"
url="https://download.strongswan.org/$archive"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT INT TERM

cd "$workdir"

wget -O "$archive" "$url"

tar -xjf "$archive"
cd strongswan-*

./configure \
  --prefix=/usr \
  --sysconfdir=/etc \
  --libdir=/usr/lib \
  --libexecdir=/usr/lib \
  --with-ipsecdir=/etc/ipsec.d \
  --enable-charon \
  --enable-starter \
  --enable-stroke \
  --enable-kernel-netlink \
  --enable-socket-default \
  --enable-openssl \
  --enable-eap-identity \
  --enable-eap-mschapv2 \
  --enable-eap-peap \
  --enable-eap-tls \
  --enable-pem \
  --enable-pkcs1 \
  --enable-pkcs7 \
  --enable-pkcs8 \
  --enable-pubkey \
  --enable-x509 \
  --enable-constraints \
  --enable-revocation \
  --enable-random \
  --enable-nonce \
  --enable-updown

make -j"$(getconf _NPROCESSORS_ONLN)"
make DESTDIR=/out install
