#!/usr/bin/env bash
# monitor.sh — Consumo e temperatura Raspberry Pi 5
# Uso: ./monitor.sh [secondi]  (default: 30)

DURATA=${1:-30}
echo "Monitoraggio per ${DURATA} secondi..."
echo "Ora        Watt (presa)  CPU Core    Temperatura"
echo "---------- ------------ ----------- -----------"

for i in $(seq 1 "$DURATA"); do
  DATA=$(vcgencmd pmic_read_adc)
  TEMP=$(vcgencmd measure_temp | grep -oE '[0-9.]+' | head -1)

  RISULTATO=$(echo "$DATA" | awk '
    function v(s) { split(s,a,"="); gsub(/[A-Za-z]/,"",a[2]); return a[2]+0 }
    /3V7_WL_SW_A/ { awl=v($0) }  /3V7_WL_SW_V/ { vwl=v($0) }
    /3V3_SYS_A/   { a33=v($0) }  /3V3_SYS_V/   { v33=v($0) }
    /1V8_SYS_A/   { a18=v($0) }  /1V8_SYS_V/   { v18=v($0) }
    /DDR_VDD2_A/  { ad2=v($0) }  /DDR_VDD2_V/  { vd2=v($0) }
    /DDR_VDDQ_A/  { adq=v($0) }  /DDR_VDDQ_V/  { vdq=v($0) }
    /1V1_SYS_A/   { a11=v($0) }  /1V1_SYS_V/   { v11=v($0) }
    /0V8_SW_A/    { a08=v($0) }  /0V8_SW_V/    { v08=v($0) }
    /VDD_CORE_A/  { acore=v($0) } /VDD_CORE_V/ { vcore=v($0) }
    /0V8_AON_A/   { aaon=v($0) }  /0V8_AON_V/  { vaon=v($0) }
    /HDMI_A/      { ahdmi=v($0) } /HDMI_V/     { vhdmi=v($0) }
    END {
      tot = vwl*awl + v33*a33 + v18*a18 + vd2*ad2 + vdq*adq + v11*a11 + v08*a08 + vcore*acore + vaon*aaon + vhdmi*ahdmi
      wall  = tot / 0.85
      core  = vcore * acore
      printf "%.2f %.2f", wall, core
    }')

  WALL=$(echo "$RISULTATO" | awk '{print $1}')
  CORE=$(echo "$RISULTATO" | awk '{print $2}')

  echo "$(date +%H:%M:%S)   ${WALL}W         ${CORE}W       ${TEMP}°C"
  sleep 1
done

echo ""
echo "Fine monitoraggio."
