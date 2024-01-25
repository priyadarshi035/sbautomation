#!/bin/bash



SERVICEBUS_NAMES="spstpbussv001"

purge_dlq_topic() {
    local DLQ_TOPIC_URL="https://${SERVICEBUS_NAMES}.servicebus.windows.net/$1/subscriptions/$2/\$DeadLetterQueue/messages/head"
    local count=$3
    
    echo "INFORM: Cleaning the dead letters messages from the Topic..."
    while [[ ${count} -ge 0 ]]
    do
	local STATUS_CODE=$(curl -I -X DELETE -H "Authorization: Bearer $TOKEN" ${DLQ_TOPIC_URL} 2>/dev/null | head -n 1 | cut -d$' ' -f2)
	if [[ STATUS_CODE -ge 300 ]]; then
            echo "ERROR: Exit dead letters message Topic cleaning with code ${STATUS_CODE}"
            return 1
        elif [[ STATUS_CODE -eq 204 ]]; then
            echo "INFORM: All Messages from Dead letters message Topic $1 has been cleaned"
            return 0
        fi
        let count--
    done
}




TOPIC_LIST=$(az servicebus topic list --namespace-name spstpbussv001 --resource-group SAP-STT-RG-APPS-PROD -o json | .jq '.[].name')

for i in ${TOPIC_LIST[@]}
do

#   TOPIC_NAME=$(echo $i | tr -d '"')
TOPIC_NAME="sbt-supplier-saz-other"
  SUBSCRIPTION_DETAILS=$(az servicebus topic subscription list --namespace-name spstpbussv001 --resource-group SAP-STT-RG-APPS-PROD --topic-name $TOPIC_NAME -o json | .jq 'map(select(.countDetails.deadLetterMessageCount>0))')
  SUBSCRIPTION_DETAILS_LN=$(echo $SUBSCRIPTION_DETAILS | .jq '.| length')
  

#> topic-test.json
  if [ "$SUBSCRIPTION_DETAILS_LN" -eq 0 ]; then
    echo "INFORM: There are NO Messages in the Dead Letter Queues for topic $TOPIC_NAME !!!"
  else
    echo "INFORM: Topic: $TOPIC_NAME with Dead Letter Queues Message has been Received & Deletion is in Progress!!!"
    echo $SUBSCRIPTION_DETAILS | .jq -c '.[]' | while read j;
        do         
            SUBSCRIPTION_NAME=$(echo $j | .jq .name)
            DLQ_TOPIC_COUNT=$(echo $j | .jq .countDetails.deadLetterMessageCount)
            #echo Topic: $TOPIC_NAME Subscription Name: $SUBSCRIPTION_NAME DLQ Count: $DLQ_TOPIC_COUNT >> topic-test.json
            purge_dlq_topic $TOPIC_NAME $SUBSCRIPTION_NAME $DLQ_TOPIC_COUNT
            
        done

  fi
done
