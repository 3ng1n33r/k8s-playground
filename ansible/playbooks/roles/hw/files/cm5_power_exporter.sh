#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C

OUT="/opt/node_exporter/textfile_collector/cm5_power.prom"
BOARD="${CM5_BOARD:-$(hostname -s)}"
DIR="$(dirname "$OUT")"

mkdir -p "$DIR" || exit 1

# Не допускаем параллельного выполнения одного сборщика.
exec 9>"${OUT}.lock"
flock -n 9 || exit 0

tmp="$(mktemp "${OUT}.tmp.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT

write_metrics() {
    local success="$1"
    local now="$2"

    {
        echo '# HELP cm5_power_collector_success 1 if the latest collection succeeded.'
        echo '# TYPE cm5_power_collector_success gauge'
        printf 'cm5_power_collector_success{board="%s"} %s\n' "$BOARD" "$success"

        echo '# HELP cm5_power_last_success_timestamp_seconds Unix time of last successful collection.'
        echo '# TYPE cm5_power_last_success_timestamp_seconds gauge'
        printf 'cm5_power_last_success_timestamp_seconds{board="%s"} %s\n' "$BOARD" "$now"
    } > "$tmp"
}

# Получить частоту тактового генератора в MHz.
read_clock() {
    local clock="$1"
    local output
    local hz

    output="$(timeout 3s vcgencmd measure_clock "$clock" 2>/dev/null)" || return 1

    if [[ "$output" =~ frequency\([0-9]+\)=([0-9]+) ]]; then
        hz="${BASH_REMATCH[1]}"
        awk -v hz="$hz" 'BEGIN { printf "%.3f", hz / 1000000 }'
    else
        return 1
    fi
}

# Получить температуру SoC в Celsius.
read_temperature() {
    local output
    local temperature

    output="$(timeout 3s vcgencmd measure_temp 2>/dev/null)" || return 1

    if [[ "$output" =~ temp=([-+]?[0-9]*\.?[0-9]+) ]]; then
        temperature="${BASH_REMATCH[1]}"
        printf '%s\n' "$temperature"
    else
        return 1
    fi
}

# Прочитать состояние throttling.
throttled_out="$(timeout 3s vcgencmd get_throttled 2>/dev/null)" || {
    write_metrics 0 0
    mv -f "$tmp" "$OUT"
    exit 0
}

if [[ "$throttled_out" =~ throttled=0x([[:xdigit:]]+) ]]; then
    hex="${BASH_REMATCH[1]}"
    throttled=$((16#$hex))
else
    write_metrics 0 0
    mv -f "$tmp" "$OUT"
    exit 0
fi

# Прочитать ADC PMIC.
adc_out="$(timeout 5s vcgencmd pmic_read_adc 2>/dev/null)" || {
    write_metrics 0 0
    mv -f "$tmp" "$OUT"
    exit 0
}

# Дополнительные метрики.
# Ошибка получения отдельной метрики не прерывает сбор.
arm_clock="$(read_clock arm)" || arm_clock=""
core_clock="$(read_clock core)" || core_clock=""
temperature="$(read_temperature)" || temperature=""

now="$(date +%s)"
write_metrics 1 "$now"

{
    echo
    echo '# HELP cm5_pmic_voltage_volts PMIC rail voltage in volts.'
    echo '# TYPE cm5_pmic_voltage_volts gauge'
    echo "$adc_out" | awk -v board="$BOARD" '
        /^[[:space:]]*[[:alnum:]_]+[[:space:]]+volt\([0-9]+\)=/ {
            rail = $1
            sub(/_V$/, "", rail)
            value = $0
            sub(/^.*volt\([0-9]+\)=/, "", value)
            sub(/V[[:space:]]*$/, "", value)
            if (value ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/)
                printf "cm5_pmic_voltage_volts{board=\"%s\",rail=\"%s\"} %s\n", board, rail, value
        }
    '

    echo
    echo '# HELP cm5_pmic_current_amperes PMIC rail current in amperes.'
    echo '# TYPE cm5_pmic_current_amperes gauge'
    echo "$adc_out" | awk -v board="$BOARD" '
        /^[[:space:]]*[[:alnum:]_]+[[:space:]]+current\([0-9]+\)=/ {
            rail = $1
            sub(/_A$/, "", rail)
            value = $0
            sub(/^.*current\([0-9]+\)=/, "", value)
            sub(/A[[:space:]]*$/, "", value)
            if (value ~ /^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/)
                printf "cm5_pmic_current_amperes{board=\"%s\",rail=\"%s\"} %s\n", board, rail, value
        }
    '

    echo
    echo '# HELP cm5_clock_frequency_mhz Clock frequency in MHz.'
    echo '# TYPE cm5_clock_frequency_mhz gauge'

    if [[ -n "$arm_clock" ]]; then
        printf 'cm5_clock_frequency_mhz{board="%s",clock="arm"} %s\n' \
            "$BOARD" "$arm_clock"
    fi

    if [[ -n "$core_clock" ]]; then
        printf 'cm5_clock_frequency_mhz{board="%s",clock="core"} %s\n' \
            "$BOARD" "$core_clock"
    fi

    echo
    echo '# HELP cm5_temperature_celsius SoC temperature in degrees Celsius.'
    echo '# TYPE cm5_temperature_celsius gauge'

    if [[ -n "$temperature" ]]; then
        printf 'cm5_temperature_celsius{board="%s"} %s\n' \
            "$BOARD" "$temperature"
    fi

    echo
    echo '# HELP cm5_throttled_raw Raw bitmask from vcgencmd get_throttled.'
    echo '# TYPE cm5_throttled_raw gauge'
    printf 'cm5_throttled_raw{board="%s"} %s\n' "$BOARD" "$throttled"

    echo
    echo '# HELP cm5_throttled_status Whether a throttling condition bit is set.'
    echo '# TYPE cm5_throttled_status gauge'

    for spec in \
        'undervoltage_detected:0' \
        'frequency_capped:1' \
        'currently_throttled:2' \
        'soft_temperature_limit_active:3' \
        'undervoltage_occurred:16' \
        'frequency_capping_occurred:17' \
        'throttling_occurred:18' \
        'soft_temperature_limit_occurred:19'
    do
        reason="${spec%%:*}"
        bit="${spec##*:}"
        value=$(( (throttled >> bit) & 1 ))
        printf 'cm5_throttled_status{board="%s",reason="%s"} %s\n' \
            "$BOARD" "$reason" "$value"
    done
} >> "$tmp"

# Файл появляется целиком, без промежуточного состояния.
mv -f "$tmp" "$OUT"
trap - EXIT
