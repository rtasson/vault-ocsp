#!/bin/bash
# This is a simple integration test with Vault and vault-ocsp. This script requires
# vault, jq, and openssl. It also requires vault-ocsp to be built in the pwd.

# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\n\t'

# show every command
set -x

# sanity check. cleanup will remove certificates.
if [ -e *pem ] ; then 
  echo "certificates exist in pwd; this script is not safe to proceed. bailing."
  exit 1
fi

# sanity check. this script will modify a running vault instance.
set +e
ps ax | grep -v grep | grep vault
if [ $? -ne 1 ] ; then
  echo "vault or vault-ocsp appear to be running already; this script is not safe to run. bailing."
  exit 1
fi
set -e

# cleanup
function cleanup() {
  rm -f public.pem private.pem leaf.json leaf.pem root.json root.pem
  killall vault vault-ocsp
  sleep 1
}

# cleanup for any exit
trap cleanup EXIT

# start vault development server & instantiate certificates
export VAULT_ADDR='http://127.0.0.1:8200'
vault server -dev &
sleep 1
vault secrets enable pki
vault write pki/config/urls ocsp_servers="http://127.0.0.1:8080"
vault write -format json pki/root/generate/internal common_name=root ttl=8000 > root.json
root_contents=$(jq -r .data.certificate root.json)
echo "${root_contents}" > root.pem
vault write pki/roles/test allow_any_name=true
vault write -format json pki/issue/test common_name=leaf ttl=7000 > leaf.json
leaf_contents=$(jq -r .data.certificate leaf.json)
echo "${leaf_contents}" > leaf.pem

# generate temporary keys
openssl genrsa -out private.pem 4096
openssl req -new -x509 -key private.pem -out public.pem -subj "/CN=test"

# actually run the thing
export VAULT_ADDR=http://127.0.0.1:8200
./vault-ocsp -responderCert public.pem -responderKey private.pem & 
sleep 1

# check certificate status
openssl ocsp -issuer root.pem -cert leaf.pem -url http://127.0.0.1:8080 -no_cert_verify -resp_text | grep "Cert Status: good"

# revoke cert and check that vault-ocsp responded correctly
vault write pki/revoke serial_number=$(jq -r .data.serial_number leaf.json)
set +e
openssl ocsp -issuer root.pem -cert leaf.pem -url http://127.0.0.1:8080 -no_cert_verify -resp_text | grep "Cert Status: revoked"
if [ $? -ne 0 ]; then
  echo "vault-ocsp failed to report the certificate revocation status correctly; failed."
fi

echo "Success!"
