# Keys

Tag page:
https://git.zx2c4.com/cgit/tag/?h=v1.3

~~~bash
# Inspect the signature packet and extract key information
curl -fsSLo cgit-1.3.tar.asc https://git.zx2c4.com/cgit/snapshot/cgit-1.3.tar.asc

gpg --list-packets < cgit-1.3.tar.asc
# off=0 ctb=89 tag=2 hlen=3 plen=608
# :signature packet: algo 1, keyid 49FC7012A5DE03AE
#         version 4, created 1771897763, md5len 0, sigclass 0x00
#         digest algo 8, begin of digest fb 86
#         hashed subpkt 33 len 21 (issuer fpr v4 AB9942E6D4A4CFC3412620A749FC7012A5DE03AE)
#         hashed subpkt 2 len 4 (sig created 2026-02-24)
#         hashed subpkt 20 len 26 (notation: manu=2,2.5+1.12,2,2)
#         hashed subpkt 28 len 15 (signer's user ID)
#         subpkt 16 len 8 (issuer key ID 49FC7012A5DE03AE)
#         data: [4093 bits]

# Fetch the public key
gpg --keyserver hkps://keys.openpgp.org --recv-keys 49FC7012A5DE03AE

# Verify fingerprint
gpg --fingerprint 49FC7012A5DE03AE
# pub   rsa4096 2011-01-15 [SC] [expires: 2027-03-31]
#       AB99 42E6 D4A4 CFC3 4126  20A7 49FC 7012 A5DE 03AE
# uid           [ unknown] Jason A. Donenfeld <Jason@zx2c4.com>
# sub   rsa4096 2011-01-15 [E] [expires: 2027-03-31]

# Export
mkdir -p keys
gpg --export --armor 49FC7012A5DE03AE > jason.asc

gpg --show-keys jason.asc
# pub   rsa4096 2011-01-15 [SC] [expires: 2027-03-31]
#       AB9942E6D4A4CFC3412620A749FC7012A5DE03AE
# uid                      Jason A. Donenfeld <Jason@zx2c4.com>
# sub   rsa4096 2011-01-15 [E] [expires: 2027-03-31]
~~~