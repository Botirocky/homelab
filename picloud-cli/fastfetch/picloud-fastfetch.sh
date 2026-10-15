case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
[ -n "$PICLOUD_FASTFETCH_KI" ] && return 0
[ "$SHLVL" -gt 1 ] 2>/dev/null && return 0
command -v fastfetch >/dev/null 2>&1 && fastfetch
