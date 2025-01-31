#!/usr/bin/with-contenv bashio

echo "Hello world!"
curl -X GET -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" -H "Content-Type: application/json" http://supervisor/os/info
