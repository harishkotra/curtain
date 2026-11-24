GNOKEY  ?= gnokey
REMOTE  ?= https://rpc.onyx.testnets.gno.land
CHAINID ?= onyx-1
KEY     ?= curtain

test:
	gno test ./gno.land/p/curtain/groth16/ ./gno.land/r/curtain/

deploy-verifier:
	$(GNOKEY) maketx addpkg -pkgpath gno.land/p/curtain/groth16 \
	  -pkgdir ./gno.land/p/curtain/groth16 -gas-fee 1000000ugnot \
	  -gas-wanted 200000000 -broadcast -chainid $(CHAINID) -remote $(REMOTE) $(KEY)

deploy-realm:
	$(GNOKEY) maketx addpkg -pkgpath gno.land/r/curtain \
	  -pkgdir ./gno.land/r/curtain -gas-fee 1000000ugnot \
	  -gas-wanted 200000000 -broadcast -chainid $(CHAINID) -remote $(REMOTE) $(KEY)

.PHONY: test deploy-verifier deploy-realm
