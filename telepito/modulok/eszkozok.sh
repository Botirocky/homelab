#!/usr/bin/env bash

cim "Eszközök – Stirling-PDF + IT-Tools"

for d in stirling-pdf/configs stirling-pdf/tessdata; do konyvtar "${ADAT_DIR}/${d}"; done

stack_telepit eszkozok
stack_indit eszkozok

vhost_ir "68-eszkozok" "http://pdf.${BELSO_DOMAIN} {
	request_body {
		max_size 2GB
	}
	reverse_proxy stirling-pdf:8080
}

http://eszkozok.${BELSO_DOMAIN} {
	reverse_proxy it-tools:80
}"

szolgaltatas_jegyzes "Stirling-PDF" "http://pdf.${BELSO_DOMAIN}"      "PDF összefűzés, vágás, OCR, aláírás – helyben"
szolgaltatas_jegyzes "IT-Tools"     "http://eszkozok.${BELSO_DOMAIN}" "base64, hash, JWT, cron, UUID, …"

:
