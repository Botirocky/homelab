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
#ifndef NTFY_TEMA
#define NTFY_TEMA ""
#endif
#ifndef DISCORD_WEBHOOK
#define DISCORD_WEBHOOK ""
#endif
#ifndef WEB_KULCS
#define WEB_KULCS ""
#endif

#define GEPNEV "orszem"
#define PI_NEV "picloud"
#define PI_CIM "192.168.1.185"
#define ALLAPOT_URL "http://192.168.1.185/allapot.json"
#define PI_SSH_PORT 22
#define NTFY_SZERVER "https://ntfy.sh/"

#define ELLENORZES_MP 15
#define ELAVULT_MP 180
#define KIESES_MP 120
#define FIGY_MP 300
#define EMLEKEZTETO_PERC 10

#define GOMB_FEL 26
#define GOMB_LE 25
#define GOMB_OK 15
#define GOMB_MOD 13
#define BUZZER_PIN 4
#define NEOPIXEL_TAP 2
#define NEOPIXEL_LAB 0
#define NEOPIXEL_FENY 25

#define OLED_RST 14
#define OLED_CIM 0x3C

#define RACK_MELEG_C 40.0
#define PI_MELEG_C 75.0

#define EJJEL_TOL 22
#define EJJEL_IG 7
#define TZ_INFO "CET-1CEST,M3.5.0,M10.5.0/3"
