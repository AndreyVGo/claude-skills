#!/usr/bin/env bash
# Проверка имени по группе A: домены, история, пакеты, магазины приложений, VK.
# Всё, что здесь выводится, — результат реального запроса. Ничего не додумывать.
#
#   ./check-name.sh <имя> [зона ...]
#   ./check-name.sh zorveksa com io ru
#
# Зоны по умолчанию: com io

set -uo pipefail

NAME="${1:-}"
[ -z "$NAME" ] && { echo "usage: $0 <имя> [зона ...]" >&2; exit 2; }
shift
ZONES=("$@")
[ ${#ZONES[@]} -eq 0 ] && ZONES=(com io)

UA="domain-brand-naming/1.0"
TODAY="$(date +%Y-%m-%d)"
NAME_LC="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

code() { curl -sL -o /dev/null -w '%{http_code}' -m 15 -A "$UA" "$1" 2>/dev/null; }
body() { curl -sL -m 15 -A "$UA" "$1" 2>/dev/null; }

# whois на macOS не идёт по refer сам: спрашиваем IANA, потом сервер зоны
whois_zone() {
  local domain="$1" srv
  srv="$(whois "$domain" 2>/dev/null | awk '/^refer:/ {print $2; exit}')"
  if [ -n "$srv" ]; then
    whois -h "$srv" "$domain" 2>/dev/null
  else
    whois "$domain" 2>/dev/null
  fi
}

echo "ИМЯ: $NAME_LC   ДАТА ПРОВЕРКИ: $TODAY"
echo
echo "== ДОМЕНЫ =="
for z in "${ZONES[@]}"; do
  d="$NAME_LC.$z"
  url="https://rdap.org/domain/$d"
  hc="$(curl -sL -m 15 -A "$UA" -o "$TMP/r" -w '%{http_code}' "$url" 2>/dev/null)"
  resp="$(cat "$TMP/r" 2>/dev/null)"

  if printf '%s' "$resp" | grep -q 'No RDAP service'; then
    w="$(whois_zone "$d")"
    if [ -z "$w" ]; then
      echo "  $d — НЕ ПРОВЕРЕН (whois недоступен)"
    elif printf '%s' "$w" | grep -qiE 'No entries found|NOT FOUND|No match|Status: *free|is available|No Data Found'; then
      echo "  $d — СВОБОДЕН | источник: WHOIS $(printf '%s' "$w" | head -1 | cut -c1-40), ссылки не существует"
    else
      echo "  $d — ЗАНЯТ | источник: WHOIS, ссылки не существует"
      printf '%s' "$w" | grep -iE '^ *(registrar|created|creation date|paid-till|expir|state|status):' | sed 's/^ */      /' | head -4
    fi
  elif [ "$hc" = "404" ]; then
    echo "  $d — СВОБОДЕН | RDAP $url (404)"
  elif [ "$hc" = "200" ]; then
    if printf '%s' "$resp" | grep -qE 'redemption[Pp]eriod|pending[Dd]elete'; then
      echo "  $d — ЗАНЯТ, в процессе удаления: освободится через 30–75 дней | RDAP $url"
    else
      echo "  $d — ЗАНЯТ | RDAP $url (200)"
    fi
    printf '%s' "$resp" | grep -oE '"eventAction":"[^"]*","eventDate":"[^"]*"' | sed 's/^/      /' | head -3
  else
    echo "  $d — НЕ ПРОВЕРЕН (HTTP $hc) | $url"
  fi
done
echo "  ВНИМАНИЕ: свободный по RDAP домен может оказаться premium. Цену смотри у регистратора (чек-лист 6)."
echo

echo "== ИСТОРИЯ (web.archive.org) =="
for z in "${ZONES[@]}"; do
  d="$NAME_LC.$z"
  u="https://web.archive.org/cdx/search/cdx?url=$d&output=json&limit=3"
  out="$(body "$u" | tr -d "[:space:]")"
  if printf '%s' "$out" | grep -q 'urlkey'; then
    echo "  $d — ЕСТЬ СНИМКИ, посмотри, что было | $u"
  elif [ -z "$out" ] || [ "$out" = "[]" ]; then
    echo "  $d — снимков нет, домен не использовался | $u"
  else
    echo "  $d — НЕ ПРОВЕРЕН (неожиданный ответ архива) | $u"
  fi
done
echo

echo "== ПАКЕТЫ И МАГАЗИНЫ =="
check_404() {  # url, подпись
  local c; c="$(code "$1")"
  if [ "$c" = "404" ]; then echo "  $2 — свободно | $1"
  elif [ "$c" = "200" ]; then echo "  $2 — ЗАНЯТО | $1"
  else echo "  $2 — НЕ ПРОВЕРЕН (HTTP $c) | $1"; fi
}
check_404 "https://registry.npmjs.org/$NAME_LC" "npm"
check_404 "https://pypi.org/pypi/$NAME_LC/json" "PyPI"
check_404 "https://api.github.com/users/$NAME_LC" "GitHub"
check_404 "https://vk.com/$NAME_LC" "VK"
u="https://itunes.apple.com/search?term=$NAME_LC&entity=software&limit=5"
rc="$(body "$u" | grep -oE '"resultCount":[0-9]+' | head -1 | cut -d: -f2)"
echo "  App Store — совпадений: ${rc:-НЕ ПРОВЕРЕН} | $u"
echo
echo "== НЕ ПРОВЕРЯЕТСЯ МАШИННО (чек-листы 1-5) =="
echo "  Товарные знаки, ЕГРЮЛ, Google, Яндекс, Instagram, X, Telegram, Google Play."
echo "  Закрыты капчей, логином или отдают 200 на что угодно. Писать по ним результат"
echo "  без ручной проверки запрещено."
