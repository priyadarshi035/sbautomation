#!/bin/sh

#Declaring an array to receive comma separated Service bus names as an input.
declare -a SERVICEBUS_NAMES

SERVICEBUS_NAMES=$1
AZURE_RESOURCEGROUP_NAME=""
AZURE_SUBSCRIPTION_NAME=""
SERVICEPRINCIPALID=""
SERVICEPRINCIPALKEY=""
TENANTID=""


#Login into Azure Subscription.
az login --service-principal -u $SERVICEPRINCIPALID -p $SERVICEPRINCIPALKEY --tenant $TENANTID
TOKEN=$(az account get-access-token --resource=https://servicebus.azure.net --query accessToken | tr -d '"')


purge_dlq_queue() {
    local DLQ_QUEUE_URL="https://${SERVICENAMESPACE}.servicebus.windows.net/tax-report-nf-params-lines/\$DeadLetterQueue/messages/head"
    local count=1000
    echo "cleaning the dead letters messages from the message queue..."
    while [[ ${count} -ge 0 ]]
    do
        local STATUS_CODE=$(curl -I -X DELETE -H "Authorization: Bearer $TOKEN" ${DLQ_QUEUE_URL} 2>/dev/null | head -n 1 | cut -d$' ' -f2)
        if [[ STATUS_CODE -ge 300 ]]; then
            echo "Exit dead letters message queue cleaning with code ${STATUS_CODE}"
            return 1
        elif [[ STATUS_CODE -eq 204 ]]; then
            echo "dead letters message queue has been cleaned"
            return 0
        fi
        let count--
    done
    echo "Exit with maxium number tries."
    return 1
}


# This function will be used to Capture Queues with Dead Letter Messages as well as Active Messages Over a Threshold.
Queues_Details () {
    echo "INFORM: Service Bus Name $1"
    Queue_list=$(az servicebus queue list --namespace-name $1 --resource-group $AZURE_RESOURCEGROUP_NAME -o json )
    
    # Filtering Queues which has DLQ Count more than 0.
    DEAD_LETTER_QUEUE=$(echo $Queue_list | jq 'map(select(.countDetails.deadLetterMessageCount>0))')
    DEAD_LETTER_QUEUE_LN=$(echo $DEAD_LETTER_QUEUE | jq '.| length')

    # Filtering Queues which has Active Messages Count more than 10k.
    ACTIVE_MESSAGE_QUEUE=$(echo $Queue_list | jq 'map(select(.countDetails.activeMessageCount>10000))')
    ACTIVE_MESSAGE_QUEUE_LN=$(echo $ACTIVE_MESSAGE_QUEUE | jq '.| length')


    # House keeping for Dead Letter Queue Messages.
    if [ "$DEAD_LETTER_QUEUE_LN" -eq 0 ];
    then
        echo "INFORM: There are NO Messages in the Dead Letter Queues!!!"

    else
        echo "INFORM: Dead Letter Queues List has been Received!!!"
        rm -rf MSOps_SB_DLQ_Details*
        echo $DEAD_LETTER_QUEUE | jq -c '.[]' | while read j;
        do
            
            DLQ_QUEUE_NAME=$(echo $j | jq .name)
            DLQ_QUEUE_COUNT=$(echo $j | jq .countDetails.deadLetterMessageCount)
            
            echo "Service Bus Name --> $1; DLQ Queue Name --> $DLQ_QUEUE_NAME; DLQ Message Count --> $DLQ_QUEUE_COUNT" >> MSOps_SB_DLQ_Details-$(date '+%d-%m-%Y').txt
            #check for the commands
            purge_dlq_queue $DLQ_QUEUE_NAME
            #az servicebus queue purge --resource-group $AZURE_RESOURCEGROUP_NAME --namespace-name $1 --queue-name $DLQ_QUEUE_NAME
            if [ $? -ne 0 ] 
            then
                echo "ERROR: The Deletion of Messages from DEAD LETTER QUEUE Failed!!!"
            fi
        done

    fi

    # Noting Down the Details of Queues with Active Messages greater than 10k
    if [ "$ACTIVE_MESSAGE_QUEUE_LN" -eq 0 ];
    then
        echo "INFORM: There are NO Queues with Active Messages greater than 10k!!!"
        exit 1
    else
        echo "INFORM: The Queue Details with Active Messages greater than 10k have been saved in Excel for Reference!!!"
        rm -rf MSOps_SB_AM_Details*
        echo $ACTIVE_MESSAGE_QUEUE | jq -c '.[]' | while read k;
        do
            AM_QUEUE_NAME=$(echo $k | jq .name)
            AM_QUEUE_COUNT=$(echo $j | jq .countDetails.activeMessageCount)
            echo "Service Bus Name --> $1; Active Message Queue Name --> $AM_QUEUE_NAME; Active Message Count --> $AM_QUEUE_COUNT" >> MSOps_SB_AM_Details-$(date '+%d-%m-%Y').txt
            #check for the commands
            #az servicebus queue purge --resource-group $AZURE_RESOURCEGROUP_NAME --namespace-name $1 --queue-name $QUEUE_NAME
            
            if [ $? -ne 0 ] 
            then
                echo "ERROR: The Deletion of Messages from DEAD LETTER QUEUE Failed!!!"
            fi

        done

    fi

}


# Main Code Snippet from which Functions are called
if [ $# -eq 0 ];
then
    echo "ERROR: Comma Separated Service Bus Names are Missing"
    exit 1
else
    echo "INFORM: Service Bus Names for Maintenance are Received"

    #Separate the Input received based on Comma De-Limiter and Push the Values in the Array Declared Above.
    IFS=',' read -ra SERVICEBUS_NAMES <<< "$1"
    for i in "${SERVICEBUS_NAMES[@]}"; 
        do
            #Calling the Function to get details of Queues.
            Queues_Details $i
            
        done
fi
