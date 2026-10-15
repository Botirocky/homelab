#pragma once

#if __has_include("titkok.h")
#include "titkok.h"
#endif

#ifndef WIFI_SSID
#define WIFI_SSID "A_TE_WIFID"
#endif
#ifndef WIFI_JELSZO
#define WIFI_JELSZO "A_TE_JELSZAVAD"
#endif
#ifndef WEB_KULCS
#define WEB_KULCS ""
#endif
#ifndef GEPEK_KULCS
#define GEPEK_KULCS ""
#endif

#define GEPNEV "ebreszto"
#define GEPEK_URL "http://192.168.1.185:8097/gepek"

#define LAPTOP_NEV "Laptop"
#define LAPTOP_HOST "botirocky-linux"
#define LAPTOP_IP "192.168.1.171"
#define LAPTOP_MAC_WIFI "aa:bb:cc:00:00:02"
#define LAPTOP_MAC_KABEL "aa:bb:cc:00:00:03"

#define EBRESZTES_MAX_MP 120
#define VM_MAX_MP 90
#define ALLAPOT_MP 10
#define KIJELZO_ALVAS_MP 90

#define GOMB_FEL 26
#define GOMB_LE 25
#define GOMB_OK 15
#define GOMB_MOD 13
#define BUZZER_PIN 4
#define NEOPIXEL_TAP 2
#define NEOPIXEL_LAB 0
#define NEOPIXEL_FENY 30

#define OLED_RST 14
#define OLED_CIM 0x3C

#define PI_IP "192.168.1.185"
#define EJSZAKA_URL "http://192.168.1.185:8097/ejszaka"
#define EJSZAKA_ALAP_LEALL (22 * 60)
#define EJSZAKA_ALAP_EBRESZT (8 * 60)
#define LEALL_ABLAK_PERC 30
#define EBRESZT_ABLAK_PERC 60
#define PI_EBRESZTO_PIN 32
#define PI_PROBA_MAX 3
#define PI_PROBA_MP 120

#define EJJEL_TOL 22
#define EJJEL_IG 7
#define TZ_INFO "CET-1CEST,M3.5.0,M10.5.0/3"
