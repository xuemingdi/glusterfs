#!/bin/bash

. $(dirname $0)/../include.rc
. $(dirname $0)/../volume.rc

ping_file () {
        echo hello > $1 2> /dev/null
}
for d in /etc/ssl /etc/openssl /usr/local/etc/openssl ; do
        if test -d $d ; then
                SSL_BASE=$d
                break
        fi
done
SSL_KEY=$SSL_BASE/glusterfs.key
SSL_CERT=$SSL_BASE/glusterfs.pem
SSL_CA=$SSL_BASE/glusterfs.ca

cleanup;
rm -f $SSL_BASE/glusterfs.*
mkdir -p $B0/1
mkdir -p $M0

TEST glusterd
TEST pidof glusterd
TEST $CLI volume info;

# Construct a cipher list that excludes CBC because of POODLE.
# http://web.nvd.nist.gov/view/vuln/detail?vulnId=CVE-2014-3566
#
# Since this is a bit opaque, here's what it does:
#	(1) Get the ciphers matching a normal cipher-list spec
#	(2) Delete any colon-separated entries containing "CBC"
#	(3) Collapse adjacent colons from deleted entries
#	(4) Remove colons at the beginning or end
function valid_ciphers {
	openssl ciphers 'HIGH:!SSLv2' | sed	\
		-e '/[^:]*CBC[^:]*/s///g'	\
		-e '/::*/s//:/g'		\
		-e '/^:/s///'			\
		-e '/:$/s///'
}

TEST openssl genrsa -out $SSL_KEY 1024
TEST openssl req -new -x509 -key $SSL_KEY -subj /CN=Anyone -out $SSL_CERT
ln $SSL_CERT $SSL_CA

TEST $CLI volume create $V0 $H0:$B0/1
TEST $CLI volume set $V0 server.ssl on
TEST $CLI volume set $V0 client.ssl on
#EST $CLI volume set $V0 ssl.cipher-list $(valid_ciphers)
#EST $CLI volume set $V0 auth.ssl-allow Anyone
TEST $CLI volume start $V0

# This mount should WORK.
TEST glusterfs --volfile-server=$H0 --volfile-id=$V0 $M0
TEST ping_file $M0/before
EXPECT_WITHIN $UMOUNT_TIMEOUT "Y" force_umount $M0

# Change the authorized user name.  Note that servers don't pick up changes
# automagically like clients do, so we have to stop/start ourselves.
TEST $CLI volume stop $V0
#EST $CLI volume set $V0 auth.ssl-allow NotYou
TEST $CLI volume start $V0

# This mount should FAIL because the identity given by our certificate does not
# match the allowed user.  In other words, authentication works (they know who
# we are) but authorization doesn't (we're not the right person).
#EST $GFS --volfile-server=$H0 --volfile-id=$V0 $M0

# Looks like /*/bin/glusterfs isn't returning error status correctly (again).
# Actually try doing something to get a real error.
#EST ! ping_file $M0/after

cleanup;