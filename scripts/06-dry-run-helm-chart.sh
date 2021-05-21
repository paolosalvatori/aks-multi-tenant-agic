#!/bin/bash
helm install pluto ../syntheticapi \
    --debug \
    --dry-run \
    --namespace pluto \
    --create-namespace \
    --set image.repository=paolosalvatori.azurecr.io/syntheticapi \
    --set image.tag=latest \
    --set nameOverride=pluto \
    --set ingress.hosts[0].host=pluto.acme.com \
    --set ingress.tls[0].hosts[0]=pluto.acme.com
#    --disable-openapi-validation 