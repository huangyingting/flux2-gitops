#!/usr/bin/env bash
#
# Fire and resolve a dummy alert to prometheus alertmanager
# Used to test alertmanager alerting
# 
# To use it
# kubectl port-forward svc/prometheus-kube-prometheus-alertmanager \
# -n motheus-kube-prometheus-alertmanager-0 -monitoring 9093:9093
# ./promalert.sh
#

name=$RANDOM
url='http://localhost:9093/api/v1/alerts'
bold=$(tput bold)
normal=$(tput sgr0)

generate_post_data() {
  cat <<EOF
[{
  "status": "$1",
  "labels": {
    "alertname": "${name}",
    "service": "ops-service",
    "severity":"warning",
    "instance": "${name}.example.com",
    "namespace": "default"
  },
  "annotations": {
    "summary": "Latency is high!",
    "description": "Latency is high!"
  },
  "generatorURL": "http://prometheus.example.com/$name"
  $2
  $3
}]
EOF
}

echo "${bold}Firing alert ${name} ${normal}"
printf -v startsAt ',"startsAt" : "%s"' $(date --rfc-3339=seconds | sed 's/ /T/')
POSTDATA=$(generate_post_data 'firing' "${startsAt}")
curl -i $url --data "$POSTDATA"
echo -e "\n"

echo "${bold}Press enter to resolve alert ${name} ${normal}"
read

echo "${bold}Sending resolved ${normal}"
printf -v endsAt ',"endsAt" : "%s"' $(date --rfc-3339=seconds | sed 's/ /T/')
POSTDATA=$(generate_post_data 'firing' "${startsAt}" "${endsAt}")
curl -i $url --data "$POSTDATA"
echo -e "\n"
