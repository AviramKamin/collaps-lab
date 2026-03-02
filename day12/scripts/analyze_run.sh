#!/usr/bin/env bash
set -euo pipefail

RUN="$1"

if [ ! -d "$RUN" ]; then
  echo "Usage: $0 <run_dir>"
  exit 1
fi

HB_MARKS="$RUN/heartbeat_marks.log"
HB_LOG="$RUN/heartbeat.log"

if [ ! -f "$HB_MARKS" ] || [ ! -f "$HB_LOG" ]; then
  echo "Missing heartbeat files in $RUN"
  exit 1
fi

awk '
function pct(arr,n,p,  idx){
  idx=int(n*p)
  if(idx<1) idx=1
  if(idx>n) idx=n
  return arr[idx]
}

NR==FNR {
  mark[$2]=$1
  next
}

{
  ts=$1
  dt=$2

  for (c=1;c<=3;c++) {
    if (ts>=mark["C"c"_RECOVERY_R2_START"] &&
        ts<=mark["C"c"_RECOVERY_R2_END"]) {
      a[++n]=dt
      if (dt > 200000000) spikes++
    }
  }
}

END{
  if(n==0){
    print "count=0 spikes=0"
    exit
  }

  # simple bubble sort (portable)
  for(i=1;i<=n;i++){
    for(j=i+1;j<=n;j++){
      if(a[i] > a[j]){
        tmp=a[i]
        a[i]=a[j]
        a[j]=tmp
      }
    }
  }

  p50=pct(a,n,0.50)
  p95=pct(a,n,0.95)
  p99=pct(a,n,0.99)

  printf "count=%d\n", n
  printf "spikes_gt_200ms=%d\n", spikes+0
  printf "p50_ns=%d\n", p50
  printf "p95_ns=%d\n", p95
  printf "p99_ns=%d\n", p99
  printf "max_ns=%d\n", a[n]
}
' "$HB_MARKS" "$HB_LOG"
